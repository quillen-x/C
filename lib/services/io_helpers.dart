import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';

class IoHelpers {
  static const _mediaChannel = MethodChannel('media_downloader/media');

  static String get homeDir {
    return Platform.environment['HOME'] ?? Directory.systemTemp.path;
  }

  static Directory get supportDir {
    return Directory(
      '$homeDir/Library/Application Support/com.xujiapeng.mediaDownloader',
    );
  }

  static File get settingsFile {
    return File('${supportDir.path}/settings.json');
  }

  static String defaultDownloadDir() {
    if (Platform.isIOS) {
      return '$homeDir/Documents';
    }
    return '$homeDir/Downloads/MediaDownloader';
  }

  static Future<AppSettings> loadSettings() async {
    try {
      if (await settingsFile.exists()) {
        final text = await settingsFile.readAsString();
        final json = jsonDecode(text) as Map<String, dynamic>;
        final settings = AppSettings.fromJson(json);
        if (settings.downloadDir.trim().isEmpty || Platform.isIOS) {
          settings.downloadDir = defaultDownloadDir();
        }
        return settings;
      }
    } catch (_) {}
    return AppSettings(
      downloadDir: defaultDownloadDir(),
      proxyEnabled: !Platform.isIOS,
    );
  }

  static Future<void> saveSettings(AppSettings settings) async {
    await supportDir.create(recursive: true);
    await settingsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  static Future<Directory> ensureDownloadDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<List<File>> listSavedFiles(String dirPath) async {
    final dirs = <Directory>[Directory(dirPath)];
    if (Platform.isIOS) {
      dirs.add(Directory('$dirPath/MediaDownloader'));
    }
    final files = <File>[];
    final seen = <String>{};
    for (final dir in dirs) {
      if (!await dir.exists()) {
        continue;
      }
      final items = await dir.list(recursive: true, followLinks: false).toList();
      for (final item in items.whereType<File>()) {
        final name = item.uri.pathSegments.isEmpty
            ? ''
            : item.uri.pathSegments.last;
        if (name.startsWith('.') || !seen.add(item.path)) {
          continue;
        }
        final lower = name.toLowerCase();
        if (lower.endsWith('.mp4') ||
            lower.endsWith('.m4a') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.webp')) {
          files.add(item);
        }
      }
    }
    files.sort((a, b) {
      final at = a.lastModifiedSync();
      final bt = b.lastModifiedSync();
      return bt.compareTo(at);
    });
    return files;
  }

  static Future<bool> saveToPhotos(String path) async {
    if (!Platform.isIOS) {
      return false;
    }
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    try {
      final ok = await _mediaChannel.invokeMethod<bool>(
        'saveToPhotos',
        <String, String>{'path': path},
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static String savedMessage(String path) {
    if (Platform.isIOS) {
      return '已保存到「下载」，点开即可观看。';
    }
    return '下载完成：$path';
  }

  static bool isPlayable(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  static bool isVideoFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v');
  }

  static bool isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  static final Map<String, Future<File?>> _thumbPending = <String, Future<File?>>{};

  static Future<File?> videoThumbnail(String videoPath, {String ffmpegPath = ''}) {
    final pending = _thumbPending[videoPath];
    if (pending != null) {
      return pending;
    }
    final future = _makeVideoThumbnail(videoPath, ffmpegPath);
    _thumbPending[videoPath] = future;
    return future.whenComplete(() => _thumbPending.remove(videoPath));
  }

  static Future<File?> _makeVideoThumbnail(String videoPath, String ffmpegPath) async {
    final video = File(videoPath);
    if (!await video.exists()) {
      return null;
    }
    final dir = Directory('${supportDir.path}/thumbs');
    await dir.create(recursive: true);
    final name = video.uri.pathSegments.isEmpty
        ? '${videoPath.hashCode.abs()}.jpg'
        : '${videoPath.hashCode.abs()}_${video.uri.pathSegments.last}.jpg';
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final thumb = File('${dir.path}/$safe');
    try {
      if (await thumb.exists()) {
        final videoTime = await video.lastModified();
        final thumbTime = await thumb.lastModified();
        if (!thumbTime.isBefore(videoTime)) {
          return thumb;
        }
      }
    } catch (_) {}
    final bin = ffmpegPath.trim().isEmpty ? 'ffmpeg' : ffmpegPath.trim();
    try {
      final result = await Process.run(bin, <String>[
        '-y',
        '-ss',
        '0.4',
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=360:-2',
        '-q:v',
        '4',
        thumb.path,
      ]);
      if (result.exitCode == 0 && await thumb.exists() && await thumb.length() > 0) {
        return thumb;
      }
    } catch (_) {}
    return await thumb.exists() ? thumb : null;
  }

  static Future<void> openPreview(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }
    if (Platform.isIOS) {
      await _mediaChannel.invokeMethod<bool>(
        'openPreview',
        <String, String>{'path': path},
      );
      return;
    }
    await Process.run('open', [path]);
  }

  static Future<void> openInFinder(String path) async {
    final target = path.isEmpty ? defaultDownloadDir() : path;
    if (Platform.isIOS) {
      final file = File(target);
      if (await file.exists()) {
        await Share.shareXFiles(<XFile>[XFile(target)]);
        return;
      }
      final files = await listSavedFiles(defaultDownloadDir());
      if (files.isNotEmpty) {
        await Share.shareXFiles(
          files.take(5).map((item) => XFile(item.path)).toList(),
        );
        return;
      }
      await Share.share('请打开「文件」App → 浏览 → 我的 iPhone → C');
      return;
    }
    await Process.run('open', [target]);
  }

  static Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Map<String, String> processEnv() {
    final current = Map<String, String>.from(Platform.environment);
    const extra = '/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin';
    final oldPath = current['PATH'] ?? '';
    current['PATH'] = '$extra:$oldPath';
    return current;
  }

  static String uniqueId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  static String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String formatSavedStamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}_${two(time.hour)}-${two(time.minute)}-${two(time.second)}';
  }

  static String formatSavedStampLabel(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  static Future<Directory> ensurePhotoSaveDir({
    required String downloadDir,
    required String category,
    required String username,
  }) {
    final cat = sanitizeFileName(
      category.trim().isEmpty ? '未分类' : category.trim(),
    );
    var user = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (user.isEmpty) {
      user = 'unknown';
    }
    return ensureDownloadDir('$downloadDir/${sanitizeFileName(cat)}/${sanitizeFileName(user)}');
  }

  static SavedFileInfo describeSavedFile(File file, String downloadDir) {
    var category = '';
    var username = '';
    final root = downloadDir.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
    final path = file.path.replaceAll(r'\', '/');
    if (root.isNotEmpty && path.startsWith(root)) {
      final rel = path.substring(root.length).replaceFirst(RegExp(r'^/+'), '');
      final parts = rel.split('/');
      if (parts.length >= 4 && parts.first.toLowerCase() == 'mediadownloader') {
        category = parts[1];
        username = parts[2];
      } else if (parts.length >= 3) {
        category = parts[0];
        username = parts[1];
      }
    }
    var downloadedAt = file.lastModifiedSync();
    var displayName = '';
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = RegExp(
      r'^(.*?)_?(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})(?:_\d+)?\.[^.]+$',
    ).firstMatch(name);
    if (match != null) {
      downloadedAt = DateTime(
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
      );
      displayName = (match.group(1) ?? '').replaceAll(RegExp(r'_+$'), '').trim();
      if (displayName.toLowerCase() == username.toLowerCase()) {
        displayName = '';
      }
    }
    return SavedFileInfo(
      file: file,
      category: category,
      username: username,
      displayName: displayName,
      downloadedAt: downloadedAt,
      fileName: name,
    );
  }
}

class SavedFileInfo {
  const SavedFileInfo({
    required this.file,
    required this.category,
    required this.username,
    required this.downloadedAt,
    required this.fileName,
    this.displayName = '',
  });

  final File file;
  final String category;
  final String username;
  final String displayName;
  final DateTime downloadedAt;
  final String fileName;

  String resolvedName(Map<String, String> names) {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    if (username.isEmpty) {
      return '';
    }
    return (names[username.toLowerCase()] ?? '').trim();
  }

  String titleFor(Map<String, String> names) {
    final name = resolvedName(names);
    if (name.isNotEmpty) {
      return name;
    }
    if (username.isNotEmpty) {
      return '@$username';
    }
    return fileName;
  }

  String subtitleFor(Map<String, String> names) {
    final parts = <String>[];
    if (username.isNotEmpty) {
      parts.add('@$username');
    }
    if (category.isNotEmpty) {
      parts.add(category);
    }
    parts.add(IoHelpers.formatSavedStampLabel(downloadedAt));
    return parts.join(' · ');
  }
}
