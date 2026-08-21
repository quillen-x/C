import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/account_db.dart';
import 'services/io_helpers.dart';
import 'services/proxy_overrides.dart';
import 'services/x_following_service.dart';
import 'services/x_trends_service.dart';
import 'services/x_video_service.dart';

class AppController extends ChangeNotifier {
  AppSettings settings = AppSettings();
  final List<DownloadTask> tasks = <DownloadTask>[];
  final AccountDb accountDb = AccountDb();
  bool ready = false;
  String? loadError;

  XTrendsService get xTrends => XTrendsService(settings);
  XFollowingService get xFollowingService => XFollowingService(settings);
  XVideoService get xVideo => XVideoService(settings);

  int get activeCount => tasks
      .where((task) =>
          task.status == TaskStatus.running || task.status == TaskStatus.queued)
      .length;

  Future<void> init() async {
    try {
      await IoHelpers.init();
      settings = await IoHelpers.loadSettings();
      ProxyHttpOverrides.apply(
        settings.proxyEnabled ? settings.proxyAddress : null,
      );
      await IoHelpers.ensureDownloadDir(settings.downloadDir);
    } catch (error) {
      loadError = error.toString();
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> saveSettings(AppSettings next) async {
    settings = next;
    ProxyHttpOverrides.apply(
      settings.proxyEnabled ? settings.proxyAddress : null,
    );
    await IoHelpers.saveSettings(settings);
    await IoHelpers.ensureDownloadDir(settings.downloadDir);
    notifyListeners();
  }

  /// 设置里当前打开的分类。新增关注会归到这一类。
  String get followCategory {
    final visible = settings.visibleCategories
        .map((item) => item.trim())
        .toList();
    if (visible.isEmpty) {
      return '';
    }
    if (visible.length == 1) {
      return visible.first;
    }
    final named = visible.where((item) => item.isNotEmpty).toList();
    if (named.isEmpty) {
      return '';
    }
    return named.first;
  }

  XAccount taggedForFollow(XAccount account, {String? category}) {
    final key = (category ?? followCategory).trim().toLowerCase();
    return account.copyWith(category: key);
  }

  Future<XAccount> followAndSave(XAccount account, {String? category}) async {
    final tagged = taggedForFollow(account, category: category);
    if (tagged.category.trim().isNotEmpty) {
      await ensureCategory(tagged.category, show: true);
    }
    await followXAccount(tagged.username);
    await accountDb.upsert(tagged);
    await accountDb.updateCategory(tagged.username, tagged.category);
    return tagged;
  }

  Future<List<XAccount>> followAndSaveAll(
    List<XAccount> accounts, {
    String? category,
  }) async {
    if (accounts.isEmpty) {
      return <XAccount>[];
    }
    final tagged = accounts
        .map((account) => taggedForFollow(account, category: category))
        .toList();
    final cat = tagged.first.category.trim();
    if (cat.isNotEmpty) {
      await ensureCategory(cat, show: true);
    }
    await followXAccounts(
      tagged.map((account) => account.username).toList(),
    );
    await accountDb.upsertAll(tagged);
    for (final account in tagged) {
      await accountDb.updateCategory(account.username, account.category);
    }
    return tagged;
  }

  Future<CategoryAssignResult> addAccountsToCategory(
    List<XAccount> accounts, {
    required String category,
  }) async {
    final key = category.trim().toLowerCase();
    if (key.isEmpty) {
      throw StateError('请选择分类');
    }
    await ensureCategory(key, show: true);
    final following = settings.xFollowing
        .map((name) => name.trim().toLowerCase())
        .toSet();
    final pending = <XAccount>[];
    final existing = <XAccount>[];
    final seen = <String>{};
    for (final account in accounts) {
      final name = account.username.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) {
        continue;
      }
      final tagged = account.copyWith(category: key);
      if (following.contains(name.toLowerCase())) {
        existing.add(tagged);
      } else {
        pending.add(tagged);
      }
    }
    if (pending.isNotEmpty) {
      await followAndSaveAll(pending, category: key);
    }
    for (final account in existing) {
      await accountDb.upsert(account);
      await accountDb.updateCategory(account.username, account.category);
    }
    return CategoryAssignResult(
      followed: pending.length,
      updated: existing.length,
      category: key,
    );
  }

  Future<ProfileSyncResult> syncFollowingProfiles({
    required String category,
    required bool Function() isCanceled,
    required void Function(int done, int total, int failed, String current)
        onProgress,
  }) async {
    final key = category.trim().toLowerCase();
    final map = await accountDb.loadMap();
    final names = settings.xFollowing.where((name) {
      final account = map[name.toLowerCase()];
      final cat = (account?.category ?? '').trim().toLowerCase();
      return cat == key;
    }).toList();
    if (names.isEmpty) {
      return ProfileSyncResult.empty();
    }
    final existing = await accountDb.syncedUsernames();
    final pending = names
        .where((name) => !existing.contains(name.toLowerCase()))
        .toList();
    if (pending.isEmpty) {
      return ProfileSyncResult(
        pending: 0,
        failed: 0,
        stored: await accountDb.count(),
        alreadyDone: true,
      );
    }
    onProgress(0, pending.length, 0, '');
    var index = 0;
    var done = 0;
    var failed = 0;
    Future<void> worker() async {
      while (!isCanceled()) {
        if (index >= pending.length) {
          return;
        }
        final username = pending[index++];
        onProgress(done, pending.length, failed, username);
        try {
          XAccount account;
          try {
            account = await xFollowingService.fetchAccount(username);
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            account = await xFollowingService.fetchAccount(username);
          }
          final tagged = account.copyWith(category: category);
          await accountDb.upsert(tagged);
          await accountDb.updateCategory(tagged.username, tagged.category);
        } catch (_) {
          failed += 1;
        }
        done += 1;
        onProgress(done, pending.length, failed, username);
      }
    }

    await Future.wait(<Future<void>>[
      worker(),
      worker(),
      worker(),
      worker(),
    ]);
    return ProfileSyncResult(
      pending: pending.length,
      failed: failed,
      stored: await accountDb.count(),
      canceled: isCanceled(),
    );
  }

  Future<void> followXAccount(String username) async {
    await followXAccounts(<String>[username], prepend: true);
  }

  Future<void> followXAccounts(List<String> usernames, {bool prepend = false}) async {
    final next = settings.copy();
    final seen = next.xFollowing.map((item) => item.toLowerCase()).toSet();
    final added = <String>[];
    for (final raw in usernames) {
      final name = raw.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) {
        continue;
      }
      added.add(name);
    }
    if (added.isEmpty) {
      return;
    }
    next.xFollowing = prepend
        ? <String>[...added, ...next.xFollowing]
        : <String>[...next.xFollowing, ...added];
    await saveSettings(next);
  }

  Future<void> unfollowXAccount(String username) async {
    await unfollowXAccounts(<String>[username]);
  }

  Future<void> unfollowXAccounts(List<String> usernames) async {
    final lower = usernames
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (lower.isEmpty) {
      return;
    }
    final next = settings.copy();
    next.xFollowing = settings.xFollowing
        .where((item) => !lower.contains(item.toLowerCase()))
        .toList();
    if (next.xFollowing.length == settings.xFollowing.length) {
      return;
    }
    await saveSettings(next);
  }

  Future<int> purgeAccounts(List<String> usernames) async {
    if (usernames.isEmpty) {
      return 0;
    }
    await unfollowXAccounts(usernames);
    await accountDb.deleteUsernames(usernames);
    return usernames.length;
  }

  Future<void> ensureCategory(String category, {bool show = false}) async {
    final key = category.trim().toLowerCase();
    if (key.isEmpty) {
      return;
    }
    final exists = settings.categories.any(
      (item) => item.trim().toLowerCase() == key,
    );
    final shown = settings.visibleCategories.any(
      (item) => item.trim().toLowerCase() == key,
    );
    if (exists && (!show || shown)) {
      return;
    }
    final next = settings.copy();
    if (!exists) {
      next.categories = <String>[...next.categories, key];
    }
    if (show && !shown) {
      next.visibleCategories = <String>[...next.visibleCategories, key];
    }
    await saveSettings(next);
  }

  bool showsAccount(XAccount account) {
    return settings.showsCategory(account.category);
  }

  bool _allowsMedia(XAccount account, AppPage? mediaPage) {
    if (mediaPage == null || !mediaPage.isMediaHub) {
      return true;
    }
    return settings.mediaFor(account.category).allows(mediaPage);
  }

  Future<List<XAccount>> visibleAccounts({
    bool specialOnly = false,
    AppPage? mediaPage,
  }) async {
    final rows = await accountDb.loadAll();
    return rows.where((account) {
      if (specialOnly && !account.special) {
        return false;
      }
      return showsAccount(account) && _allowsMedia(account, mediaPage);
    }).toList();
  }

  Future<List<String>> visibleUsernames({
    List<String>? from,
    bool specialOnly = false,
    AppPage? mediaPage,
  }) async {
    final allowed = from ??
        (await accountDb.loadAll()).map((account) => account.username).toList();
    final map = await accountDb.loadMap();
    return allowed.where((username) {
      final account = map[username.toLowerCase()];
      if (account == null) {
        return !specialOnly &&
            settings.showsCategory('') &&
            (mediaPage == null ||
                !mediaPage.isMediaHub ||
                settings.mediaFor('').allows(mediaPage));
      }
      if (specialOnly && !account.special) {
        return false;
      }
      return showsAccount(account) && _allowsMedia(account, mediaPage);
    }).toList();
  }

  DownloadTask enqueue({
    required String title,
    required String sourceUrl,
  }) {
    final task = DownloadTask(
      id: IoHelpers.uniqueId(),
      kind: DownloadKind.x,
      title: title,
      sourceUrl: sourceUrl,
    );
    tasks.insert(0, task);
    notifyListeners();
    return task;
  }

  Future<void> recordDownloadedFile({
    required String title,
    required String path,
    String sourceUrl = '',
  }) async {
    final savePath = path.trim();
    if (savePath.isEmpty) {
      return;
    }
    await revealDownloadRecord(savePath);
    final exists = tasks.any((task) => task.savePath == savePath);
    if (!exists) {
      tasks.insert(
        0,
        DownloadTask(
          id: IoHelpers.uniqueId(),
          kind: DownloadKind.x,
          title: title.trim().isEmpty ? savePath : title.trim(),
          sourceUrl: sourceUrl,
          status: TaskStatus.done,
          progress: 1,
          savePath: savePath,
        ),
      );
    }
    notifyListeners();
  }

  void removeTask(String id) {
    tasks.removeWhere((task) => task.id == id);
    notifyListeners();
  }

  void removeTasksByPath(String path) {
    final target = path.trim();
    if (target.isEmpty) {
      return;
    }
    tasks.removeWhere((task) => task.savePath == target);
    notifyListeners();
  }

  void clearIdleTasks() {
    tasks.removeWhere(
      (task) =>
          task.status != TaskStatus.running && task.status != TaskStatus.queued,
    );
    notifyListeners();
  }

  bool isDownloadHidden(String path) {
    final target = path.trim();
    return target.isNotEmpty && settings.hiddenDownloads.contains(target);
  }

  Future<void> hideDownloadRecords(Iterable<String> paths) async {
    final hidden = List<String>.from(settings.hiddenDownloads);
    var changed = false;
    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty || hidden.contains(path)) {
        continue;
      }
      hidden.add(path);
      changed = true;
    }
    if (!changed) {
      return;
    }
    settings.hiddenDownloads = hidden;
    await IoHelpers.saveSettings(settings);
    notifyListeners();
  }

  Future<void> revealDownloadRecord(String path) async {
    final target = path.trim();
    if (target.isEmpty) {
      return;
    }
    final hidden = List<String>.from(settings.hiddenDownloads);
    if (!hidden.remove(target)) {
      return;
    }
    settings.hiddenDownloads = hidden;
    await IoHelpers.saveSettings(settings);
    notifyListeners();
  }

  DownloadTask? activeTaskFor(String sourceUrl) {
    final source = sourceUrl.trim();
    if (source.isEmpty) {
      return null;
    }
    for (final task in tasks) {
      if (task.sourceUrl == source &&
          (task.status == TaskStatus.running ||
              task.status == TaskStatus.queued)) {
        return task;
      }
    }
    return null;
  }

  Future<DownloadTask> downloadDirectMedia({
    required String url,
    String username = '',
    String displayName = '',
    String ext = '.mp4',
  }) async {
    final source = url.trim();
    if (source.isEmpty) {
      throw StateError('没有可下载的地址');
    }
    final existing = activeTaskFor(source);
    if (existing != null) {
      return existing;
    }
    final user = username.trim().replaceFirst(RegExp(r'^@'), '');
    var name = displayName.trim();
    final title = name.isNotEmpty
        ? (user.isEmpty ? name : '$name @$user')
        : (user.isEmpty ? '视频' : '@$user');
    final task = enqueue(title: title, sourceUrl: source);
    return _run(task, () async {
      var category = '未分类';
      if (user.isNotEmpty) {
        final account = await accountDb.get(user);
        if (account != null) {
          category = XAccount.categoryLabel(account.category);
          if (name.isEmpty) {
            name = account.name.trim();
          }
        }
      }
      final dir = await IoHelpers.ensurePhotoSaveDir(
        downloadDir: settings.downloadDir,
        category: category,
        username: user,
      );
      final stamp = IoHelpers.formatSavedStamp(DateTime.now());
      final label = IoHelpers.sanitizeFileName(
        name.isNotEmpty
            ? '${name}_$stamp'
            : (user.isNotEmpty ? '${user}_$stamp' : stamp),
      );
      final path = await IoHelpers.uniqueSavePath(
        dir: dir.path,
        label: label,
        ext: ext,
      );
      await IoHelpers.downloadFile(
        source,
        path,
        onProgress: (progress, speed) {
          task.progress = progress;
          task.speed = speed;
          notifyListeners();
        },
      );
      return path;
    });
  }

  Future<DownloadTask> downloadVideo({
    required String url,
    required String title,
    required VideoQuality quality,
  }) async {
    final task = enqueue(title: title, sourceUrl: url);
    return _run(task, () {
      return xVideo.download(
        url: url,
        dir: settings.downloadDir,
        quality: quality,
        onProgress: (progress, speed) {
          task.progress = progress;
          task.speed = speed;
          notifyListeners();
        },
      );
    });
  }

  Future<DownloadTask> _run(
    DownloadTask task,
    Future<String> Function() work,
  ) async {
    task.status = TaskStatus.running;
    task.progress = 0.02;
    notifyListeners();
    try {
      final path = await work();
      task.savePath = path;
      task.status = TaskStatus.done;
      task.progress = 1;
      task.speed = '';
      await revealDownloadRecord(path);
      notifyListeners();
      if (Platform.isIOS) {
        await IoHelpers.saveToPhotos(path);
      }
    } catch (error) {
      task.status = TaskStatus.failed;
      task.error = error.toString();
    }
    notifyListeners();
    return task;
  }

  Future<String> diagnose() async {
    final lines = <String>[
      '平台：${Platform.isIOS ? 'iPhone / iPad' : Platform.operatingSystem}',
      settings.proxyEnabled
          ? '代理：已启用 ${settings.proxyUrl}'
          : (Platform.isIOS
              ? '代理：未启用（iPhone 请先打开系统 VPN，如小火箭 / Stash）'
              : '代理：未启用（将直连，国内通常无法访问）'),
      '保存目录：${settings.downloadDir}',
    ];
    if (!Platform.isIOS) {
      final ffmpegOk = File(settings.ffmpegPath).existsSync();
      lines.add('ffmpeg：${ffmpegOk ? '已找到' : '未找到'}  ${settings.ffmpegPath}');
    }
    return lines.join('\n');
  }

  @override
  void dispose() {
    accountDb.close();
    super.dispose();
  }
}

class CategoryAssignResult {
  const CategoryAssignResult({
    required this.followed,
    required this.updated,
    required this.category,
  });

  final int followed;
  final int updated;
  final String category;

  int get total => followed + updated;
}

class ProfileSyncResult {
  ProfileSyncResult({
    required this.pending,
    required this.failed,
    required this.stored,
    this.canceled = false,
    this.alreadyDone = false,
  });

  factory ProfileSyncResult.empty() {
    return ProfileSyncResult(
      pending: 0,
      failed: 0,
      stored: 0,
      alreadyDone: false,
    );
  }

  final int pending;
  final int failed;
  final int stored;
  final bool canceled;
  final bool alreadyDone;
}
