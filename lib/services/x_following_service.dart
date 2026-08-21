import 'dart:convert';
import 'dart:io';

import '../models.dart';

class XFollowingException implements Exception {
  XFollowingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class XSuggestedAccount {
  const XSuggestedAccount(this.username, this.label);
  final String username;
  final String label;
}

class XFollowingService {
  XFollowingService(this.settings);
  final AppSettings settings;

  static const suggested = <XSuggestedAccount>[
    XSuggestedAccount('NASA', '航天'),
    XSuggestedAccount('NBA', '篮球'),
    XSuggestedAccount('SpaceX', '航天'),
    XSuggestedAccount('ESPN', '体育'),
    XSuggestedAccount('Reuters', '新闻'),
    XSuggestedAccount('BBCWorld', '新闻'),
    XSuggestedAccount('OpenAI', '科技'),
    XSuggestedAccount('NatGeo', '自然'),
  ];

  static const _translateLang = 'zh-cn';

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, String> _query(Map<String, String> params) {
    return <String, String>{
      ...params,
      'lang': _translateLang,
    };
  }

  static const _reserved = <String>{
    'home',
    'explore',
    'search',
    'settings',
    'i',
    'intent',
    'compose',
    'messages',
    'notifications',
    'login',
    'signup',
    'privacy',
    'tos',
    'download',
    'about',
    'jobs',
    'help',
    'hashtag',
    'share',
  };

  static String? extractUsername(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri != null &&
        uri.host.isNotEmpty &&
        (uri.host.contains('x.com') || uri.host.contains('twitter.com'))) {
      final parts = uri.pathSegments.where((item) => item.isNotEmpty).toList();
      if (parts.isEmpty) {
        return null;
      }
      text = parts.first;
    }
    if (text.startsWith('@')) {
      text = text.substring(1);
    }
    text = text.split('/').first.trim();
    if (text.isEmpty || _reserved.contains(text.toLowerCase())) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9_]{1,40}$').hasMatch(text)) {
      return null;
    }
    return text;
  }

  Future<XAccount> fetchAccount(String raw) async {
    final username = extractUsername(raw);
    if (username == null) {
      throw XFollowingException('请输入用户名，例如 @NASA，或粘贴 x.com/用户名 链接。');
    }
    try {
      return await _fetchAccountAt(
        Uri.parse(
          'https://api.fxtwitter.com/2/profile/${Uri.encodeComponent(username)}',
        ),
        username,
      );
    } catch (_) {
      return _fetchAccountAt(
        Uri.parse('https://api.fxtwitter.com/${Uri.encodeComponent(username)}'),
        username,
      );
    }
  }

  Future<XAccount> _fetchAccountAt(Uri uri, String username) async {
    final json = jsonDecode(await _getRaw(uri)) as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>?;
    if (user == null) {
      throw XFollowingException('未找到账号 @$username。');
    }
    return _parseAccount(user, username);
  }

  Future<List<XAccount>> fetchFollowing(String username) {
    return _fetchProfileUsers(username, 'following');
  }

  Future<List<XAccount>> fetchFollowers(String username) {
    return _fetchProfileUsers(username, 'followers');
  }

  Future<List<XAccount>> _fetchProfileUsers(String username, String kind) async {
    final handle = extractUsername(username) ?? username;
    final accounts = <XAccount>[];
    final seen = <String>{};
    String? cursor;
    try {
      for (var page = 0; page < 10; page++) {
        final query = <String, String>{'count': '100'};
        if (cursor != null && cursor.isNotEmpty) {
          query['cursor'] = cursor;
        }
        final uri = Uri.parse(
          'https://api.fxtwitter.com/2/profile/${Uri.encodeComponent(handle)}/$kind',
        ).replace(queryParameters: query);
        final json = jsonDecode(await _getRaw(uri)) as Map<String, dynamic>;
        if ((json['code'] as num?)?.toInt() != 200) {
          break;
        }
        var added = 0;
        final results = json['results'];
        if (results is List) {
          for (final item in results) {
            if (item is! Map) {
              continue;
            }
            final account = _parseAccount(Map<String, dynamic>.from(item), handle);
            final key = account.username.toLowerCase();
            if (key.isEmpty || !seen.add(key)) {
              continue;
            }
            accounts.add(account);
            added++;
          }
        }
        final next = _cursorBottom(json['cursor']);
        if (added == 0 || next == null || next == cursor) {
          break;
        }
        cursor = next;
      }
    } catch (_) {}
    return accounts;
  }

  Future<XPostPage> searchPosts(
    String query, {
    String feed = 'latest',
    String? cursor,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const XPostPage(posts: <XPost>[], cursor: null);
    }
    final current = (cursor ?? '').trim();
    final params = _query(<String, String>{
      'q': q,
      'feed': feed,
      'count': '50',
    });
    if (current.isNotEmpty) {
      params['cursor'] = current;
    }
    final uri = Uri.parse('https://api.fxtwitter.com/2/search').replace(
      queryParameters: params,
    );
    final body = await _getRaw(uri, allowNotFound: true);
    if (body.trim().isEmpty) {
      return const XPostPage(posts: <XPost>[], cursor: null);
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final code = (json['code'] as num?)?.toInt();
    if (code == 404) {
      return const XPostPage(posts: <XPost>[], cursor: null);
    }
    if (code != 200) {
      throw XFollowingException('搜索失败。');
    }
    final posts = _parseStatusList(json['results'], '');
    var next = _cursorBottom(json['cursor']);
    if (posts.isEmpty || next == current) {
      next = null;
    }
    return XPostPage(posts: posts, cursor: next);
  }

  Future<XAccountPage> searchUsers(
    String query, {
    String? cursor,
    Set<String> exclude = const <String>{},
  }) async {
    final q = query.trim().replaceFirst(RegExp(r'^@+'), '');
    if (q.isEmpty) {
      return const XAccountPage(accounts: <XAccount>[]);
    }
    final current = (cursor ?? '').trim();
    final seen = <String>{
      ...exclude.map((name) => name.trim().toLowerCase()).where((name) => name.isNotEmpty),
    };
    final accounts = <XAccount>[];

    if (current.isEmpty) {
      for (final account in await _typeaheadUsers(q)) {
        final key = account.username.toLowerCase();
        if (key.isEmpty || !seen.add(key)) {
          continue;
        }
        accounts.add(account);
      }
    }

    var next = current.isEmpty ? null : current;
    var pages = 0;
    const maxPages = 4;
    try {
      while (pages < maxPages) {
        final page = await searchPosts(q, feed: 'latest', cursor: next);
        var added = 0;
        for (final account in _accountsFromPosts(page.posts)) {
          final key = account.username.toLowerCase();
          if (key.isEmpty || !seen.add(key)) {
            continue;
          }
          accounts.add(account);
          added++;
        }
        next = page.cursor;
        pages++;
        if (next == null || next.isEmpty || added > 0) {
          break;
        }
      }
    } catch (_) {
      if (accounts.isEmpty) {
        rethrow;
      }
      next = null;
    }
    return XAccountPage(accounts: accounts, cursor: next);
  }

  Future<List<XAccount>> _typeaheadUsers(String query) async {
    final uri = Uri.parse('https://api.fxtwitter.com/2/typeahead').replace(
      queryParameters: <String, String>{
        'q': query,
        'result_type': 'users',
      },
    );
    final body = await _getRaw(uri, allowNotFound: true);
    if (body.trim().isEmpty) {
      return <XAccount>[];
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final code = (json['code'] as num?)?.toInt();
    if (code == 404) {
      return <XAccount>[];
    }
    if (code != 200) {
      throw XFollowingException('搜索成员失败。');
    }
    final users = json['users'];
    if (users is! List) {
      return <XAccount>[];
    }
    final accounts = <XAccount>[];
    final seen = <String>{};
    for (final item in users) {
      if (item is! Map) {
        continue;
      }
      final account = _parseAccount(Map<String, dynamic>.from(item), '');
      final key = account.username.toLowerCase();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      accounts.add(account);
    }
    return accounts;
  }

  List<XAccount> _accountsFromPosts(List<XPost> posts) {
    final accounts = <XAccount>[];
    final seen = <String>{};
    for (final post in posts) {
      final username = post.username.trim();
      final key = username.toLowerCase();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      accounts.add(
        XAccount(
          username: username,
          name: post.authorName.trim().isEmpty ? username : post.authorName.trim(),
          description: '',
          avatarUrl: post.avatarUrl,
          profileUrl: 'https://x.com/$username',
          followers: 0,
          following: 0,
          tweets: 0,
        ),
      );
    }
    return accounts;
  }

  String? _cursorBottom(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final bottom = raw['bottom'];
    if (bottom == null) {
      return null;
    }
    final text = '$bottom'.trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  XAccount _parseAccount(Map<String, dynamic> user, String fallback) {
    var avatar = '${user['avatar_url'] ?? ''}';
    avatar = avatar.replaceFirst('_normal', '_400x400');
    final username = '${user['screen_name'] ?? fallback}';
    var description = '${user['description'] ?? ''}'.trim();
    if (description.isEmpty) {
      final raw = user['raw_description'];
      if (raw is Map) {
        description = '${raw['text'] ?? ''}'.trim();
      }
    }
    return XAccount(
      id: '${user['id'] ?? ''}',
      username: username,
      name: '${user['name'] ?? username}',
      description: description,
      avatarUrl: avatar,
      profileUrl: '${user['url'] ?? 'https://x.com/$username'}',
      followers: (user['followers'] as num?)?.toInt() ?? 0,
      following: (user['following'] as num?)?.toInt() ?? 0,
      tweets: (user['tweets'] as num?)?.toInt() ??
          (user['statuses'] as num?)?.toInt() ??
          0,
      protected: user['protected'] == true,
    );
  }

  Future<List<XPost>> fetchPosts(String username) async {
    return (await fetchPostsPage(username, count: 30)).posts;
  }

  Future<XPostPage> fetchPostsPage(
    String username, {
    String? cursor,
    int count = 10,
    int? since,
  }) async {
    final current = (cursor ?? '').trim();
    final sinceSec = (since ?? 0) > 0 ? since : null;
    try {
      final query = _query(<String, String>{
        'count': '${count.clamp(1, 100)}',
      });
      if (current.isNotEmpty) {
        query['cursor'] = current;
      } else if (sinceSec != null) {
        query['since'] = '$sinceSec';
      }
      final uri = Uri.parse(
        'https://api.fxtwitter.com/2/profile/${Uri.encodeComponent(username)}/statuses',
      ).replace(queryParameters: query);
      final body = await _getRaw(uri);
      if (body.trim().isEmpty) {
        return const XPostPage(posts: <XPost>[], cursor: null);
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      if ((json['code'] as num?)?.toInt() != 200) {
        throw XFollowingException('动态请求失败。');
      }
      final posts = _parseStatusList(json['results'], username);
      var next = _cursorBottom(json['cursor']);
      if (posts.isEmpty || next == current) {
        next = null;
      }
      return XPostPage(posts: posts, cursor: next);
    } catch (_) {
      if (current.isNotEmpty) {
        return const XPostPage(posts: <XPost>[], cursor: null);
      }
      if (sinceSec != null) {
        rethrow;
      }
      return XPostPage(posts: await _fetchPostsFromRss(username), cursor: null);
    }
  }

  static final Map<String, String> _translationCache = <String, String>{};
  static final Map<String, Future<String>> _translationPending = <String, Future<String>>{};

  static String? cachedTranslation(String postId) {
    final text = _translationCache[postId.trim()];
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<String> fetchPostTranslation(String postId) async {
    final id = postId.trim();
    if (id.isEmpty || !RegExp(r'^\d{2,20}$').hasMatch(id)) {
      return '';
    }
    final cached = cachedTranslation(id);
    if (cached != null) {
      return cached;
    }
    final pending = _translationPending[id];
    if (pending != null) {
      return pending;
    }
    final future = _loadPostTranslation(id);
    _translationPending[id] = future;
    try {
      final text = await future;
      if (text.isNotEmpty) {
        _translationCache[id] = text;
      }
      return text;
    } finally {
      _translationPending.remove(id);
    }
  }

  Future<String> _loadPostTranslation(String id) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      try {
        final uri = Uri.parse(
          'https://api.fxtwitter.com/2/status/${Uri.encodeComponent(id)}',
        ).replace(queryParameters: _query(<String, String>{}));
        final json = jsonDecode(await _getRaw(uri)) as Map<String, dynamic>;
        if ((json['code'] as num?)?.toInt() != 200) {
          lastError = null;
          continue;
        }
        final status = json['status'];
        if (status is Map) {
          final text = _parseTranslation(status['translation']);
          if (text.isNotEmpty) {
            return text;
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    return '';
  }

  Future<XReplyPage> fetchReplies(String postId, {String? cursor}) async {
    final id = postId.trim();
    if (id.isEmpty || !RegExp(r'^\d{2,20}$').hasMatch(id)) {
      throw XFollowingException('无法识别这条帖子。');
    }
    final query = _query(<String, String>{
      'ranking_mode': 'recency',
    });
    final current = (cursor ?? '').trim();
    if (current.isNotEmpty) {
      query['cursor'] = current;
    }
    final uri = Uri.parse(
      'https://api.fxtwitter.com/2/conversation/${Uri.encodeComponent(id)}',
    ).replace(queryParameters: query);
    try {
      final json = jsonDecode(await _getRaw(uri)) as Map<String, dynamic>;
      final code = (json['code'] as num?)?.toInt() ?? 0;
      if (code != 200) {
        if (current.isNotEmpty) {
          return XReplyPage(replies: const <XPost>[], cursor: null);
        }
        throw XFollowingException('评论加载失败。');
      }
      final replies = _parseStatusList(json['replies'], '');
      var next = _cursorBottom(json['cursor']);
      if (replies.isEmpty || next == current) {
        next = null;
      }
      return XReplyPage(replies: replies, cursor: next);
    } on XFollowingException catch (error) {
      if (current.isNotEmpty && error.message.contains('404')) {
        return XReplyPage(replies: const <XPost>[], cursor: null);
      }
      rethrow;
    }
  }

  static bool _isSameDay(DateTime time, DateTime day) {
    return time.year == day.year && time.month == day.month && time.day == day.day;
  }

  Future<List<XPost>> fetchTodayFeed(
    List<String> usernames, {
    void Function(List<XPost> posts, int done, int total)? onProgress,
  }) {
    final now = DateTime.now();
    return fetchDayFeed(
      usernames,
      DateTime(now.year, now.month, now.day),
      onProgress: onProgress,
    );
  }

  Future<List<XPost>> fetchDayFeed(
    List<String> usernames,
    DateTime day, {
    void Function(List<XPost> posts, int done, int total)? onProgress,
  }) async {
    if (usernames.isEmpty) {
      return <XPost>[];
    }
    final start = DateTime(day.year, day.month, day.day);
    final posts = <XPost>[];
    final seen = <String>{};
    var next = 0;
    var done = 0;
    const workers = 8;

    void emit() {
      posts.sort((a, b) {
        final at = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      onProgress?.call(List<XPost>.from(posts), done, usernames.length);
    }

    Future<void> worker() async {
      while (true) {
        final index = next;
        next += 1;
        if (index >= usernames.length) {
          return;
        }
        try {
          final list = await _fetchDayPosts(usernames[index], start);
          for (final post in list) {
            if (seen.add(post.id)) {
              posts.add(post);
            }
          }
        } catch (_) {}
        done += 1;
        if (done == usernames.length || done % workers == 0) {
          emit();
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workers, (_) => worker()),
      eagerError: false,
    );
    emit();
    return posts;
  }

  bool _collectDay(List<XPost> out, List<XPost> page, DateTime day) {
    var reachedOlder = false;
    for (final post in page) {
      final time = post.publishedAt;
      if (time == null) {
        continue;
      }
      if (_isSameDay(time, day)) {
        out.add(post);
      } else if (time.isBefore(day)) {
        reachedOlder = true;
      }
    }
    return reachedOlder;
  }

  Future<List<XPost>> _fetchDayPosts(String username, DateTime day) async {
    final posts = <XPost>[];
    final since = day.millisecondsSinceEpoch ~/ 1000;
    XPostPage result;
    try {
      result = await fetchPostsPage(username, count: 100, since: since);
    } catch (_) {
      result = await fetchPostsPage(username, count: 40);
    }
    var reachedOlder = _collectDay(posts, result.posts, day);
    var cursor = (result.cursor ?? '').trim();
    for (var page = 1; page < 8 && cursor.isNotEmpty && !reachedOlder; page++) {
      result = await fetchPostsPage(username, cursor: cursor, count: 100);
      if (result.posts.isEmpty) {
        break;
      }
      reachedOlder = _collectDay(posts, result.posts, day);
      cursor = (result.cursor ?? '').trim();
    }
    return posts;
  }

  Future<List<XPost>> fetchFeed(List<String> usernames, {bool textOnly = true}) async {
    if (usernames.isEmpty) {
      return <XPost>[];
    }
    final results = await Future.wait(
      usernames.map(fetchPosts),
      eagerError: false,
    );
    final posts = <XPost>[];
    final seen = <String>{};
    for (final list in results) {
      for (final post in list) {
        if (textOnly && post.media.isNotEmpty) {
          continue;
        }
        if (seen.add(post.id)) {
          posts.add(post);
        }
      }
    }
    posts.sort((a, b) {
      final at = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    if (posts.length > 80) {
      return posts.sublist(0, 80);
    }
    return posts;
  }

  Future<XFeedBatch> fetchVideoFeed(
    List<String> usernames, {
    Map<String, String>? cursors,
  }) {
    return _fetchMediaFeed(
      usernames,
      keep: (post) => post.hasVideo,
      cursors: cursors,
    );
  }

  Future<XFeedBatch> fetchPhotoFeed(
    List<String> usernames, {
    Map<String, String>? cursors,
  }) {
    return _fetchMediaFeed(
      usernames,
      keep: (post) => post.hasPhotos,
      cursors: cursors,
    );
  }

  Future<XFeedBatch> _fetchMediaFeed(
    List<String> usernames, {
    required bool Function(XPost post) keep,
    Map<String, String>? cursors,
  }) async {
    if (usernames.isEmpty) {
      return const XFeedBatch();
    }
    final more = cursors != null;
    final names = more
        ? usernames.where((name) => (cursors[name] ?? '').isNotEmpty).toList()
        : usernames;
    if (names.isEmpty) {
      return const XFeedBatch();
    }
    final pages = more ? 1 : (names.length > 12 ? 1 : 2);
    final results = await Future.wait(
      names.map(
        (name) => _fetchMediaPosts(
          name,
          keep: keep,
          pages: pages,
          cursor: cursors?[name],
        ),
      ),
      eagerError: false,
    );
    final posts = <XPost>[];
    final nextCursors = <String, String>{};
    final seen = <String>{};
    for (var i = 0; i < names.length; i++) {
      final result = results[i];
      for (final post in result.posts) {
        if (keep(post) && seen.add(post.id)) {
          posts.add(post);
        }
      }
      final cursor = (result.cursor ?? '').trim();
      if (cursor.isNotEmpty) {
        nextCursors[names[i]] = cursor;
      }
    }
    posts.sort((a, b) {
      final at = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    if (!more && posts.length > 120) {
      return XFeedBatch(posts: posts.sublist(0, 120), cursors: nextCursors);
    }
    return XFeedBatch(posts: posts, cursors: nextCursors);
  }

  Future<XPostPage> _fetchMediaPosts(
    String username, {
    required bool Function(XPost post) keep,
    int pages = 1,
    String? cursor,
  }) async {
    try {
      final posts = <XPost>[];
      final seen = <String>{};
      var current = (cursor ?? '').trim();
      String? nextCursor;
      for (var page = 0; page < pages; page++) {
        final query = _query(<String, String>{'count': '50'});
        if (current.isNotEmpty) {
          query['cursor'] = current;
        }
        final uri = Uri.parse(
          'https://api.fxtwitter.com/2/profile/${Uri.encodeComponent(username)}/media',
        ).replace(queryParameters: query);
        final json = jsonDecode(await _getRaw(uri)) as Map<String, dynamic>;
        if ((json['code'] as num?)?.toInt() != 200) {
          nextCursor = null;
          break;
        }
        for (final post in _parseStatusList(json['results'], username)) {
          if (keep(post) && seen.add(post.id)) {
            posts.add(post);
          }
        }
        final next = _cursorBottom(json['cursor']);
        if (next == null || next == current) {
          nextCursor = null;
          break;
        }
        nextCursor = next;
        current = next;
      }
      if (posts.isNotEmpty) {
        return XPostPage(posts: posts, cursor: nextCursor);
      }
      if ((cursor ?? '').trim().isNotEmpty) {
        return XPostPage(posts: const <XPost>[], cursor: nextCursor);
      }
    } catch (_) {}
    return XPostPage(
      posts: (await fetchPosts(username)).where(keep).toList(),
    );
  }

  Future<List<XPost>> _fetchPostsFromRss(String username) async {
    final uri = Uri.parse('https://nitter.net/${Uri.encodeComponent(username)}/rss');
    try {
      final xml = await _getRaw(uri, accept: 'application/rss+xml, text/xml, */*');
      return _parseRss(xml, username);
    } catch (_) {
      return <XPost>[];
    }
  }

  List<XPost> _parseStatusList(dynamic raw, String username) {
    if (raw is! List) {
      return <XPost>[];
    }
    final posts = <XPost>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      if ('${map['type']}' != 'status') {
        continue;
      }
      final id = '${map['id'] ?? ''}';
      if (id.isEmpty) {
        continue;
      }
      final author = map['author'];
      var handle = username;
      var avatar = '';
      var name = '';
      if (author is Map) {
        if ('${author['screen_name'] ?? ''}'.isNotEmpty) {
          handle = '${author['screen_name']}';
        }
        avatar = '${author['avatar_url'] ?? ''}'.replaceFirst('_normal', '_400x400');
        name = '${author['name'] ?? ''}'.trim();
      }
      DateTime? published;
      final timestamp = map['created_timestamp'];
      if (timestamp is num && timestamp > 0) {
        published = DateTime.fromMillisecondsSinceEpoch(
          (timestamp * 1000).round(),
          isUtc: true,
        ).toLocal();
      }
      posts.add(XPost(
        id: id,
        username: handle,
        text: '${map['text'] ?? map['raw_text'] ?? ''}'.trim(),
        url: '${map['url'] ?? 'https://x.com/$handle/status/$id'}',
        publishedAt: published,
        media: _parseMedia(map['media']),
        translation: _parseTranslation(map['translation']),
        lang: '${map['lang'] ?? ''}'.trim(),
        avatarUrl: avatar,
        authorName: name,
      ));
    }
    return posts;
  }

  String _parseTranslation(dynamic raw) {
    if (raw is Map) {
      return '${raw['text'] ?? ''}'.trim();
    }
    return '';
  }

  List<XMedia> _parseMedia(dynamic raw) {
    if (raw is! Map) {
      return const <XMedia>[];
    }
    final items = raw['all'] is List
        ? List<dynamic>.from(raw['all'] as List)
        : <dynamic>[
            ...raw['photos'] is List ? List<dynamic>.from(raw['photos'] as List) : const <dynamic>[],
            ...raw['videos'] is List ? List<dynamic>.from(raw['videos'] as List) : const <dynamic>[],
          ];
    final media = <XMedia>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final type = '${map['type'] ?? ''}';
      XMediaKind kind;
      if (type == 'video') {
        kind = XMediaKind.video;
      } else if (type == 'gif') {
        kind = XMediaKind.gif;
      } else {
        kind = XMediaKind.photo;
      }
      final url = '${map['url'] ?? ''}';
      if (url.isEmpty) {
        continue;
      }
      var preview = '${map['thumbnail_url'] ?? ''}';
      if (preview.isEmpty) {
        preview = url.replaceFirst('name=orig', 'name=medium');
      }
      media.add(XMedia(
        kind: kind,
        url: url,
        previewUrl: preview,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        duration: (map['duration'] as num?)?.toDouble() ?? 0,
      ));
    }
    return media;
  }

  List<XPost> _parseRss(String xml, String username) {
    final posts = <XPost>[];
    final itemRe = RegExp(r'<item>([\s\S]*?)</item>', caseSensitive: false);
    for (final match in itemRe.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final title = _rssTag(block, 'title');
      var link = _rssTag(block, 'link');
      if (title.contains('RSS reader not yet')) {
        continue;
      }
      link = link
          .replaceFirst('https://nitter.net/', 'https://x.com/')
          .replaceFirst(RegExp(r'#.*$'), '');
      final idMatch = RegExp(r'/status/(\d+)').firstMatch(link);
      final id = idMatch?.group(1) ?? '${link.hashCode.abs()}';
      var text = title;
      final prefix = RegExp('^${RegExp.escape(username)}:\\s*', caseSensitive: false);
      text = text.replaceFirst(prefix, '');
      DateTime? published;
      final dateText = _rssTag(block, 'pubDate');
      if (dateText.isNotEmpty) {
        try {
          published = HttpDate.parse(dateText).toLocal();
        } catch (_) {}
      }
      posts.add(XPost(
        id: id,
        username: username,
        text: text,
        url: link.isEmpty ? 'https://x.com/$username' : link,
        publishedAt: published,
      ));
      if (posts.length >= 30) {
        break;
      }
    }
    return posts;
  }

  String _rssTag(String block, String tag) {
    final match = RegExp('<$tag>([\\s\\S]*?)</$tag>', caseSensitive: false).firstMatch(block);
    if (match == null) {
      return '';
    }
    var text = match.group(1) ?? '';
    text = text.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String> _getRaw(
    Uri uri, {
    String accept = 'application/json',
    bool allowNotFound = false,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 16);
    client.userAgent = _userAgent;
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Accept', accept);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode == 204) {
        await response.drain<void>();
        return '';
      }
      final body = await utf8.decodeStream(response);
      if (response.statusCode == 404 && allowNotFound) {
        return body;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XFollowingException('请求失败（HTTP ${response.statusCode}）。');
      }
      return body;
    } on SocketException {
      throw XFollowingException('无法连接，请确认 VPN/代理已开启。');
    } finally {
      client.close(force: true);
    }
  }
}
