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
      final items = await dir.list().toList();
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
}
