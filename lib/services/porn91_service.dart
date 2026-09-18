import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'io_helpers.dart';

class Porn91Exception implements Exception {
  Porn91Exception(this.message);
  final String message;

  @override
  String toString() => message;
}

class Porn91Video {
  const Porn91Video({
    required this.viewkey,
    required this.title,
    this.duration = '',
    this.thumbnail = '',
    this.author = '',
    this.likes = 0,
    this.videoId = '',
    this.fetchUrl = '',
  });

  final String viewkey;
  final String title;
  final String duration;
  final String thumbnail;
  final String author;
  final int likes;
  final String videoId;
  final String fetchUrl;

  String get pageUrl => 'https://91porn.com/view_video.php?viewkey=$viewkey';

  String get requestUrl {
    final raw = fetchUrl.trim();
    if (raw.isEmpty) {
      return pageUrl;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    if (raw.startsWith('//')) {
      return 'https:$raw';
    }
    if (raw.startsWith('/')) {
      return '${Porn91Service.host}$raw';
    }
    return '${Porn91Service.host}/$raw';
  }
}

class Porn91PageResult {
  const Porn91PageResult({
    required this.videos,
    required this.page,
    required this.hasMore,
  });

  final List<Porn91Video> videos;
  final int page;
  final bool hasMore;
}

class Porn91Service {
  Porn91Service(this.settings);
  final AppSettings settings;
  final Map<String, String> _cookies = <String, String>{'language': 'cn_CN'};
  final Set<String> _downloadedTitles = <String>{};
  final Set<String> _downloadedKeys = <String>{};
  final List<String> _savedTitles = <String>[];
  bool _logLoaded = false;

  static const host = 'https://91porn.com';
  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const imageHeaders = <String, String>{
    'User-Agent': userAgent,
    'Referer': '$host/',
  };
  static const downloadedLogFile = 'downloaded.json';
  static final _stampSuffix = RegExp(
    r'_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?:_\d+)?$',
  );

  Future<Porn91PageResult> fetchIndex({int page = 1}) async {
    final index = page < 1 ? 1 : page;
    final query = <String, String>{
      'category': 'top',
      'viewtype': 'basic',
    };
    if (index > 1) {
      query['page'] = '$index';
    }
    final uri = Uri.parse('$host/v.php').replace(queryParameters: query);
    final html = await _getHtml(uri);
    final videos = _parseIndex(html);
    final hasMore = videos.isNotEmpty &&
        (RegExp('page=${index + 1}\\b', caseSensitive: false).hasMatch(html) ||
            videos.length >= 12);
    return Porn91PageResult(videos: videos, page: index, hasMore: hasMore);
  }

  Future<List<Porn91Video>> fetchTopVideos({int pages = 2}) async {
    final limit = pages < 1 ? 1 : pages;
    final videos = <Porn91Video>[];
    final seen = <String>{};
    Object? lastError;
    for (var page = 1; page <= limit; page++) {
      try {
        final result = await fetchIndex(page: page);
        for (final item in result.videos) {
          if (seen.add(item.viewkey)) {
            videos.add(item);
          }
        }
        if (result.videos.isEmpty || !result.hasMore) {
          break;
        }
      } catch (error) {
        lastError = error;
        break;
      }
    }
    if (videos.isEmpty && lastError != null) {
      throw lastError;
    }
    return videos;
  }

  Future<String> resolveVideoUrl(Porn91Video video) async {
    final urls = await _resolveDownloadUrls(video);
    return urls.first;
  }

  Future<String> download({
    required Porn91Video video,
    required String dir,
    required void Function(double progress, String speed) onProgress,
  }) async {
    onProgress(0.04, '解析中');
    final urls = await _resolveDownloadUrls(video);
    await IoHelpers.ensureDownloadDir(dir);
    var title = video.title.trim();
    if (title.isEmpty) {
      title = video.viewkey;
    }
    if (title.length > 72) {
      title = title.substring(0, 72);
    }
    final stamp = IoHelpers.formatSavedStamp(DateTime.now());
    final label = IoHelpers.sanitizeFileName('${title}_$stamp');
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (url.toLowerCase().contains('.m3u8')) {
        lastError = Porn91Exception('这个视频是切片流，暂时只支持直链 mp4。');
        continue;
      }
      onProgress(0.08, urls.length > 1 ? '开始下载（${i + 1}/${urls.length}）' : '开始下载');
      final path = await IoHelpers.uniqueSavePath(
        dir: dir,
        label: label,
        ext: _extFromUrl(url),
      );
      try {
        await IoHelpers.downloadFile(
          url,
          path,
          referer: video.requestUrl,
          onProgress: onProgress,
        );
        onProgress(1, '');
        return path;
      } catch (error) {
        lastError = error;
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    final error = lastError;
    if (error is Exception) {
      throw error;
    }
    throw Porn91Exception('视频下载失败，请确认 VPN/代理已开启。');
  }

  Future<bool> hasDownloaded(Porn91Video video) async {
    await _ensureDownloadedLog();
    final key = video.viewkey.trim().toLowerCase();
    if (key.isNotEmpty && _downloadedKeys.contains(key)) {
      return true;
    }
    return _hasTitle(recordedTitle(video));
  }

  Future<void> markDownloaded(Porn91Video video) async {
    await _ensureDownloadedLog();
    var changed = _addKey(video.viewkey);
    if (_addTitle(recordedTitle(video))) {
      changed = true;
    }
    if (changed) {
      await _saveDownloadedLog();
    }
  }

  String recordedTitle(Porn91Video video) {
    final title = video.title.trim();
    return title.isEmpty ? video.viewkey.trim() : title;
  }

  File _downloadedLogFile() {
    return File(
      '${settings.downloadDir}/${IoHelpers.monthlyDownloadFolder}/$downloadedLogFile',
    );
  }

  Future<void> _ensureDownloadedLog() async {
    if (_logLoaded) {
      return;
    }
    _logLoaded = true;
    final file = _downloadedLogFile();
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          for (final item in raw) {
            _addTitle('$item');
          }
        } else if (raw is Map) {
          final titles = raw['titles'];
          if (titles is List) {
            for (final item in titles) {
              _addTitle('$item');
            }
          }
          final keys = raw['viewkeys'];
          if (keys is List) {
            for (final item in keys) {
              _addKey('$item');
            }
          }
        }
      } catch (_) {}
    }
    if (await _importExistingFiles()) {
      await _saveDownloadedLog();
    }
  }

  Future<bool> _importExistingFiles() async {
    final dir = Directory(
      '${settings.downloadDir}/${IoHelpers.monthlyDownloadFolder}',
    );
    if (!await dir.exists()) {
      return false;
    }
    var changed = false;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path.split(RegExp(r'[\\/]')).last
          : entity.uri.pathSegments.last;
      if (name == downloadedLogFile || name.startsWith('.')) {
        continue;
      }
      final title = _titleFromFileName(name);
      if (title != null && _addTitle(title)) {
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _saveDownloadedLog() async {
    final file = _downloadedLogFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'titles': _savedTitles,
        'viewkeys': _downloadedKeys.toList(),
      }),
    );
  }

  bool _hasTitle(String title) {
    final key = _titleKey(title);
    if (key.isEmpty) {
      return false;
    }
    if (_downloadedTitles.contains(key)) {
      return true;
    }
    if (key.length > 72) {
      return _downloadedTitles.contains(key.substring(0, 72).trim());
    }
    return false;
  }

  bool _addTitle(String title) {
    final raw = title.trim();
    final key = _titleKey(raw);
    if (key.isEmpty || !_downloadedTitles.add(key)) {
      return false;
    }
    _savedTitles.add(raw);
    if (key.length > 72) {
      _downloadedTitles.add(key.substring(0, 72).trim());
    }
    return true;
  }

  bool _addKey(String viewkey) {
    final key = viewkey.trim().toLowerCase();
    return key.isNotEmpty && _downloadedKeys.add(key);
  }

  String _titleKey(String title) {
    return title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String? _titleFromFileName(String name) {
    final base = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final stripped = base.replaceFirst(_stampSuffix, '');
    final title = stripped.replaceAll(RegExp(r'_+$'), '').trim();
    if (title.isEmpty) {
      return null;
    }
    return title;
  }

  Future<List<String>> _resolveDownloadUrls(Porn91Video video) async {
    await _ensureSession();
    var html = await _getHtml(
      Uri.parse(video.requestUrl),
      referer: '$host/v.php?category=top&viewtype=basic',
    );
    var urls = _extractVideoUrls(html, videoId: video.videoId);
    if (video.videoId.isNotEmpty && !_urlsMatchVideo(urls, video.videoId)) {
      _cookies.remove('CLIPSHARE');
      await _ensureSession();
      html = await _getHtml(
        Uri.parse(video.requestUrl),
        referer: '$host/v.php?category=top&viewtype=basic',
      );
      urls = _extractVideoUrls(html, videoId: video.videoId);
    }
    if (urls.isEmpty) {
      throw Porn91Exception('找到了页面，但没有可下载的视频地址。');
    }
    if (video.videoId.isNotEmpty && !_urlsMatchVideo(urls, video.videoId)) {
      throw Porn91Exception('没有拿到这条视频的完整地址，请稍后重试。');
    }
    return urls;
  }

  bool _urlsMatchVideo(List<String> urls, String videoId) {
    return urls.any((url) => url.contains(videoId));
  }

  Future<void> _ensureSession() async {
    if ((_cookies['CLIPSHARE'] ?? '').isNotEmpty) {
      return;
    }
    await _getHtml(Uri.parse('$host/v.php?category=top&viewtype=basic'));
  }

  List<Porn91Video> _parseIndex(String html) {
    final videos = <Porn91Video>[];
    final seen = <String>{};
    final cardRe = RegExp(
      r'''view_video\.php\?viewkey=([0-9a-zA-Z]+)[^"'>\s]*''',
      caseSensitive: false,
    );
    for (final match in cardRe.allMatches(html)) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      final start = match.start;
      final end = (start + 3200).clamp(0, html.length);
      final chunk = html.substring(start, end);
      final beforeStart = (start - 400).clamp(0, html.length);
      final around = html.substring(beforeStart, end);
      final fetchUrl = _absUrl(match.group(0) ?? '');
      final videoId = _firstGroup(
            chunk,
            RegExp(r'/thumb/(\d+)\.(?:jpg|jpeg|png|webp)', caseSensitive: false),
          ) ??
          _firstGroup(
            chunk,
            RegExp(r'playvthumb_(\d+)', caseSensitive: false),
          ) ??
          '';
      final thumb = _firstGroup(
            around,
            RegExp(
              r'''<img[^>]+(?:src|data-src)=["']([^"']+)["']''',
              caseSensitive: false,
            ),
          ) ??
          '';
      final title = _decodeHtml(
        _firstGroup(
              chunk,
              RegExp(
                r'class="[^"]*video-title[^"]*"[^>]*>([^<]+)',
                caseSensitive: false,
              ),
            ) ??
            _firstGroup(
              chunk,
              RegExp(r'''title=["']([^"']+)["']''', caseSensitive: false),
            ) ??
            key,
      );
      final duration = _firstGroup(
            chunk,
            RegExp(
              r'class="[^"]*duration[^"]*"[^>]*>([^<]+)',
              caseSensitive: false,
            ),
          ) ??
          '';
      final author = _decodeHtml(
        _firstGroup(
              chunk,
              RegExp(
                r'(?:author|uploader)[^<]{0,40}>([^<]+)',
                caseSensitive: false,
              ),
            ) ??
            '',
      );
      final likes = _parseCount(
        chunk,
        const <String>[
          r'收藏[:：]?\s*</span>\s*([\d,]+)',
          r'Favorites?[:：]?\s*</span>\s*([\d,]+)',
          r'收藏[:：]\s*([\d,]+)',
          r'Favorites?[:：]\s*([\d,]+)',
        ],
      );
      videos.add(
        Porn91Video(
          viewkey: key,
          title: title,
          duration: duration.trim(),
          thumbnail: _absUrl(thumb),
          author: author.trim(),
          likes: likes,
          videoId: videoId,
          fetchUrl: fetchUrl,
        ),
      );
    }
    return videos;
  }

  List<String> _extractVideoUrls(String html, {String videoId = ''}) {
    final urls = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      if (!_looksLikeMedia(raw) || _isAdUrl(raw!)) {
        return;
      }
      final url = _absUrl(raw);
      if (url.isEmpty || !seen.add(url)) {
        return;
      }
      urls.add(url);
    }

    void addFromHtml(String text) {
      for (final match in RegExp(
        r'''<source[^>]+src=["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(text)) {
        add(match.group(1));
      }
      add(
        _firstGroup(
          text,
          RegExp(
            r'''(?:file|video_url|src)\s*[:=]\s*["'](https?://[^"']+\.(?:mp4|m3u8)[^"']*)["']''',
            caseSensitive: false,
          ),
        ),
      );
      for (final match in RegExp(
        r'https?://[^\s"<>]+?\.(?:mp4|m3u8)[^\s"<>]*',
        caseSensitive: false,
      ).allMatches(text)) {
        add(match.group(0));
      }
    }

    for (final match in RegExp(
      r'''strencode2?\(\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      addFromHtml(_decodePacked(match.group(1) ?? ''));
    }
    addFromHtml(html);
    if (videoId.isEmpty) {
      return urls;
    }
    final matched = urls.where((url) => url.contains(videoId)).toList();
    if (matched.isEmpty) {
      return urls;
    }
    final rest = urls.where((url) => !url.contains(videoId)).toList();
    return <String>[...matched, ...rest];
  }

  String _decodePacked(String encoded) {
    final unescaped = _unescapeJs(encoded);
    if (unescaped != encoded &&
        (unescaped.contains('http') || unescaped.contains('<source'))) {
      return unescaped;
    }
    try {
      final normalized = encoded.replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(normalized);
      var text = utf8.decode(bytes, allowMalformed: true);
      try {
        text = Uri.decodeComponent(text.replaceAll('+', '%20'));
      } catch (_) {
        text = _unescapeJs(text);
      }
      if (text.contains('http') || text.contains('<source')) {
        return text;
      }
    } catch (_) {}
    return encoded;
  }

  bool _isAdUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('kwai.net') ||
        lower.contains('preroll') ||
        lower.contains('ad-i18n') ||
        lower.contains('googleads') ||
        lower.contains('doubleclick') ||
        lower.contains('/358999.mp4') ||
        lower.contains('/378999.mp4');
  }

  String _unescapeJs(String input) {
    return input
        .replaceAllMapped(RegExp(r'%u([0-9a-fA-F]{4})'), (match) {
          return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
        })
        .replaceAllMapped(RegExp(r'%([0-9a-fA-F]{2})'), (match) {
          return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
        });
  }

  bool _looksLikeMedia(String? url) {
    if (url == null || url.trim().isEmpty) {
      return false;
    }
    final lower = url.toLowerCase();
    return lower.contains('.mp4') || lower.contains('.m3u8');
  }

  String _absUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    if (text.startsWith('//')) {
      return 'https:$text';
    }
    if (text.startsWith('/')) {
      return '$host$text';
    }
    return text;
  }

  String _extFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.contains('.m3u8')) {
      return '.m3u8';
    }
    return '.mp4';
  }

  String? _firstGroup(String html, RegExp re) {
    return re.firstMatch(html)?.group(1)?.trim();
  }

  int _parseCount(String html, List<String> patterns) {
    for (final pattern in patterns) {
      final raw = _firstGroup(html, RegExp(pattern, caseSensitive: false));
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final value = int.tryParse(raw.replaceAll(',', ''));
      if (value != null) {
        return value;
      }
    }
    return 0;
  }

  String _decodeHtml(String raw) {
    return raw
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          return String.fromCharCode(int.parse(match.group(1)!));
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cookieHeader() {
    return _cookies.entries
        .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void _storeCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      final name = cookie.name.trim();
      if (name.isEmpty) {
        continue;
      }
      _cookies[name] = cookie.value;
    }
  }

  Future<String> _getHtml(Uri uri, {String? referer}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.userAgent = userAgent;
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'text/html,application/xhtml+xml');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
      request.headers.set('Cookie', _cookieHeader());
      request.headers.set('Referer', referer ?? '$host/');
      request.followRedirects = true;
      request.maxRedirects = 8;
      final response = await request.close().timeout(const Duration(seconds: 30));
      _storeCookies(response);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Porn91Exception('请求失败（HTTP ${response.statusCode}）');
      }
      if (body.trim().isEmpty) {
        throw Porn91Exception('页面是空的，请确认 VPN/代理已开启。');
      }
      return body;
    } on SocketException {
      throw Porn91Exception('无法连接 91porn，请确认 VPN/代理已开启。');
    } on HandshakeException {
      throw Porn91Exception('无法连接 91porn，请确认 VPN/代理已开启。');
    } finally {
      client.close(force: true);
    }
  }
}
