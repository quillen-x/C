import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/x_following_service.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/phone_routes.dart';
import '../widgets/x_feed_widgets.dart';

class XFeedPage extends StatefulWidget {
  const XFeedPage({super.key});

  @override
  State<XFeedPage> createState() => _XFeedPageState();
}

class _XFeedPageState extends State<XFeedPage> {
  static const _maxDays = 14;

  final ScrollController _scroll = ScrollController();
  Map<String, XAccount> _profiles = <String, XAccount>{};
  List<XPost> _posts = <XPost>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _started = false;
  bool _autoLoadScheduled = false;
  bool _noSpecial = false;
  bool _hasMore = true;
  String? _error;
  int _loadId = 0;
  int _daysLoaded = 0;
  DateTime _cursorDay = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoLoadScheduled) {
      return;
    }
    final app = AppScope.of(context);
    if (!app.ready || !AppLayout.isCompact(context)) {
      return;
    }
    _autoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    final compact = AppLayout.isCompact(context);
    final id = ++_loadId;
    setState(() {
      _started = true;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _noSpecial = false;
      _hasMore = compact;
      _daysLoaded = 0;
      _cursorDay = _today;
      if (!compact || _posts.isEmpty) {
        _posts = <XPost>[];
      }
    });
    final app = AppScope.of(context);
    final names = await app.visibleUsernames(
      from: app.settings.xFollowing,
      specialOnly: true,
      mediaPage: AppPage.xFeed,
    );
    final profiles = await app.accountDb.loadMap();
    if (!mounted || id != _loadId) {
      return;
    }
    setState(() => _profiles = profiles);
    try {
      if (names.isEmpty) {
        if (!mounted || id != _loadId) {
          return;
        }
        setState(() {
          _posts = <XPost>[];
          _error = null;
          _noSpecial = true;
          _hasMore = false;
        });
        return;
      }
      final posts = await app.xFollowingService.fetchDayFeed(
        names,
        _cursorDay,
        onProgress: compact
            ? null
            : (items, done, total) {
                if (!mounted || id != _loadId) {
                  return;
                }
                setState(() {
                  _posts = _withAvatars(items);
                });
              },
      );
      if (!mounted || id != _loadId) {
        return;
      }
      var loaded = posts;
      var day = _cursorDay;
      var days = 1;
      while (compact && loaded.isEmpty && days < 3) {
        day = day.subtract(const Duration(days: 1));
        loaded = await app.xFollowingService.fetchDayFeed(names, day);
        days += 1;
        if (!mounted || id != _loadId) {
          return;
        }
      }
      setState(() {
        _posts = _withAvatars(loaded);
        _cursorDay = day;
        _daysLoaded = days;
        _hasMore = compact && days < _maxDays;
      });
    } catch (error) {
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() {
        _error = error.toString();
        if (_posts.isEmpty) {
          _hasMore = false;
        }
      });
    } finally {
      if (mounted && id == _loadId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (!AppLayout.isCompact(context) ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _daysLoaded >= _maxDays) {
      return;
    }
    final id = _loadId;
    final nextDay = _cursorDay.subtract(const Duration(days: 1));
    setState(() => _loadingMore = true);
    final app = AppScope.of(context);
    try {
      final names = await app.visibleUsernames(
        from: app.settings.xFollowing,
        specialOnly: true,
        mediaPage: AppPage.xFeed,
      );
      if (names.isEmpty) {
        if (mounted && id == _loadId) {
          setState(() {
            _hasMore = false;
            _noSpecial = true;
          });
        }
        return;
      }
      final posts = await app.xFollowingService.fetchDayFeed(names, nextDay);
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() {
        _cursorDay = nextDay;
        _daysLoaded += 1;
        _hasMore = _daysLoaded < _maxDays;
        _mergePosts(_withAvatars(posts));
      });
    } catch (error) {
      if (mounted && id == _loadId) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && id == _loadId) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _mergePosts(List<XPost> incoming) {
    final seen = _posts.map((post) => post.id).toSet();
    final extra = incoming.where((post) => seen.add(post.id));
    final merged = <XPost>[..._posts, ...extra];
    merged.sort((a, b) {
      final at = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    _posts = merged;
  }

  List<XPost> _withAvatars(List<XPost> posts) {
    return posts.map((post) {
      if (post.avatarUrl.isNotEmpty && post.authorName.isNotEmpty) {
        return post;
      }
      final account = _profiles[post.username.toLowerCase()];
      if (account == null) {
        return post;
      }
      return post.copyWith(
        avatarUrl: post.avatarUrl.isNotEmpty ? post.avatarUrl : account.avatarUrl,
        authorName: post.authorName.isNotEmpty ? post.authorName : account.name,
      );
    }).toList();
  }

  Future<void> _downloadPost(XPost post) async {
    final app = AppScope.of(context);
    showAppSnack(context, '已加入下载：${post.text}');
    final task = await app.downloadVideo(
      url: post.url,
      title: post.text,
      quality: VideoQuality.best,
    );
    if (!mounted) return;
    if (task.status == TaskStatus.failed) {
      showAppSnack(context, task.error, error: true);
    } else {
      showDownloadDoneSnack(context, task.savePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = AppScope.of(context).settings.xFollowing;
    final compact = AppLayout.isCompact(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBody(names.isEmpty),
        if (!compact) RefreshFab(onPressed: _load, busy: _loading),
      ],
    );
  }

  Widget _wrapPhone(Widget child, {required bool empty}) {
    return PhoneRefreshHost(
      onRefresh: _load,
      onLoadMore: _loadMore,
      hasMore: _hasMore,
      loadingMore: _loadingMore,
      empty: empty,
      child: child,
    );
  }

  Widget _buildBody(bool emptyFollowing) {
    final compact = AppLayout.isCompact(context);
    if (!_started || (_loading && _posts.isEmpty)) {
      if (compact) {
        return const Center(child: CircularProgressIndicator());
      }
      return const SizedBox.expand();
    }
    if (emptyFollowing) {
      return _wrapPhone(
        empty: true,
        const EmptyHint(
          icon: Icons.people_outline,
          title: '还没有关注任何人',
          detail: '打开底部「关注」，添加想看的账号。他们的帖子会出现在这里。',
        ),
      );
    }
    if (AppScope.of(context).settings.visibleCategories.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.tune,
          title: '还没有打开任何分类',
          detail: compact
              ? '到关注页右上角「分类」打开要看的类别。'
              : '到「分类」打开要看的类别。',
        ),
      );
    }
    if (_noSpecial) {
      return _wrapPhone(
        empty: true,
        const EmptyHint(
          icon: Icons.favorite_border_rounded,
          title: '还没有特别关注',
          detail: '当前分类里没有特别关注的账号。到「关注」里给想看的人点特别关注，这里只会加载这些人的内容。',
        ),
      );
    }
    if (_error != null && _posts.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.wifi_off_rounded,
          title: '动态加载失败',
          detail: '$_error\n请确认 VPN 已开启后再下拉刷新。',
        ),
      );
    }
    if (_posts.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.article_outlined,
          title: _loading ? '正在加载帖子' : '暂时没有帖子',
          detail: _loading
              ? '正在读取特别关注的人。'
              : '下拉刷新，或上拉看看更早的内容。',
        ),
      );
    }
    return _wrapPhone(
      empty: false,
      PostWaterfall(
        posts: _posts,
        controller: _scroll,
        columns: compact ? 1 : 3,
        showAuthor: true,
        textSize: 14.sp,
        loadingMore: compact ? _loadingMore : _loading,
        hasMore: compact ? _hasMore : _loading,
        onDownload: _downloadPost,
        padding: AppLayout.mediaHubPadding(context),
      ),
    );
  }
}

class XFollowingPage extends StatefulWidget {
  const XFollowingPage({super.key});

  @override
  State<XFollowingPage> createState() => _XFollowingPageState();
}

class _XFollowingPageState extends State<XFollowingPage> {
  static const _maxPostPages = 30;

  final _input = TextEditingController();
  final ScrollController _postsScroll = ScrollController();
  final ScrollController _listScroll = ScrollController();
  final Map<String, XAccount> _profiles = <String, XAccount>{};
  List<XPost> _posts = <XPost>[];
  List<XAccount> _related = <XAccount>[];
  String? _selected;
  String? _postsCursor;
  bool _adding = false;
  bool _loadingPosts = false;
  bool _loadingMorePosts = false;
  bool _mobileDetail = false;
  String? _postsHint;
  int _postsPages = 0;

  bool get _hasMorePosts {
    final cursor = _postsCursor;
    return cursor != null && cursor.isNotEmpty && _postsPages < _maxPostPages;
  }

  @override
  void initState() {
    super.initState();
    _postsScroll.addListener(_onPostsScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _postsScroll
      ..removeListener(_onPostsScroll)
      ..dispose();
    _listScroll.dispose();
    _input.dispose();
    super.dispose();
  }

  List<String> get _following => AppScope.of(context).settings.xFollowing;

  List<String> get _visibleFollowing {
    final app = AppScope.of(context);
    final names = _following.where((name) {
      final account = _profiles[name.toLowerCase()];
      if (account == null) {
        return app.settings.showsCategory('');
      }
      return app.showsAccount(account);
    }).toList();
    names.sort((a, b) {
      final specialA = _profiles[a.toLowerCase()]?.special == true;
      final specialB = _profiles[b.toLowerCase()]?.special == true;
      if (specialA != specialB) {
        return specialA ? -1 : 1;
      }
      final followersA = _profiles[a.toLowerCase()]?.followers ?? 0;
      final followersB = _profiles[b.toLowerCase()]?.followers ?? 0;
      final byFollowers = followersB.compareTo(followersA);
      if (byFollowers != 0) {
        return byFollowers;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return names;
  }

  String get _accountListEmptyHint {
    if (_following.isEmpty) {
      return '还没有关注';
    }
    if (AppScope.of(context).settings.visibleCategories.isEmpty) {
      return '到分类页打开';
    }
    return '当前分类下没有关注';
  }

  Future<void> _bootstrap() async {
    await _loadProfilesFromDb();
    if (!mounted) {
      return;
    }
    final names = _visibleFollowing;
    if (names.isEmpty) {
      return;
    }
    if (AppLayout.isCompact(context)) {
      return;
    }
    await _select(names.first);
  }

  Future<void> _loadProfilesFromDb() async {
    final map = await AppScope.of(context).accountDb.loadMap();
    if (!mounted) {
      return;
    }
    setState(() => _profiles.addAll(map));
  }

  Future<void> _add() async {
    await _addUsername(_input.text.trim());
  }

  Future<void> _addUsername(String raw) async {
    final app = AppScope.of(context);
    final username = XFollowingService.extractUsername(raw);
    if (username == null) {
      showAppSnack(context, '请输入用户名，例如 NASA', error: true);
      return;
    }
    final exists = _following.any((item) => item.toLowerCase() == username.toLowerCase());
    if (exists) {
      _input.clear();
      await _revealInList(username);
      return;
    }
    setState(() => _adding = true);
    try {
      final fetched = await app.xFollowingService.fetchAccount(username);
      final account = await app.followAndSave(fetched);
      if (!mounted) return;
      _input.clear();
      setState(() => _profiles[account.username.toLowerCase()] = account);
      showAppSnack(
        context,
        '已关注 @${account.username}，已加入「${XAccount.categoryLabel(account.category)}」',
      );
      await _revealInList(account.username);
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _remove(String username) async {
    final app = AppScope.of(context);
    final visible = _visibleFollowing;
    final removedIndex = visible.indexWhere(
      (name) => name.toLowerCase() == username.toLowerCase(),
    );
    final wasSelected = _selected?.toLowerCase() == username.toLowerCase();
    await app.unfollowXAccount(username);
    if (!mounted) return;
    setState(() {
      _profiles.remove(username.toLowerCase());
      if (wasSelected) {
        final names = _visibleFollowing;
        if (names.isEmpty) {
          _selected = null;
          _mobileDetail = false;
        } else if (removedIndex >= names.length) {
          _selected = names.last;
        } else if (removedIndex >= 0) {
          _selected = names[removedIndex];
        } else {
          _selected = names.first;
        }
        _posts = <XPost>[];
        _postsCursor = null;
        _postsPages = 0;
        _related = <XAccount>[];
      }
    });
    if (wasSelected && _selected != null) {
      await _select(_selected!);
    }
  }

  Future<void> _toggleSpecial(String username) async {
    final app = AppScope.of(context);
    final key = username.toLowerCase();
    final current = _profiles[key];
    final next = !(current?.special ?? false);
    try {
      if (current == null) {
        final fetched = await app.xFollowingService.fetchAccount(username);
        final tagged = fetched.copyWith(
          category: app.followCategory,
          special: next,
        );
        await app.accountDb.upsert(tagged);
        await app.accountDb.updateCategory(tagged.username, tagged.category);
        await app.accountDb.updateSpecial(tagged.username, next);
        if (!mounted) {
          return;
        }
        setState(() => _profiles[tagged.username.toLowerCase()] = tagged);
      } else {
        await app.accountDb.updateSpecial(username, next);
        if (!mounted) {
          return;
        }
        setState(() => _profiles[key] = current.copyWith(special: next));
      }
      if (!mounted) {
        return;
      }
      showAppSnack(
        context,
        next ? '已特别关注 @$username' : '已取消特别关注 @$username',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    }
  }

  Future<void> _select(String username) async {
    final app = AppScope.of(context);
    setState(() {
      _selected = username;
      _loadingPosts = true;
      _loadingMorePosts = false;
      _related = <XAccount>[];
      _postsHint = null;
      _postsCursor = null;
      _postsPages = 0;
      if (AppLayout.isCompact(context)) {
        _mobileDetail = true;
      }
    });
    if (_postsScroll.hasClients) {
      _postsScroll.jumpTo(0);
    }
    try {
      if (!_profiles.containsKey(username.toLowerCase())) {
        final account = await app.xFollowingService.fetchAccount(username);
        await app.accountDb.upsert(account);
        if (!mounted) return;
        setState(() => _profiles[account.username.toLowerCase()] = account);
      }
      try {
        final page = await app.xFollowingService.fetchPostsPage(username);
        if (!mounted || _selected?.toLowerCase() != username.toLowerCase()) {
          return;
        }
        setState(() {
          _posts = page.posts;
          _postsCursor = page.cursor;
          _postsPages = 1;
          _postsHint = page.posts.isEmpty ? '动态暂时无法在应用内展开。' : null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _posts = <XPost>[];
          _postsCursor = null;
          _postsHint = error.toString();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posts = <XPost>[];
        _postsCursor = null;
        _postsHint = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loadingPosts = false);
      }
    }
  }

  void _onPostsScroll() {
    if (!_postsScroll.hasClients || !_hasMorePosts || _loadingMorePosts || _loadingPosts) {
      return;
    }
    final position = _postsScroll.position;
    if (position.pixels >= position.maxScrollExtent - 160) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    final username = _selected;
    if (username == null || _loadingMorePosts || !_hasMorePosts) {
      return;
    }
    setState(() => _loadingMorePosts = true);
    try {
      final page = await AppScope.of(context).xFollowingService.fetchPostsPage(
        username,
        cursor: _postsCursor,
      );
      if (!mounted || _selected?.toLowerCase() != username.toLowerCase()) {
        return;
      }
      setState(() {
        final seen = _posts.map((item) => item.id).toSet();
        final added = page.posts.where((item) => seen.add(item.id)).toList();
        _posts.addAll(added);
        _postsCursor = added.isEmpty ? null : page.cursor;
        _postsPages += 1;
      });
    } catch (_) {
      if (!mounted || _selected?.toLowerCase() != username.toLowerCase()) {
        return;
      }
      setState(() => _postsCursor = null);
    } finally {
      if (mounted) {
        setState(() => _loadingMorePosts = false);
      }
    }
  }

  Future<void> _followAccount(XAccount account) async {
    final app = AppScope.of(context);
    final exists = _following.any(
      (item) => item.toLowerCase() == account.username.toLowerCase(),
    );
    if (exists) {
      await _revealInList(account.username);
      return;
    }
    final saved = await app.followAndSave(account);
    if (!mounted) {
      return;
    }
    setState(() => _profiles[saved.username.toLowerCase()] = saved);
    showAppSnack(
      context,
      '已关注 @${saved.username}，已加入「${XAccount.categoryLabel(saved.category)}」',
    );
    await _revealInList(saved.username);
  }

  Future<void> _revealInList(String username) async {
    final names = _visibleFollowing;
    final inList = names.any(
      (name) => name.toLowerCase() == username.toLowerCase(),
    );
    if (!inList) {
      showAppSnack(context, '已经关注 @$username');
      return;
    }
    if (_selected?.toLowerCase() != username.toLowerCase()) {
      await _select(username);
    }
    _scrollToName(username);
  }

  void _scrollToName(String username) {
    final names = _visibleFollowing;
    final index = names.indexWhere(
      (name) => name.toLowerCase() == username.toLowerCase(),
    );
    if (index < 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScroll.hasClients) {
        return;
      }
      final itemHeight = 60.h;
      final target = (index * itemHeight).clamp(
        0.0,
        _listScroll.position.maxScrollExtent,
      );
      _listScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _followAccounts(List<XAccount> accounts) async {
    final app = AppScope.of(context);
    final pending = <XAccount>[];
    for (final account in accounts) {
      final exists = _following.any(
        (item) => item.toLowerCase() == account.username.toLowerCase(),
      );
      if (exists) {
        continue;
      }
      pending.add(account);
    }
    if (pending.isEmpty) {
      showAppSnack(context, '这些账号都已经关注了');
      return;
    }
    final saved = await app.followAndSaveAll(pending);
    if (!mounted) {
      return;
    }
    setState(() {
      for (final account in saved) {
        _profiles[account.username.toLowerCase()] = account;
      }
    });
    final label = XAccount.categoryLabel(app.followCategory);
    showAppSnack(context, '已关注 ${saved.length} 人，已加入「$label」');
  }

  Future<void> _openFollowing(String username) async {
    if (_related.isNotEmpty) {
      _showAccountList(
        context: context,
        title: '关注了',
        accounts: _related,
        followed: _following,
        onFollow: _followAccount,
        onFollowAll: _followAccounts,
      );
      return;
    }
    _showAccountList(
      context: context,
      title: '关注了',
      followed: _following,
      onFollow: _followAccount,
      onFollowAll: _followAccounts,
      loader: () async {
        final accounts = await AppScope.of(context).xFollowingService.fetchFollowing(
          username,
        );
        if (mounted && _selected?.toLowerCase() == username.toLowerCase()) {
          _related = accounts;
        }
        return accounts;
      },
    );
  }

  Future<void> _openFollowers(String username) async {
    _showAccountList(
      context: context,
      title: '关注者',
      followed: _following,
      onFollow: _followAccount,
      onFollowAll: _followAccounts,
      loader: () => AppScope.of(context).xFollowingService.fetchFollowers(username),
    );
  }

  Future<void> _downloadPost(XPost post) async {
    final app = AppScope.of(context);
    showAppSnack(context, '已加入下载：${post.text}');
    final task = await app.downloadVideo(
      url: post.url,
      title: post.text,
      quality: VideoQuality.best,
    );
    if (!mounted) return;
    if (task.status == TaskStatus.failed) {
      showAppSnack(context, task.error, error: true);
    } else {
      showDownloadDoneSnack(context, task.savePath);
    }
  }

  void _syncSelectionToVisible(List<String> names) {
    if (_selected == null) {
      return;
    }
    final visible = names.any(
      (name) => name.toLowerCase() == _selected!.toLowerCase(),
    );
    if (visible) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final visibleNames = _visibleFollowing;
      if (_selected != null &&
          visibleNames.any(
            (name) => name.toLowerCase() == _selected!.toLowerCase(),
          )) {
        return;
      }
      if (visibleNames.isEmpty || AppLayout.isCompact(context)) {
        setState(() {
          _selected = null;
          _posts = <XPost>[];
          _postsCursor = null;
          _postsPages = 0;
          _related = <XAccount>[];
          _mobileDetail = false;
        });
        return;
      }
      _select(visibleNames.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = _visibleFollowing;
    _syncSelectionToVisible(names);
    final compact = AppLayout.isCompact(context);
    if (compact && _mobileDetail && _selected != null) {
      final profile = _profiles[_selected!.toLowerCase()];
      final title = (profile?.name.trim().isNotEmpty ?? false)
          ? profile!.name.trim()
          : '@$_selected';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneNavBar(
            title: title,
            centerTitle: true,
            onBack: () => setState(() => _mobileDetail = false),
          ),
          Expanded(
            child: _DetailPane(
              account: profile,
              username: _selected,
              posts: _posts,
              loading: _loadingPosts,
              loadingMore: _loadingMorePosts,
              hasMore: _hasMorePosts,
              hint: _postsHint,
              postsScroll: _postsScroll,
              onDownload: _downloadPost,
              onOpenFollowers: () => _openFollowers(_selected!),
              onOpenFollowing: () => _openFollowing(_selected!),
              onLoadMore: _loadMorePosts,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          const PhoneNavBar(
            title: '关注',
            centerTitle: true,
            trailing: PhoneCategoryButton(),
          ),
        Expanded(
          child: Padding(
            padding: AppLayout.pagePadding(
              context,
              top: compact ? 8 : 16,
              bottom: compact ? 8 : 16,
            ).copyWith(
              left: compact ? 8.w : 16.w,
              right: compact ? 8.w : 16.w,
            ),
            child: compact
                ? _AccountList(
                    names: names,
                    selected: _selected,
                    profiles: _profiles,
                    emptyHint: _accountListEmptyHint,
                    input: _input,
                    adding: _adding,
                    controller: _listScroll,
                    onAdd: _add,
                    onSelect: _select,
                    onToggleSpecial: _toggleSpecial,
                    onRemove: _remove,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 250.w,
                        child: _AccountList(
                          names: names,
                          selected: _selected,
                          profiles: _profiles,
                          emptyHint: _accountListEmptyHint,
                          input: _input,
                          adding: _adding,
                          controller: _listScroll,
                          onAdd: _add,
                          onSelect: _select,
                          onToggleSpecial: _toggleSpecial,
                          onRemove: _remove,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded( 
                        child: _DetailPane(
                          account: _selected == null
                              ? null
                              : _profiles[_selected!.toLowerCase()],
                          username: _selected,
                          posts: _posts,
                          loading: _loadingPosts,
                          loadingMore: _loadingMorePosts,
                          hasMore: _hasMorePosts,
                          hint: _postsHint,
                          postsScroll: _postsScroll,
                          onDownload: _downloadPost,
                          onOpenFollowers: _selected == null
                              ? null
                              : () => _openFollowers(_selected!),
                          onOpenFollowing: _selected == null
                              ? null
                              : () => _openFollowing(_selected!),
                          onLoadMore: _loadMorePosts,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({
    required this.username,
    required this.label,
    required this.followed,
    required this.enabled,
    required this.onTap,
  });

  final String username;
  final String label;
  final bool followed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: followed ? AppColors.surfaceAlt : AppColors.surface,
      borderRadius: BorderRadius.circular(999.w),
      child: InkWell(
        onTap: followed || !enabled ? null : onTap,
        borderRadius: BorderRadius.circular(999.w),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          child: Text(
            followed ? '@$username · 已关注' : '@$username · $label',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: followed ? AppColors.textMuted : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.names,
    required this.selected,
    required this.profiles,
    required this.emptyHint,
    required this.input,
    required this.adding,
    required this.controller,
    required this.onAdd,
    required this.onSelect,
    required this.onToggleSpecial,
    required this.onRemove,
  });

  final List<String> names;
  final String? selected;
  final Map<String, XAccount> profiles;
  final String emptyHint;
  final TextEditingController input;
  final bool adding;
  final ScrollController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggleSpecial;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final list = Expanded(
      child: names.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Text(
                  emptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
                ),
              ),
            )
          : ScrollbarTheme(
              data: ScrollbarThemeData(
                crossAxisMargin: 0,
                mainAxisMargin: 4.h,
                thickness: WidgetStateProperty.all(7.w),
                radius: Radius.circular(8.w),
              ),
              child: ListView.builder(
                controller: controller,
                padding: EdgeInsets.only(right: compact ? 0 : 2.w),
                itemCount: names.length,
                itemBuilder: (context, index) {
                  final username = names[index];
                  final account = profiles[username.toLowerCase()];
                  final displayName = (account?.name ?? '').trim().isEmpty
                      ? username
                      : account!.name;
                  final isSelected = selected?.toLowerCase() == username.toLowerCase();
                  return Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Material(
                      color: compact
                          ? Colors.transparent
                          : (isSelected
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : Colors.transparent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.w),
                        side: BorderSide(
                          color: !compact && isSelected
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 1.4.w,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => onSelect(username),
                        borderRadius: BorderRadius.circular(10.w),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 8.w : 6.w,
                            compact ? 10.h : 8.h,
                            compact ? 6.w : 4.w,
                            compact ? 10.h : 8.h,
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: compact ? 2.w : 4.w),
                              XAvatar(
                                url: account?.avatarUrl ?? '',
                                size: compact ? 40 : 28,
                              ),
                              SizedBox(width: compact ? 10.w : 8.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: compact ? 16.sp : 13.sp,
                                        color: compact || isSelected
                                            ? AppColors.text
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                    Text(
                                      '@$username',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected ? AppColors.accent : AppColors.textMuted,
                                        fontSize: compact ? 13.sp : 11.sp,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: account?.special == true
                                    ? '取消特别关注'
                                    : '特别关注',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(
                                  minWidth: compact ? 36.w : 28.w,
                                  minHeight: compact ? 36.w : 28.w,
                                ),
                                onPressed: () => onToggleSpecial(username),
                                icon: Icon(
                                  account?.special == true
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: compact ? 22.w : 16.w,
                                  color: account?.special == true
                                      ? AppColors.danger
                                      : (isSelected
                                          ? AppColors.textMuted
                                          : AppColors.border),
                                ),
                              ),
                              IconButton(
                                tooltip: '取消关注',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(
                                  minWidth: compact ? 36.w : 28.w,
                                  minHeight: compact ? 36.w : 28.w,
                                ),
                                onPressed: () => onRemove(username),
                                icon: Icon(
                                  Icons.close,
                                  size: compact ? 22.w : 16.w,
                                  color: isSelected ? AppColors.text : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          Padding(
            padding: EdgeInsets.only(right: 10.w),
            child: InlineActionField(
              controller: input,
              hint: 'NASA',
              actionLabel: '关注',
              busy: adding,
              onAction: onAdd,
            ),
          ),
          SizedBox(height: 10.h),
        ],
        list,
      ],
    );
    if (compact) {
      return body;
    }
    return SectionCard(
      padding: EdgeInsets.fromLTRB(10.w, 12.h, 0, 10.h),
      child: body,
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.account,
    required this.username,
    required this.posts,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.hint,
    required this.postsScroll,
    required this.onDownload,
    this.onOpenFollowers,
    this.onOpenFollowing,
    required this.onLoadMore,
  });

  final XAccount? account;
  final String? username;
  final List<XPost> posts;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? hint;
  final ScrollController postsScroll;
  final ValueChanged<XPost> onDownload;
  final VoidCallback? onOpenFollowers;
  final VoidCallback? onOpenFollowing;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (username == null) {
      if (AppLayout.isCompact(context)) {
        return const EmptyHint(
          icon: Icons.people_outline,
          title: '从这里开始',
          detail: '在上方添加 C 用户名，或点推荐账号一键关注。之后可以查看资料，并尝试下载对方帖子中的视频。',
        );
      }
      return const SectionCard(
        child: EmptyHint(
          icon: Icons.people_outline,
          title: '从这里开始',
          detail: '在上方添加 C 用户名，或点推荐账号一键关注。之后可以查看资料，并尝试下载对方帖子中的视频。',
        ),
      );
    }
    final compact = AppLayout.isCompact(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (account != null)
          _ProfileHeader(
            account: account!,
            onOpenFollowers: onOpenFollowers,
            onOpenFollowing: onOpenFollowing,
          ),
        if (account == null)
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Text('@$username', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (!compact) Divider(height: 1.h, color: AppColors.border),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : posts.isEmpty
                  ? EmptyHint(
                      icon: Icons.article_outlined,
                      title: '没有展开动态',
                      detail: hint ?? '这个账号暂时没有可展示的帖子。',
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 160 && hasMore && !loadingMore) {
                          onLoadMore();
                        }
                        return false;
                      },
                      child: PostWaterfall(
                        posts: posts,
                        controller: postsScroll,
                        columns: compact ? 1 : 2,
                        loadingMore: loadingMore,
                        hasMore: hasMore,
                        onDownload: onDownload,
                        framed: !compact,
                        textSize: 13.sp,
                        textWeight: FontWeight.w300,
                      ),
                    ),
        ),
      ],
    );
    if (compact) {
      return body;
    }
    return SectionCard(
      padding: EdgeInsets.zero,
      child: body,
    );
  }
}

void _showAccountList({
  required BuildContext context,
  required String title,
  required List<String> followed,
  required ValueChanged<XAccount> onFollow,
  required ValueChanged<List<XAccount>> onFollowAll,
  List<XAccount>? accounts,
  Future<List<XAccount>> Function()? loader,
}) {
  Widget buildList({required bool asPage}) {
    return _FollowingListDialog(
      title: title,
      accounts: accounts,
      loader: loader,
      followed: followed,
      onFollow: onFollow,
      onFollowAll: onFollowAll,
      asPage: asPage,
    );
  }

  if (AppLayout.isCompact(context)) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.navBar,
            body: SafeArea(
              child: ColoredBox(
                color: AppColors.bg,
                child: buildList(asPage: true),
              ),
            ),
          );
        },
      ),
    );
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return buildList(asPage: false);
    },
  );
}

class _FollowingListDialog extends StatefulWidget {
  const _FollowingListDialog({
    required this.title,
    required this.followed,
    required this.onFollow,
    required this.onFollowAll,
    this.accounts,
    this.loader,
    this.asPage = false,
  });

  final String title;
  final List<XAccount>? accounts;
  final Future<List<XAccount>> Function()? loader;
  final List<String> followed;
  final ValueChanged<XAccount> onFollow;
  final ValueChanged<List<XAccount>> onFollowAll;
  final bool asPage;

  @override
  State<_FollowingListDialog> createState() => _FollowingListDialogState();
}

class _FollowingListDialogState extends State<_FollowingListDialog> {
  late List<String> _followed;
  List<XAccount> _accounts = <XAccount>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _followed = List<String>.from(widget.followed);
    final existing = widget.accounts;
    if (existing != null) {
      _accounts = _sortedByFollowers(existing);
      if (_accounts.isEmpty) {
        _error = '暂时无法加载${widget.title}';
      }
    } else if (widget.loader != null) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final accounts = await widget.loader!();
      if (!mounted) {
        return;
      }
      setState(() {
        _accounts = _sortedByFollowers(accounts);
        _loading = false;
        _error = accounts.isEmpty ? '暂时无法加载${widget.title}' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<XAccount> _sortedByFollowers(List<XAccount> accounts) {
    return List<XAccount>.from(accounts)
      ..sort((a, b) {
        final byFollowers = b.followers.compareTo(a.followers);
        if (byFollowers != 0) {
          return byFollowers;
        }
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });
  }

  bool _isFollowed(String username) {
    return _followed.any((name) => name.toLowerCase() == username.toLowerCase());
  }

  void _follow(XAccount account) {
    if (_isFollowed(account.username)) {
      return;
    }
    widget.onFollow(account);
    setState(() => _followed.add(account.username));
  }

  void _followAll() {
    final pending = _accounts
        .where((account) => !_isFollowed(account.username))
        .toList();
    if (pending.isEmpty) {
      return;
    }
    widget.onFollowAll(pending);
    setState(() {
      _followed.addAll(pending.map((account) => account.username));
    });
  }

  Widget _accountRow(int index) {
    final account = _accounts[index];
    final already = _isFollowed(account.username);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.asPage ? 10.h : 8.h),
      child: Row(
        children: [
          if (!widget.asPage)
            SizedBox(
              width: 28.w,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          XAvatar(url: account.avatarUrl, size: 36),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.sp),
                ),
                Text(
                  '@${account.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                ),
              ],
            ),
          ),
          already
              ? Text(
                  '已关注',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                )
              : TextButton(
                  onPressed: () => _follow(account),
                  child: Text(
                    '关注',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final canFollowAll = !_loading &&
        _accounts.any((account) => !_isFollowed(account.username));
    final title = widget.title;
    final followAll = TextButton(
      onPressed: canFollowAll ? _followAll : null,
      child: Text(
        '全部关注',
        style: TextStyle(
          color: canFollowAll ? AppColors.accent : AppColors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 14.sp,
        ),
      ),
    );
    final list = Expanded(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyHint(
                  icon: Icons.people_outline,
                  title: widget.title,
                  detail: _error!,
                )
              : widget.asPage
                  ? ListView.builder(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) => _accountRow(index),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
                      itemCount: _accounts.length,
                      separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border),
                      itemBuilder: (context, index) => _accountRow(index),
                    ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.asPage)
          PhoneNavBar(
            title: title,
            centerTitle: true,
            onBack: () => Navigator.of(context).pop(),
            trailing: followAll,
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 14.h, 8.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                  ),
                ),
                followAll,
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        if (!widget.asPage) Divider(height: 1.h, color: AppColors.border),
        list,
      ],
    );
    if (widget.asPage) {
      return ColoredBox(color: AppColors.bg, child: body);
    }
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 48.w,
        vertical: 40.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480.w,
          maxHeight: size.height * 0.72,
        ),
        child: body,
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.account,
    this.onOpenFollowing,
    this.onOpenFollowers,
  });

  final XAccount account;
  final VoidCallback? onOpenFollowing;
  final VoidCallback? onOpenFollowers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              XAvatar(url: account.avatarUrl, size: 56),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 2.h),
                    Tooltip(
                      message: '点击复制用户名',
                      child: InkWell(
                        onTap: () async {
                          await copyText(account.username);
                          if (!context.mounted) {
                            return;
                          }
                          showAppSnack(context, '已复制 @${account.username}');
                        },
                        child: Text(
                          '@${account.username}${account.protected ? ' · 已保护' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _stats(),
            ],
          ),
          if (account.description.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              account.description.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r' +'), ' ').trim(),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5.sp, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stats() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        onOpenFollowers == null
            ? _stat(value: formatCount(account.followers), label: '关注者')
            : _stat(
                value: formatCount(account.followers),
                label: '关注者',
                onTap: onOpenFollowers,
              ),
        _stat(
          value: formatCount(account.following),
          label: '关注了',
          onTap: onOpenFollowing,
        ),
        _stat(value: formatCount(account.tweets), label: '帖子'),
      ],
    );
  }

  Widget _stat({
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    final child = SizedBox(
      width: 64.w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: onTap == null ? AppColors.text : AppColors.accent,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.sp,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

Future<bool> showAccountHome(BuildContext context, XAccount account) async {
  if (AppLayout.isCompact(context)) {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.navBar,
            body: SafeArea(
              child: ColoredBox(
                color: AppColors.bg,
                child: _AccountHomeDialog(account: account, asPage: true),
              ),
            ),
          );
        },
      ),
    );
    return result == true;
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _AccountHomeDialog(account: account);
    },
  );
  return result == true;
}

Future<void> openXMention(BuildContext context, String raw) async {
  final username = XFollowingService.extractUsername(raw);
  if (username == null) {
    return;
  }
  final app = AppScope.of(context);
  try {
    var account = await app.accountDb.get(username);
    account ??= await app.xFollowingService.fetchAccount(username);
    if (!context.mounted) {
      return;
    }
    await showAccountHome(context, account);
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    showAppSnack(context, '无法打开 @$username', error: true);
  }
}

class _AccountHomeDialog extends StatefulWidget {
  const _AccountHomeDialog({
    required this.account,
    this.asPage = false,
  });

  final XAccount account;
  final bool asPage;

  @override
  State<_AccountHomeDialog> createState() => _AccountHomeDialogState();
}

class _AccountHomeDialogState extends State<_AccountHomeDialog> {
  static const _maxPostPages = 30;

  final ScrollController _postsScroll = ScrollController();
  late XAccount _account = widget.account;
  List<XPost> _posts = <XPost>[];
  List<XAccount> _related = <XAccount>[];
  String? _postsCursor;
  String? _hint;
  bool _loadingPosts = true;
  bool _loadingMore = false;
  int _pages = 0;
  bool _followed = false;
  bool _busy = false;
  bool _unfollowed = false;
  String? _targetCategory;

  bool get _hasMore {
    final cursor = _postsCursor;
    return cursor != null && cursor.isNotEmpty && _pages < _maxPostPages;
  }

  List<String> get _categoryOptions {
    final keys = <String>{};
    for (final item in AppScope.of(context).settings.categories) {
      final key = item.trim().toLowerCase();
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    final current = (_targetCategory ?? _account.category).trim().toLowerCase();
    if (current.isNotEmpty) {
      keys.add(current);
    }
    final list = keys.toList()..sort();
    return list;
  }

  String? get _effectiveCategory {
    final selected = _targetCategory?.trim().toLowerCase() ?? '';
    if (selected.isNotEmpty) {
      return selected;
    }
    final accountCat = _account.category.trim().toLowerCase();
    if (accountCat.isNotEmpty) {
      return accountCat;
    }
    final follow = AppScope.of(context).followCategory.trim().toLowerCase();
    if (follow.isNotEmpty) {
      return follow;
    }
    final options = _categoryOptions;
    return options.isEmpty ? null : options.first;
  }

  @override
  void initState() {
    super.initState();
    _postsScroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _postsScroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_postsScroll.hasClients || !_hasMore || _loadingMore || _loadingPosts) {
      return;
    }
    final position = _postsScroll.position;
    if (position.pixels >= position.maxScrollExtent - 160) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final username = widget.account.username;
    final inSettings = app.settings.xFollowing.any(
      (item) => item.toLowerCase() == username.toLowerCase(),
    );
    final cached = await app.accountDb.get(username);
    if (mounted) {
      setState(() {
        _followed = inSettings;
        if (cached != null) {
          _account = cached;
          final key = cached.category.trim().toLowerCase();
          if (key.isNotEmpty) {
            _targetCategory = key;
          }
        }
      });
    }
    try {
      final profile = await app.xFollowingService.fetchAccount(username);
      if (mounted) {
        setState(() {
          _account = profile.copyWith(
            category: _account.category,
            special: _account.special,
          );
        });
      }
    } catch (_) {}
    try {
      final page = await app.xFollowingService.fetchPostsPage(username);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = page.posts;
        _postsCursor = page.cursor;
        _pages = 1;
        _hint = page.posts.isEmpty ? '动态暂时无法在应用内展开。' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = <XPost>[];
        _postsCursor = null;
        _hint = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loadingPosts = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await AppScope.of(context).xFollowingService.fetchPostsPage(
        widget.account.username,
        cursor: _postsCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = <XPost>[..._posts, ...page.posts];
        _postsCursor = page.cursor;
        _pages += 1;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _followAccount(XAccount account) async {
    final app = AppScope.of(context);
    final exists = app.settings.xFollowing.any(
      (item) => item.toLowerCase() == account.username.toLowerCase(),
    );
    if (exists) {
      return;
    }
    final saved = await app.followAndSave(account);
    if (!mounted) {
      return;
    }
    showAppSnack(
      context,
      '已关注 @${saved.username}，已加入「${XAccount.categoryLabel(saved.category)}」',
    );
  }

  Future<void> _followAccounts(List<XAccount> accounts) async {
    final app = AppScope.of(context);
    final pending = accounts
        .where(
          (account) => !app.settings.xFollowing.any(
            (item) => item.toLowerCase() == account.username.toLowerCase(),
          ),
        )
        .toList();
    if (pending.isEmpty) {
      showAppSnack(context, '这些账号都已经关注了');
      return;
    }
    final saved = await app.followAndSaveAll(pending);
    if (!mounted) {
      return;
    }
    showAppSnack(
      context,
      '已关注 ${saved.length} 人，已加入「${XAccount.categoryLabel(app.followCategory)}」',
    );
  }

  Future<void> _selectCategory(String key) async {
    if (_busy) {
      return;
    }
    final next = key.trim().toLowerCase();
    if (next.isEmpty) {
      return;
    }
    setState(() => _targetCategory = next);
    if (!_followed) {
      return;
    }
    final app = AppScope.of(context);
    try {
      await app.accountDb.updateCategory(widget.account.username, next);
      await app.ensureCategory(next, show: true);
      if (!mounted) {
        return;
      }
      setState(() => _account = _account.copyWith(category: next));
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    }
  }

  Future<void> _promptNewCategory() async {
    if (_busy) {
      return;
    }
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('新增类别'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.text),
            cursorColor: AppColors.accent,
            decoration: const InputDecoration(
              hintText: '例如 news',
              hintStyle: TextStyle(color: AppColors.textMuted),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) {
      return;
    }
    final key = result.trim().toLowerCase();
    if (key.isEmpty) {
      showAppSnack(context, '请输入分类名', error: true);
      return;
    }
    await AppScope.of(context).ensureCategory(key);
    if (!mounted) {
      return;
    }
    await _selectCategory(key);
  }

  Future<void> _followSelf() async {
    if (_busy || _followed) {
      return;
    }
    var category = _effectiveCategory;
    if (category == null || category.isEmpty) {
      await _promptNewCategory();
      if (!mounted) {
        return;
      }
      category = _targetCategory;
      if (category == null || category.isEmpty) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final saved = await AppScope.of(context).followAndSave(
        _account,
        category: category,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _followed = true;
        _unfollowed = false;
        _account = saved;
        _targetCategory = saved.categoryKey;
      });
      showAppSnack(
        context,
        '已关注 @${saved.username}，已加入「${XAccount.categoryLabel(saved.category)}」',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unfollow() async {
    if (_busy || !_followed) {
      return;
    }
    setState(() => _busy = true);
    try {
      final app = AppScope.of(context);
      await app.unfollowXAccount(widget.account.username);
      await app.accountDb.delete(widget.account.username);
      if (!mounted) {
        return;
      }
      setState(() {
        _followed = false;
        _unfollowed = true;
        _account = _account.copyWith(category: '');
      });
      showAppSnack(context, '已取消关注 @${widget.account.username}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openFollowing() async {
    if (_related.isNotEmpty) {
      _showAccountList(
        context: context,
        title: '关注了',
        accounts: _related,
        followed: AppScope.of(context).settings.xFollowing,
        onFollow: _followAccount,
        onFollowAll: _followAccounts,
      );
      return;
    }
    _showAccountList(
      context: context,
      title: '关注了',
      followed: AppScope.of(context).settings.xFollowing,
      onFollow: _followAccount,
      onFollowAll: _followAccounts,
      loader: () async {
        final accounts = await AppScope.of(context).xFollowingService.fetchFollowing(
          widget.account.username,
        );
        if (mounted) {
          _related = accounts;
        }
        return accounts;
      },
    );
  }

  Future<void> _openFollowers() async {
    _showAccountList(
      context: context,
      title: '关注者',
      followed: AppScope.of(context).settings.xFollowing,
      onFollow: _followAccount,
      onFollowAll: _followAccounts,
      loader: () => AppScope.of(context).xFollowingService.fetchFollowers(
        widget.account.username,
      ),
    );
  }

  Future<void> _downloadPost(XPost post) async {
    final app = AppScope.of(context);
    showAppSnack(context, '已加入下载：${post.text}');
    final task = await app.downloadVideo(
      url: post.url,
      title: post.text,
      quality: VideoQuality.best,
    );
    if (!mounted) {
      return;
    }
    if (task.status == TaskStatus.failed) {
      showAppSnack(context, task.error, error: true);
    } else {
      showDownloadDoneSnack(context, task.savePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final asPage = widget.asPage;
    final title = _account.name.trim().isNotEmpty
        ? _account.name.trim()
        : '@${_account.username}';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asPage)
          PhoneNavBar(
            title: title,
            centerTitle: true,
            onBack: () => Navigator.of(context).pop(_unfollowed),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(8.w, 6.h, 8.w, 0),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: '点击复制用户名',
                    child: InkWell(
                      onTap: () async {
                        await copyText(widget.account.username);
                        if (!context.mounted) {
                          return;
                        }
                        showAppSnack(context, '已复制 @${widget.account.username}');
                      },
                      child: Text(
                        '@${widget.account.username}',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(_unfollowed),
                  icon: Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        _ProfileHeader(
          account: _account,
          onOpenFollowers: () => _openFollowers(),
          onOpenFollowing: () => _openFollowing(),
        ),
        _followBar(),
        if (!asPage) Divider(height: 1.h, color: AppColors.border),
        Expanded(
          child: _loadingPosts
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
                  ? EmptyHint(
                      icon: Icons.article_outlined,
                      title: '没有展开动态',
                      detail: _hint ?? '这个账号暂时没有可展示的帖子。',
                    )
                  : ListView.separated(
                      controller: _postsScroll,
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
                      itemCount: _posts.length + (_loadingMore || _hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => SizedBox(height: asPage ? 4.h : 10.h),
                      itemBuilder: (context, index) {
                        if (index >= _posts.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            child: Center(
                              child: _loadingMore
                                  ? SizedBox(
                                      width: 20.w,
                                      height: 20.w,
                                      child: CircularProgressIndicator(strokeWidth: 2.w),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          );
                        }
                        return PostCard(
                          key: ValueKey(_posts[index].id),
                          post: _posts[index],
                          onDownload: _downloadPost,
                          onTap: () => showPostComments(context, _posts[index]),
                          framed: !asPage,
                          textSize: 16.sp,
                          textWeight: FontWeight.w300,
                        );
                      },
                    ),
        ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        Navigator.of(context).pop(_unfollowed);
      },
      child: asPage
          ? ColoredBox(color: AppColors.bg, child: body)
          : Dialog(
              backgroundColor: AppColors.surface,
              insetPadding: EdgeInsets.symmetric(
                horizontal: 80.w,
                vertical: 16.h,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420.w,
                  maxHeight: size.height * 0.94,
                ),
                child: body,
              ),
            ),
    );
  }

  Widget _followBar() {
    final selected = _effectiveCategory;
    final options = _categoryOptions;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 8.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final key in options) ...[
                    _chip(
                      label: XAccount.categoryLabel(key),
                      selected: selected == key,
                      onTap: () => _selectCategory(key),
                    ),
                    SizedBox(width: 6.w),
                  ],
                  _chip(
                    label: '+ 新增',
                    selected: false,
                    onTap: _promptNewCategory,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 4.w),
          if (_busy)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: SizedBox(
                width: 16.w,
                height: 16.w,
                child: CircularProgressIndicator(strokeWidth: 2.w),
              ),
            )
          else if (_followed)
            TextButton(
              onPressed: _unfollow,
              child: Text(
                '取消关注',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.sp,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _followSelf,
              child: Text(
                '关注',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.sp,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.x : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 28.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.black : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

