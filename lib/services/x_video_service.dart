import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models.dart';
import 'io_helpers.dart';

class XVideoException implements Exception {
  XVideoException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _XFormat {
  _XFormat({
    required this.url,
    required this.bitrate,
    required this.width,
    required this.height,
  });

  final String url;
  final int bitrate;
  final int width;
  final int height;
}

class _XTweetVideo {
  _XTweetVideo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.webpageUrl,
    required this.formats,
  });

  final String id;
  final String title;
  final String uploader;
  final int duration;
  final String thumbnail;
  final String webpageUrl;
  final List<_XFormat> formats;
}

class XVideoService {
  XVideoService(this.settings);
  final AppSettings settings;

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static bool isXUrl(String url) {
    final text = url.toLowerCase();
    return text.contains('x.com/') ||
        text.contains('twitter.com/') ||
        text.contains('fxtwitter.com/') ||
        text.contains('vxtwitter.com/');
  }

  static String? extractStatusId(String url) {
    final match = RegExp(
      r'(?:x\.com|twitter\.com|fxtwitter\.com|vxtwitter\.com)/[^?\s#]*/status(?:es)?/(\d+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (match != null) {
      return match.group(1);
    }
    final fallback = RegExp(r'/status(?:es)?/(\d+)', caseSensitive: false).firstMatch(url);
    return fallback?.group(1);
  }

  Future<VideoInfo> fetchInfo(String url) async {
    final tweet = await _resolve(url);
    return VideoInfo(
      id: tweet.id,
      title: tweet.title,
      uploader: tweet.uploader,
      duration: tweet.duration,
      thumbnail: tweet.thumbnail,
      webpageUrl: tweet.webpageUrl,
      extractor: 'twitter',
    );
  }

  Future<String> download({
    required String url,
    required String dir,
    required VideoQuality quality,
    required void Function(double progress, String speed) onProgress,
  }) async {
    final tweet = await _resolve(url);
    final format = _pickFormat(tweet.formats, quality);
    await IoHelpers.ensureDownloadDir(dir);
    onProgress(0.05, '解析完成');

    var title = tweet.title;
    if (title.length > 72) {
      title = title.substring(0, 72);
    }
    final stem = IoHelpers.sanitizeFileName('$title [${tweet.id}]');
    if (quality == VideoQuality.audio) {
      final mp4Path = '$dir/$stem.mp4';
      final audioPath = '$dir/$stem.m4a';
      await _downloadFile(format.url, mp4Path, onProgress);
      await _extractAudio(mp4Path, audioPath);
      try {
        await File(mp4Path).delete();
      } catch (_) {}
      onProgress(1, '');
      return audioPath;
    }

    final path = '$dir/$stem.mp4';
    await _downloadFile(format.url, path, onProgress);
    onProgress(1, '');
    return path;
  }

  Future<_XTweetVideo> _resolve(String url) async {
    final id = extractStatusId(url);
    if (id == null) {
      throw XVideoException('请粘贴推文链接，例如 https://x.com/用户名/status/数字');
    }
    final endpoints = <Uri>[
      Uri.parse('https://api.fxtwitter.com/status/$id'),
      Uri.parse('https://api.vxtwitter.com/i/status/$id'),
    ];
    Object? lastError;
    for (final uri in endpoints) {
      try {
        final json = await _getJson(uri);
        return _parseTweet(json, id, url);
      } catch (error) {
        lastError = error;
      }
    }
    final message = lastError?.toString() ?? '';
    if (message.contains('没有视频')) {
      throw XVideoException(message);
    }
    throw XVideoException('无法解析该视频。请确认 VPN/代理已开启，并粘贴带 /status/ 的推文链接。');
  }

  _XTweetVideo _parseTweet(Map<String, dynamic> json, String id, String fallbackUrl) {
    final tweet = json['tweet'];
    if (tweet is Map) {
      return _parseFx(Map<String, dynamic>.from(tweet), id, fallbackUrl);
    }
    final code = json['code'];
    if (code == 404 || code == 401 || code == 403) {
      throw XVideoException('未找到该推文，或该帖子不可访问。');
    }
    return _parseVx(json, id, fallbackUrl);
  }

  _XTweetVideo _parseFx(Map<String, dynamic> tweet, String id, String fallbackUrl) {
    final media = tweet['media'] as Map<String, dynamic>?;
    var videos = _asMaps(media?['videos']);
    if (videos.isEmpty) {
      videos = _asMaps(media?['all']).where((item) {
        final type = '${item['type']}'.toLowerCase();
        return type == 'video' || type == 'gif';
      }).toList();
    }
    if (videos.isEmpty) {
      final quote = tweet['quote'] as Map<String, dynamic>?;
      final quoteMedia = quote?['media'] as Map<String, dynamic>?;
      videos = _asMaps(quoteMedia?['videos']);
    }
    if (videos.isEmpty) {
      throw XVideoException('这条帖子没有视频。');
    }
    final video = videos.first;
    final formats = _formatsFromFx(video);
    if (formats.isEmpty) {
      throw XVideoException('找到了帖子，但没有可下载的 mp4 地址。');
    }
    final author = tweet['author'] as Map<String, dynamic>?;
    final text = '${tweet['text'] ?? tweet['raw_text'] ?? '视频'}'.trim();
    final duration = (video['duration'] as num?)?.round() ?? 0;
    return _XTweetVideo(
      id: '${tweet['id'] ?? id}',
      title: text.isEmpty ? '视频' : text,
      uploader: '${author?['screen_name'] ?? author?['name'] ?? ''}',
      duration: duration,
      thumbnail: '${video['thumbnail_url'] ?? ''}',
      webpageUrl: '${tweet['url'] ?? fallbackUrl}',
      formats: formats,
    );
  }

  _XTweetVideo _parseVx(Map<String, dynamic> json, String id, String fallbackUrl) {
    final extended = _asMaps(json['media_extended']);
    final videos = extended.where((item) {
      final type = '${item['type']}'.toLowerCase();
      return type == 'video' || type == 'gif';
    }).toList();
    final formats = <_XFormat>[];
    for (final video in videos) {
      formats.addAll(_formatsFromVx(video));
    }
    if (formats.isEmpty) {
      final urls = json['mediaURLs'];
      if (urls is List) {
        for (final item in urls) {
          final mediaUrl = '$item';
          if (mediaUrl.contains('.mp4')) {
            formats.add(_formatFromUrl(mediaUrl, 0));
          }
        }
      }
    }
    if (formats.isEmpty) {
      throw XVideoException('这条帖子没有视频。');
    }
    final text = '${json['text'] ?? json['tweet'] ?? '视频'}'.trim();
    final durationMs = (videos.isNotEmpty ? videos.first['duration_millis'] as num? : null)?.round() ?? 0;
    return _XTweetVideo(
      id: '${json['tweetID'] ?? json['tweetId'] ?? id}',
      title: text.isEmpty ? '视频' : text,
      uploader: '${json['user_screen_name'] ?? json['user_name'] ?? ''}',
      duration: durationMs > 0 ? (durationMs / 1000).round() : 0,
      thumbnail: videos.isNotEmpty ? '${videos.first['thumbnail_url'] ?? ''}' : '',
      webpageUrl: '${json['tweetURL'] ?? json['url'] ?? fallbackUrl}',
      formats: formats,
    );
  }

  List<_XFormat> _formatsFromFx(Map<String, dynamic> video) {
    final formats = <_XFormat>[];
    for (final item in _asMaps(video['formats'])) {
      final container = '${item['container'] ?? ''}'.toLowerCase();
      final mediaUrl = '${item['url'] ?? ''}';
      if (mediaUrl.isEmpty) {
        continue;
      }
      if (container == 'm3u8' || mediaUrl.contains('.m3u8')) {
        continue;
      }
      if (container.isNotEmpty && container != 'mp4' && !mediaUrl.contains('.mp4')) {
        continue;
      }
      final parsed = _sizeFromUrl(mediaUrl);
      formats.add(_XFormat(
        url: mediaUrl,
        bitrate: (item['bitrate'] as num?)?.toInt() ?? 0,
        width: (item['width'] as num?)?.toInt() ?? parsed[0],
        height: (item['height'] as num?)?.toInt() ?? parsed[1],
      ));
    }
    final fallback = '${video['url'] ?? ''}';
    if (formats.isEmpty && fallback.contains('.mp4')) {
      formats.add(_formatFromUrl(
        fallback,
        (video['bitrate'] as num?)?.toInt() ?? 0,
        width: (video['width'] as num?)?.toInt() ?? 0,
        height: (video['height'] as num?)?.toInt() ?? 0,
      ));
    }
    return formats;
  }

  List<_XFormat> _formatsFromVx(Map<String, dynamic> video) {
    final mediaUrl = '${video['url'] ?? ''}';
    if (mediaUrl.isEmpty || mediaUrl.contains('.m3u8')) {
      return const <_XFormat>[];
    }
    final size = video['size'] as Map<String, dynamic>?;
    return <_XFormat>[
      _formatFromUrl(
        mediaUrl,
        (video['bitrate'] as num?)?.toInt() ?? 0,
        width: (size?['width'] as num?)?.toInt() ?? (video['width'] as num?)?.toInt() ?? 0,
        height: (size?['height'] as num?)?.toInt() ?? (video['height'] as num?)?.toInt() ?? 0,
      ),
    ];
  }

  _XFormat _formatFromUrl(String url, int bitrate, {int width = 0, int height = 0}) {
    final parsed = _sizeFromUrl(url);
    return _XFormat(
      url: url,
      bitrate: bitrate,
      width: width > 0 ? width : parsed[0],
      height: height > 0 ? height : parsed[1],
    );
  }

  List<int> _sizeFromUrl(String url) {
    final match = RegExp(r'/(\d+)x(\d+)/').firstMatch(url);
    if (match == null) {
      return const <int>[0, 0];
    }
    return <int>[int.parse(match.group(1)!), int.parse(match.group(2)!)];
  }

  _XFormat _pickFormat(List<_XFormat> formats, VideoQuality quality) {
    var maxHeight = 9999;
    switch (quality) {
      case VideoQuality.best:
        maxHeight = 9999;
        break;
      case VideoQuality.p1080:
        maxHeight = 1080;
        break;
      case VideoQuality.p720:
        maxHeight = 720;
        break;
      case VideoQuality.p480:
      case VideoQuality.audio:
        maxHeight = 480;
        break;
    }
    final under = formats.where((item) {
      if (item.height <= 0) {
        return true;
      }
      return item.height <= maxHeight;
    }).toList();
    final pool = under.isNotEmpty ? under : formats;
    pool.sort((a, b) {
      final bitrate = b.bitrate.compareTo(a.bitrate);
      if (bitrate != 0) {
        return bitrate;
      }
      return b.height.compareTo(a.height);
    });
    return pool.first;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 16);
    client.userAgent = _userAgent;
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XVideoException('解析接口失败（HTTP ${response.statusCode}）。');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException {
      throw XVideoException('无法连接，请确认 VPN/代理已开启。');
    } on HttpException catch (error) {
      throw XVideoException('解析失败：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadFile(
    String url,
    String path,
    void Function(double progress, String speed) onProgress,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(minutes: 5);
    client.userAgent = _userAgent;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', 'https://x.com/');
      request.followRedirects = true;
      request.maxRedirects = 8;
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XVideoException('视频下载失败（HTTP ${response.statusCode}）。');
      }
      final file = File(path);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      final started = DateTime.now();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 90))) {
          received += chunk.length;
          sink.add(chunk);
          final elapsedMs = max(DateTime.now().difference(started).inMilliseconds, 1);
          final kibPerSec = received / elapsedMs * 1000 / 1024;
          final progress = total > 0 ? (received / total).clamp(0.0, 0.99) : 0.2;
          onProgress(progress, '${kibPerSec.toStringAsFixed(0)} KiB/s');
        }
        await sink.flush();
      } catch (error) {
        await sink.close();
        try {
          await file.delete();
        } catch (_) {}
        throw XVideoException('视频下载中断：$error');
      }
      await sink.close();
      if (received <= 0) {
        throw XVideoException('视频文件为空，请稍后重试。');
      }
    } on SocketException {
      throw XVideoException('无法下载视频，请确认 VPN/代理已开启。');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractAudio(String input, String output) async {
    final ffmpeg = File(settings.ffmpegPath);
    if (!await ffmpeg.exists()) {
      throw XVideoException('提取音频需要 ffmpeg：${settings.ffmpegPath}');
    }
    final result = await Process.run(
      settings.ffmpegPath,
      <String>['-y', '-i', input, '-vn', '-c:a', 'aac', '-b:a', '192k', output],
      environment: IoHelpers.processEnv(),
    );
    if (result.exitCode != 0) {
      throw XVideoException('音频提取失败。');
    }
  }

  List<Map<String, dynamic>> _asMaps(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }
}
