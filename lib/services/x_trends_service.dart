import 'dart:convert';
import 'dart:io';

import '../models.dart';

class XTrendsException implements Exception {
  XTrendsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class XTrendsService {
  XTrendsService(this.settings);
  final AppSettings settings;

  static const regions = <XTrendRegion>[
    XTrendRegion('worldwide', '全球', ''),
    XTrendRegion('united-states', '美国', 'united-states/'),
    XTrendRegion('japan', '日本', 'japan/'),
    XTrendRegion('south-korea', '韩国', 'south-korea/'),
    XTrendRegion('united-kingdom', '英国', 'united-kingdom/'),
    XTrendRegion('taiwan', '台湾', 'taiwan/'),
    XTrendRegion('hong-kong', '香港', 'hong-kong/'),
  ];

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Future<XTrendSnapshot> fetch(XTrendRegion region) async {
    if (region.id == 'worldwide') {
      try {
        return await _fetchFx();
      } catch (_) {
        return _fetchTrends24(region);
      }
    }
    return _fetchTrends24(region);
  }

  Future<XTrendSnapshot> _fetchFx() async {
    final uri = Uri.parse('https://api.fxtwitter.com/2/trends').replace(
      queryParameters: const <String, String>{
        'type': 'trending',
        'count': '50',
      },
    );
    final json = jsonDecode(await _getRaw(uri, accept: 'application/json'))
        as Map<String, dynamic>;
    if ((json['code'] as num?)?.toInt() != 200) {
      throw XTrendsException('热点请求失败。');
    }
    final items = <XTrend>[];
    final trends = json['trends'];
    if (trends is List) {
      var index = 1;
      for (final item in trends) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final name = '${map['name'] ?? ''}'.trim();
        if (name.isEmpty) {
          continue;
        }
        final rank = int.tryParse('${map['rank'] ?? ''}') ?? index;
        items.add(
          XTrend(
            rank: rank,
            name: name,
            searchUrl: 'https://x.com/search?q=${Uri.encodeComponent(name)}',
            detail: '${map['context'] ?? ''}'.trim(),
          ),
        );
        index += 1;
      }
    }
    if (items.isEmpty) {
      throw XTrendsException('没有解析到热点，请稍后刷新。');
    }
    return XTrendSnapshot(
      regionId: 'worldwide',
      updatedAt: DateTime.now(),
      items: items,
    );
  }

  Future<XTrendSnapshot> _fetchTrends24(XTrendRegion region) async {
    final uri = Uri.parse('https://trends24.in/${region.path}');
    final html = await _getRaw(uri);
    final snapshot = _parse(html, region.id);
    if (snapshot.items.isEmpty) {
      throw XTrendsException('没有解析到热点，请稍后刷新。');
    }
    return snapshot;
  }

  XTrendSnapshot _parse(String html, String regionId) {
    final listMatch = RegExp(
      r'<div class="?list-container"?>[\s\S]*?<ol class="?trend-card__list"?>([\s\S]*?)</ol>',
      caseSensitive: false,
    ).firstMatch(html);
    if (listMatch == null) {
      throw XTrendsException('热点页面结构有变，暂时无法读取。');
    }
    final items = <XTrend>[];
    final itemRe = RegExp(
      r'<a href="([^"]+)" class="?trend-link"?>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    var rank = 1;
    for (final match in itemRe.allMatches(listMatch.group(1)!)) {
      final name = _decode(match.group(2) ?? '');
      if (name.isEmpty) {
        continue;
      }
      var url = match.group(1) ?? '';
      url = url.replaceFirst('https://twitter.com/', 'https://x.com/');
      items.add(XTrend(rank: rank, name: name, searchUrl: url));
      rank += 1;
    }
    DateTime? updatedAt;
    final tsMatch = RegExp(
      r'<div class="?list-container"?>[\s\S]*?data-timestamp=([0-9.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (tsMatch != null) {
      final seconds = double.tryParse(tsMatch.group(1)!);
      if (seconds != null && seconds > 0) {
        updatedAt = DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round(),
          isUtc: true,
        ).toLocal();
      }
    }
    return XTrendSnapshot(
      regionId: regionId,
      updatedAt: updatedAt,
      items: items,
    );
  }

  Future<String> _getRaw(
    Uri uri, {
    String accept = 'text/html,application/xhtml+xml',
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.userAgent = _userAgent;
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Accept', accept);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XTrendsException('热点请求失败（HTTP ${response.statusCode}）。');
      }
      return body;
    } on SocketException {
      throw XTrendsException('无法获取热点，请确认 VPN/代理已开启。');
    } on HttpException catch (error) {
      throw XTrendsException('热点请求失败：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  String _decode(String raw) {
    var text = raw.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!));
    });
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
    });
    return text.trim();
  }
}
