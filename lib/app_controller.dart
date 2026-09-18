import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/account_db.dart';
import 'services/io_helpers.dart';
import 'services/porn91_service.dart';
import 'services/proxy_overrides.dart';
import 'services/x_following_service.dart';
import 'services/x_trends_service.dart';
import 'services/x_video_service.dart';

class AppController extends ChangeNotifier {
  static const _sexInactiveDays = 180;
  static const sexVideoMinDurationSeconds = 120;
  static const sexVideoMaxDurationSeconds = 1800;
  static const monthlyBestDays = <int>{1, 10, 20};

  AppSettings settings = AppSettings();
  final List<DownloadTask> tasks = <DownloadTask>[];
  final AccountDb accountDb = AccountDb();
  bool ready = false;
  String? loadError;
  bool _scheduledRunning = false;
  bool _scheduledJob = false;

  static File get _scheduledJobFlag {
    final home = Platform.environment['HOME'] ?? IoHelpers.homeDir;
    return File('$home/.media_downloader_scheduled_job');
  }

  XTrendsService get xTrends => XTrendsService(settings);
  XFollowingService get xFollowingService => XFollowingService(settings);
  XVideoService get xVideo => XVideoService(settings);
  Porn91Service? _porn91;
  Porn91Service get porn91 => _porn91 ??= Porn91Service(settings);

  int get activeCount => tasks
      .where((task) =>
          task.status == TaskStatus.running || task.status == TaskStatus.queued)
      .length;

  Future<void> init() async {
    _scheduledJob = _consumeScheduledJobFlag();
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
    if (loadError == null) {
      await runScheduledDownloads();
    }
    if (_scheduledJob) {
      await _waitUntilDownloadsIdle();
      exit(0);
    }
  }

  bool _consumeScheduledJobFlag() {
    final file = _scheduledJobFlag;
    if (!file.existsSync()) {
      return false;
    }
    try {
      file.deleteSync();
    } catch (_) {}
    return true;
  }

  Future<void> _waitUntilDownloadsIdle() async {
    final deadline = DateTime.now().add(const Duration(hours: 6));
    while (DateTime.now().isBefore(deadline)) {
      if (activeCount <= 0 && !_scheduledRunning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (activeCount <= 0 && !_scheduledRunning) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// 启动时调用；之后定时任务也可直接调这个方法。
  /// 当前分类是 sex 时先下图片再下视频；1/10/20 号再下一键每月最佳。
  Future<void> runScheduledDownloads({DateTime? now}) async {
    if (_scheduledRunning || !settings.showsCategory(XAccount.sexCategoryKey)) {
      return;
    }
    _scheduledRunning = true;
    try {
      try {
        await _downloadSpecialPhotos();
      } catch (_) {}
      try {
        await _downloadSpecialVideos();
      } catch (_) {}
      if (monthlyBestDays.contains((now ?? DateTime.now()).day)) {
        try {
          await _downloadMonthlyBest();
        } catch (_) {}
      }
    } finally {
      _scheduledRunning = false;
    }
  }

  Future<void> _downloadSpecialPhotos() async {
    final names = await visibleUsernames(
      specialOnly: true,
      mediaPage: AppPage.xPhotos,
    );
    if (names.isEmpty) {
      return;
    }
    final batch = await xFollowingService.fetchPhotoFeed(names);
    final accountMap = await accountDb.loadMap();
    final photos = _flattenPhotos(batch.posts, accountMap: accountMap);
    final load = settings.photoLoad;
    final seen = <String>{};
    for (final item in photos) {
      if (!load.allowsLikes(item.post.likes)) {
        continue;
      }
      final url = _photoUrl(item.media);
      if (url.isEmpty || !seen.add(url)) {
        continue;
      }
      if (isInDownloadList(url) || findExistingDownload(url) != null) {
        continue;
      }
      await downloadDirectMedia(
        url: url,
        username: item.post.username,
        displayName: item.post.displayName,
        ext: _photoExtFromUrl(url),
      );
    }
  }

  Future<void> _downloadSpecialVideos() async {
    final accounts = await visibleAccounts(
      specialOnly: true,
      mediaPage: AppPage.x,
    );
    if (accounts.isEmpty) {
      return;
    }
    final accountMap = <String, XAccount>{
      for (final account in accounts) account.username.toLowerCase(): account,
    };
    final batch = await xFollowingService.fetchVideoFeed(
      accounts.map((account) => account.username).toList(),
    );
    final videos = _flattenVideos(batch.posts, accountMap: accountMap);
    final load = settings.videoLoad;
    final seen = <String>{};
    for (final item in videos) {
      final key = _postKey(item.post);
      final url = item.post.url.trim();
      if (!load.allowsLikes(item.post.likes)) {
        continue;
      }
      if (key.isEmpty || url.isEmpty || !seen.add(key)) {
        continue;
      }
      if (activeTaskFor(url) != null || findExistingDownload(url) != null) {
        continue;
      }
      if (await findExistingPostVideoPath(url) != null) {
        continue;
      }
      await downloadVideo(
        url: url,
        title: item.post.text,
        quality: VideoQuality.best,
      );
    }
  }

  Future<void> _downloadMonthlyBest() async {
    final videos = await porn91.fetchTopVideos();
    for (final video in videos) {
      if (activeTaskFor(video.pageUrl) != null) {
        continue;
      }
      if (findExistingDownload(video.pageUrl) != null) {
        continue;
      }
      if (await porn91.hasDownloaded(video)) {
        continue;
      }
      await downloadPorn91(video);
    }
  }

  List<_JobMedia> _flattenPhotos(
    List<XPost> posts, {
    required Map<String, XAccount> accountMap,
  }) {
    final photos = <_JobMedia>[];
    for (final raw in posts) {
      var post = raw;
      final account = accountMap[post.username.toLowerCase()];
      if (account != null &&
          (post.avatarUrl.isEmpty || post.authorName.isEmpty)) {
        post = post.copyWith(
          avatarUrl: post.avatarUrl.isNotEmpty ? post.avatarUrl : account.avatarUrl,
          authorName: post.authorName.isNotEmpty ? post.authorName : account.name,
        );
      }
      for (final media in post.media) {
        if (media.kind == XMediaKind.photo) {
          photos.add(_JobMedia(post: post, media: media));
        }
      }
    }
    photos.sort((a, b) => b.post.likes.compareTo(a.post.likes));
    final load = settings.photoLoad;
    final postCounts = <String, int>{};
    final keptPosts = <String>{};
    return photos.where((item) {
      if (!load.allowsLikes(item.post.likes)) {
        return false;
      }
      final postId = _postKey(item.post);
      if (postId.isNotEmpty && keptPosts.contains(postId)) {
        return true;
      }
      final key = item.post.username.toLowerCase();
      final n = postCounts[key] ?? 0;
      if (n >= load.perUser) {
        return false;
      }
      postCounts[key] = n + 1;
      if (postId.isNotEmpty) {
        keptPosts.add(postId);
      }
      return true;
    }).toList();
  }

  List<_JobMedia> _flattenVideos(
    List<XPost> posts, {
    required Map<String, XAccount> accountMap,
  }) {
    final videos = <_JobMedia>[];
    for (final raw in posts) {
      var post = raw;
      final account = accountMap[post.username.toLowerCase()];
      if (account != null &&
          (post.avatarUrl.isEmpty || post.authorName.isEmpty)) {
        post = post.copyWith(
          avatarUrl: post.avatarUrl.isNotEmpty ? post.avatarUrl : account.avatarUrl,
          authorName: post.authorName.isNotEmpty ? post.authorName : account.name,
        );
      }
      for (final media in post.media) {
        if (!allowsVideoTabMedia(account, media)) {
          continue;
        }
        videos.add(_JobMedia(post: post, media: media));
      }
    }
    videos.sort((a, b) => b.post.likes.compareTo(a.post.likes));
    final load = settings.videoLoad;
    final counts = <String, int>{};
    return videos.where((item) {
      if (!load.allowsLikes(item.post.likes)) {
        return false;
      }
      final key = item.post.username.toLowerCase();
      final n = counts[key] ?? 0;
      if (n >= load.perUser) {
        return false;
      }
      counts[key] = n + 1;
      return true;
    }).toList();
  }

  String _postKey(XPost post) {
    final id = post.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return post.url.trim();
  }

  String _photoUrl(XMedia media) {
    final original = media.originalUrl.trim();
    if (original.isNotEmpty) {
      return original;
    }
    return media.url.trim();
  }

  String _photoExtFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final format = uri?.queryParameters['format']?.toLowerCase() ?? '';
    final path = (uri?.path ?? url).toLowerCase();
    final hay = '$path $format';
    if (hay.contains('png')) {
      return '.png';
    }
    if (hay.contains('gif')) {
      return '.gif';
    }
    if (hay.contains('webp')) {
      return '.webp';
    }
    return '.jpg';
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

  /// 当前打开的分类目录名。下载的图片/视频都进这个分类，不建「未分类」。
  String downloadFolderCategory({String? accountCategory}) {
    final visible = settings.visibleCategories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final accountKey = (accountCategory ?? '').trim();
    if (accountKey.isNotEmpty) {
      for (final item in visible) {
        if (item.toLowerCase() == accountKey.toLowerCase() ||
            XAccount.categoryLabel(item) ==
                XAccount.categoryLabel(accountKey)) {
          return XAccount.categoryLabel(item);
        }
      }
    }
    if (visible.isNotEmpty) {
      return XAccount.categoryLabel(visible.first);
    }
    if (accountKey.isNotEmpty) {
      final label = XAccount.categoryLabel(accountKey);
      if (label.isNotEmpty && label != '未分类') {
        return label;
      }
    }
    for (final item in settings.categories) {
      final key = item.trim();
      if (key.isEmpty) {
        continue;
      }
      final label = XAccount.categoryLabel(key);
      if (label.isNotEmpty && label != '未分类') {
        return label;
      }
    }
    return XAccount.categoryLabel(followCategory);
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

  Future<CategoryAssignResult> addUsernamesToCategory(
    Iterable<String> usernames, {
    required String category,
  }) async {
    final key = category.trim().toLowerCase();
    await ensureCategory(key, show: key.isNotEmpty);
    final names = <String>[];
    final seen = <String>{};
    for (final raw in usernames) {
      final username = XFollowingService.extractUsername(raw);
      if (username == null || !seen.add(username.toLowerCase())) {
        continue;
      }
      names.add(username);
    }
    if (names.isEmpty) {
      return CategoryAssignResult(followed: 0, updated: 0, category: key);
    }
    final following = settings.xFollowing
        .map((name) => name.trim().toLowerCase())
        .toSet();
    final stored = await accountDb.loadMap();
    final pending = <XAccount>[];
    final existing = <String>[];
    for (final name in names) {
      final lower = name.toLowerCase();
      if (following.contains(lower) && stored.containsKey(lower)) {
        existing.add(name);
        continue;
      }
      pending.add(
        XAccount(
          username: name,
          name: name,
          description: '',
          avatarUrl: '',
          profileUrl: 'https://x.com/$name',
          followers: 0,
          following: 0,
          tweets: 0,
          category: key,
        ),
      );
    }
    if (pending.isNotEmpty) {
      await followXAccounts(
        pending.map((account) => account.username).toList(),
      );
      await accountDb.insertIfAbsent(pending);
    }
    await accountDb.updateCategoryAll(
      <String>[
        ...pending.map((account) => account.username),
        ...existing,
      ],
      key,
    );
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
          try {
            final page = await xFollowingService.fetchPostsPage(username, count: 8);
            await recordLastPostAt(username, page.posts);
          } catch (_) {}
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
      next.visibleCategories = <String>[key];
    }
    await saveSettings(next);
  }

  bool showsAccount(XAccount account) {
    if (!settings.showsCategory(account.category)) {
      return false;
    }
    if (account.categoryKey == 'sex' && !_isSexRecentlyActive(account)) {
      return false;
    }
    return true;
  }

  bool _isSexRecentlyActive(XAccount account) {
    final last = account.lastPostAt;
    if (last <= 0) {
      return true;
    }
    final cutoff = DateTime.now().subtract(const Duration(days: _sexInactiveDays));
    return !DateTime.fromMillisecondsSinceEpoch(last).isBefore(cutoff);
  }

  bool isSexOnlyCategoryView() {
    final visible = settings.visibleCategories
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
    return visible.length == 1 && visible.first == 'sex';
  }

  bool shouldApplySexVideoDurationFilter(XAccount? account) {
    if (!settings.showsCategory('sex')) {
      return false;
    }
    if (isSexOnlyCategoryView()) {
      return true;
    }
    return account?.categoryKey == 'sex';
  }

  int mediaDurationSeconds(XMedia media) => media.durationSeconds;

  bool allowsVideoTabMedia(XAccount? account, XMedia media) {
    if (!media.isVideo) {
      return false;
    }
    if (!settings.videoLoad.allowsDuration(mediaDurationSeconds(media))) {
      return false;
    }
    if (!shouldApplySexVideoDurationFilter(account)) {
      return true;
    }
    if (media.kind != XMediaKind.video) {
      return false;
    }
    final seconds = mediaDurationSeconds(media);
    if (seconds <= 0) {
      return false;
    }
    return seconds >= sexVideoMinDurationSeconds &&
        seconds <= sexVideoMaxDurationSeconds;
  }

  Future<void> recordLastPostAt(String username, List<XPost> posts) async {
    final latest = XPost.latestMillis(posts);
    if (latest <= 0) {
      return;
    }
    await accountDb.updateLastPostAt(username, latest);
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

  final Set<String> _startingDownloads = <String>{};

  bool _sameSource(String a, String b) {
    final left = a.trim();
    final right = b.trim();
    if (left.isEmpty || right.isEmpty) {
      return false;
    }
    if (left == right) {
      return true;
    }
    final leftId = XVideoService.extractStatusId(left);
    final rightId = XVideoService.extractStatusId(right);
    return leftId != null && rightId != null && leftId == rightId;
  }

  Iterable<String> _sourceKeys(String source) sync* {
    final value = source.trim();
    if (value.isEmpty) {
      return;
    }
    yield value;
    final id = XVideoService.extractStatusId(value);
    if (id != null) {
      yield 'status:$id';
    }
  }

  bool _isStarting(String source) {
    return _sourceKeys(source).any(_startingDownloads.contains);
  }

  bool _markStarting(String source) {
    if (isInDownloadList(source)) {
      return false;
    }
    _startingDownloads.addAll(_sourceKeys(source));
    return true;
  }

  void _unmarkStarting(String source) {
    _startingDownloads.removeAll(_sourceKeys(source).toList());
  }

  bool isInDownloadList(String sourceUrl) {
    return _isStarting(sourceUrl) ||
        activeTaskFor(sourceUrl) != null ||
        findExistingDownload(sourceUrl) != null;
  }

  DownloadTask? activeTaskFor(String sourceUrl) {
    final source = sourceUrl.trim();
    if (source.isEmpty) {
      return null;
    }
    for (final task in tasks) {
      if (!_sameSource(task.sourceUrl, source)) {
        continue;
      }
      if (task.status == TaskStatus.running ||
          task.status == TaskStatus.queued) {
        return task;
      }
    }
    return null;
  }

  DownloadTask? findExistingDownload(String sourceUrl) {
    final source = sourceUrl.trim();
    if (source.isEmpty) {
      return null;
    }
    for (final task in tasks) {
      if (!_sameSource(task.sourceUrl, source) ||
          task.status != TaskStatus.done) {
        continue;
      }
      final path = task.savePath.trim();
      if (path.isEmpty || isDownloadHidden(path)) {
        continue;
      }
      if (File(path).existsSync()) {
        return task;
      }
    }
    return null;
  }

  Future<String?> findExistingPostVideoPath(String postUrl) async {
    final id = XVideoService.extractStatusId(postUrl);
    if (id == null) {
      return null;
    }
    final marker = '[$id].mp4';
    final roots = <String>{
      settings.downloadDir,
      '${settings.downloadDir}/MediaDownloader',
    };
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) {
        continue;
      }
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.isEmpty
            ? entity.path.split(RegExp(r'[\\/]')).last
            : entity.uri.pathSegments.last;
        if (!name.contains(marker)) {
          continue;
        }
        if (await entity.length() > 0) {
          return entity.path;
        }
      }
    }
    return null;
  }

  DownloadTask reuseDownload({
    required String title,
    required String sourceUrl,
    required String savePath,
  }) {
    final path = savePath.trim();
    final source = sourceUrl.trim();
    final cached = findExistingDownload(source);
    if (cached != null) {
      cached.alreadyDownloaded = true;
      return cached;
    }
    final task = DownloadTask(
      id: IoHelpers.uniqueId(),
      kind: DownloadKind.x,
      title: title.trim().isEmpty ? path : title.trim(),
      sourceUrl: source,
      status: TaskStatus.done,
      progress: 1,
      savePath: path,
    )..alreadyDownloaded = true;
    tasks.insert(0, task);
    notifyListeners();
    return task;
  }

  DownloadTask? _skipIfAlreadyDownloaded({
    required String sourceUrl,
    required String title,
  }) {
    final source = sourceUrl.trim();
    if (source.isEmpty) {
      return null;
    }
    final active = activeTaskFor(source);
    if (active != null) {
      return active;
    }
    final existing = findExistingDownload(source);
    if (existing != null) {
      existing.alreadyDownloaded = true;
      return existing;
    }
    return null;
  }

  Future<DownloadTask?> _skipPostIfAlreadyDownloaded({
    required String sourceUrl,
    required String title,
  }) async {
    final skipped = _skipIfAlreadyDownloaded(
      sourceUrl: sourceUrl,
      title: title,
    );
    if (skipped != null) {
      return skipped;
    }
    final path = await findExistingPostVideoPath(sourceUrl);
    if (path == null) {
      return null;
    }
    return reuseDownload(title: title, sourceUrl: sourceUrl, savePath: path);
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
    final user = username.trim().replaceFirst(RegExp(r'^@'), '');
    var name = displayName.trim();
    final title = name.isNotEmpty
        ? (user.isEmpty ? name : '$name @$user')
        : (user.isEmpty ? '视频' : '@$user');
    final skipped = _skipIfAlreadyDownloaded(sourceUrl: source, title: title);
    if (skipped != null) {
      return skipped;
    }
    if (!_markStarting(source)) {
      return _listedOrQueued(sourceUrl: source, title: title);
    }
    try {
      final again = _skipIfAlreadyDownloaded(sourceUrl: source, title: title);
      if (again != null) {
        return again;
      }
      final task = enqueue(title: title, sourceUrl: source);
      return await _run(task, () async {
        var accountCategory = '';
        if (user.isNotEmpty) {
          final account = await accountDb.get(user);
          if (account != null) {
            accountCategory = account.category;
            if (name.isEmpty) {
              name = account.name.trim();
            }
          }
        }
        final dir = await IoHelpers.ensurePhotoSaveDir(
          downloadDir: settings.downloadDir,
          category: downloadFolderCategory(accountCategory: accountCategory),
          isVideo: IoHelpers.isVideoFile('file$ext') ||
              ext.toLowerCase().contains('m4a'),
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
    } finally {
      _unmarkStarting(source);
    }
  }

  Future<DownloadTask> downloadPorn91(Porn91Video video) async {
    final source = video.pageUrl;
    final title = video.title.trim().isEmpty ? video.viewkey : video.title.trim();
    final skipped = _skipIfAlreadyDownloaded(sourceUrl: source, title: title);
    if (skipped != null) {
      return skipped;
    }
    if (await porn91.hasDownloaded(video)) {
      return _skippedPorn91(title: title, sourceUrl: source);
    }
    if (!_markStarting(source)) {
      return _listedOrQueued(sourceUrl: source, title: title);
    }
    try {
      final again = _skipIfAlreadyDownloaded(sourceUrl: source, title: title);
      if (again != null) {
        return again;
      }
      if (await porn91.hasDownloaded(video)) {
        return _skippedPorn91(title: title, sourceUrl: source);
      }
      final task = enqueue(title: title, sourceUrl: source);
      return await _run(task, () async {
        final dir = await IoHelpers.ensureMonthlyDownloadDir(settings.downloadDir);
        final path = await porn91.download(
          video: video,
          dir: dir.path,
          onProgress: (progress, speed) {
            task.progress = progress;
            task.speed = speed;
            notifyListeners();
          },
        );
        await porn91.markDownloaded(video);
        return path;
      });
    } finally {
      _unmarkStarting(source);
    }
  }

  Future<DownloadTask> downloadVideo({
    required String url,
    required String title,
    required VideoQuality quality,
  }) async {
    final source = url.trim();
    final skipped = _skipIfAlreadyDownloaded(sourceUrl: source, title: title);
    if (skipped != null) {
      return skipped;
    }
    if (!_markStarting(source)) {
      return _listedOrQueued(sourceUrl: source, title: title);
    }
    try {
      final existing = await _skipPostIfAlreadyDownloaded(
        sourceUrl: source,
        title: title,
      );
      if (existing != null) {
        return existing;
      }
      final task = enqueue(title: title, sourceUrl: source);
      return await _run(task, () async {
        var accountCategory = '';
        final username = XFollowingService.extractUsername(source) ?? '';
        if (username.isNotEmpty) {
          final account = await accountDb.get(username);
          if (account != null) {
            accountCategory = account.category;
          }
        }
        final dir = await IoHelpers.ensurePhotoSaveDir(
          downloadDir: settings.downloadDir,
          category: downloadFolderCategory(accountCategory: accountCategory),
          isVideo: true,
        );
        return xVideo.download(
          url: source,
          dir: dir.path,
          quality: quality,
          onProgress: (progress, speed) {
            task.progress = progress;
            task.speed = speed;
            notifyListeners();
          },
        );
      });
    } finally {
      _unmarkStarting(source);
    }
  }

  DownloadTask _listedOrQueued({
    required String sourceUrl,
    required String title,
  }) {
    return _skipIfAlreadyDownloaded(sourceUrl: sourceUrl, title: title) ??
        DownloadTask(
          id: IoHelpers.uniqueId(),
          kind: DownloadKind.x,
          title: title,
          sourceUrl: sourceUrl,
          status: TaskStatus.queued,
        );
  }

  DownloadTask _skippedPorn91({
    required String title,
    required String sourceUrl,
  }) {
    return DownloadTask(
      id: IoHelpers.uniqueId(),
      kind: DownloadKind.x,
      title: title,
      sourceUrl: sourceUrl,
      status: TaskStatus.done,
      progress: 1,
    )..alreadyDownloaded = true;
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

class _JobMedia {
  const _JobMedia({required this.post, required this.media});

  final XPost post;
  final XMedia media;
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
