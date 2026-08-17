import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/io_helpers.dart';
import '../services/x_following_service.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import '../widgets/media_viewer.dart';

class XFeedPage extends StatefulWidget {
  const XFeedPage({super.key});

  @override
  State<XFeedPage> createState() => _XFeedPageState();
}

class _XFeedPageState extends State<XFeedPage> {
  final ScrollController _scroll = ScrollController();
  Map<String, XAccount> _profiles = <String, XAccount>{};
  List<XPost> _posts = <XPost>[];
  bool _loading = false;
  bool _started = false;
  String? _error;
  int _loadId = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
      _posts = <XPost>[];
    });
    final app = AppScope.of(context);
    final names = await app.visibleUsernames(from: app.settings.xFollowing);
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
        });
        return;
      }
      final posts = await app.xFollowingService.fetchTodayFeed(
        names,
        onProgress: (items, done, total) {
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
      setState(() => _posts = _withAvatars(posts));
    } catch (error) {
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && id == _loadId) {
        setState(() => _loading = false);
      }
    }
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
    return _buildBody(names.isEmpty);
  }

  Widget _buildBody(bool emptyFollowing) {
    if (!_started) {
      return Center(
        child: PrimaryButton(
          label: '加载帖子',
          icon: Icons.dynamic_feed_outlined,
          onPressed: _load,
        ),
      );
    }
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (emptyFollowing) {
      return const EmptyHint(
        icon: Icons.people_outline,
        title: '还没有关注任何人',
        detail: '打开底部「关注」，添加想看的账号。他们的帖子会出现在这里。',
      );
    }
    if (AppScope.of(context).settings.visibleCategories.isEmpty) {
      return const EmptyHint(
        icon: Icons.tune,
        title: '还没有打开任何分类',
        detail: '到「设置 → 关注分类」打开要看的类别。',
      );
    }
    if (_error != null && _posts.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '动态加载失败',
        detail: '$_error\n请确认 VPN 已开启后再刷新。',
      );
    }
    if (_posts.isEmpty) {
      return EmptyHint(
        icon: Icons.article_outlined,
        title: _loading ? '正在加载今天的帖子' : '今天还没有新帖子',
        detail: _loading
            ? '正在读取当前分类下关注的人。'
            : '当前分类里，关注的人今天还没有发帖。',
      );
    }
    return _PostWaterfall(
      posts: _posts,
      controller: _scroll,
      columns: AppLayout.isCompact(context) ? 2 : 5,
      showAuthor: true,
      loadingMore: _loading,
      hasMore: _loading,
      onDownload: _downloadPost,
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
    return _following.where((name) {
      final account = _profiles[name.toLowerCase()];
      if (account == null) {
        return app.settings.showsCategory('');
      }
      return app.showsAccount(account);
    }).toList();
  }

  String get _accountListEmptyHint {
    if (_following.isEmpty) {
      return '还没有关注';
    }
    if (AppScope.of(context).settings.visibleCategories.isEmpty) {
      return '到设置打开分类';
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
    await app.unfollowXAccount(username);
    if (!mounted) return;
    setState(() {
      _profiles.remove(username.toLowerCase());
      if (_selected?.toLowerCase() == username.toLowerCase()) {
        final names = _visibleFollowing;
        _selected = names.isEmpty ? null : names.first;
        _posts = <XPost>[];
        _postsCursor = null;
        _postsPages = 0;
        _related = <XAccount>[];
        _mobileDetail = false;
      }
    });
    if (_selected != null) {
      await _select(_selected!);
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppLayout.headerPadding(context),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _mobileDetail = false),
                  icon: Icon(Icons.arrow_back_ios_new, size: 18.w),
                ),
                Expanded(
                  child: Text(
                    '@$_selected',
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: AppLayout.pagePadding(context, bottom: 16),
              child: _DetailPane(
                account: _profiles[_selected!.toLowerCase()],
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
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: AppLayout.pagePadding(context, top: 16, bottom: 16).copyWith(left: 16.w, right: 16.w),
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
                    onRemove: _remove,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 260.w,
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
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.fromLTRB(10.w, 12.h, 0, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(right: 10.w),
            child: Stack(
            alignment: Alignment.centerRight,
            children: [
              AppTextField(
                controller: input,
                hint: 'NASA',
                contentPadding: EdgeInsets.fromLTRB(14.w, 12.h, 100.w, 12.h),
                onSubmitted: (_) => onAdd(),
              ),
              Padding(
                padding: EdgeInsets.only(right: 6.w),
                child: PrimaryButton(
                  label: '关注',
                  color: AppColors.x,
                  busy: adding,
                  onPressed: onAdd,
                ),
              ),
            ],
            ),
          ),
          SizedBox(height: 10.h),
          Expanded(
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
                      padding: EdgeInsets.only(right: 2.w),
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
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.w),
                            side: BorderSide(
                              color: isSelected ? AppColors.accent : Colors.transparent,
                              width: 1.4.w,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => onSelect(username),
                            borderRadius: BorderRadius.circular(10.w),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(6.w, 8.h, 2.w, 8.h),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3.w,
                                    height: 32.h,
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.accent : Colors.transparent,
                                      borderRadius: BorderRadius.circular(2.w),
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  SizedBox(
                                    width: 20.w,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: isSelected ? AppColors.accent : AppColors.textMuted,
                                        fontSize: 11.sp,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  _Avatar(url: account?.avatarUrl ?? '', size: 28),
                                  SizedBox(width: 8.w),
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
                                            fontSize: 13.sp,
                                            color: isSelected ? AppColors.text : AppColors.textMuted,
                                          ),
                                        ),
                                        Text(
                                          '@$username',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected ? AppColors.accent : AppColors.textMuted,
                                            fontSize: 11.sp,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '取消关注',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => onRemove(username),
                                    icon: Icon(
                                      Icons.close,
                                      size: 16.w,
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
          ),
        ],
      ),
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
      return const SectionCard(
        child: EmptyHint(
          icon: Icons.people_outline,
          title: '从这里开始',
          detail: '在上方添加 C 用户名，或点推荐账号一键关注。之后可以查看资料，并尝试下载对方帖子中的视频。',
        ),
      );
    }
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
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
          Divider(height: 1.h, color: AppColors.border),
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
                        child: _PostWaterfall(
                          posts: posts,
                          controller: postsScroll,
                          loadingMore: loadingMore,
                          hasMore: hasMore,
                          onDownload: onDownload,
                        ),
                      ),
          ),
        ],
      ),
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
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _FollowingListDialog(
        title: title,
        accounts: accounts,
        loader: loader,
        followed: followed,
        onFollow: onFollow,
        onFollowAll: onFollowAll,
      );
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
  });

  final String title;
  final List<XAccount>? accounts;
  final Future<List<XAccount>> Function()? loader;
  final List<String> followed;
  final ValueChanged<XAccount> onFollow;
  final ValueChanged<List<XAccount>> onFollowAll;

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
      _accounts = existing;
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
        _accounts = accounts;
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = AppLayout.isCompact(context);
    final canFollowAll = !_loading &&
        _accounts.any((account) => !_isFollowed(account.username));
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 20.w : 48.w,
        vertical: compact ? 24.h : 40.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480.w,
          maxHeight: size.height * 0.72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 8.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _loading
                          ? widget.title
                          : '${widget.title} ${_count(_accounts.length)} 人',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: canFollowAll ? _followAll : null,
                    child: Text(
                      '全部关注',
                      style: TextStyle(
                        color: canFollowAll ? AppColors.accent : AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Divider(height: 1.h, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? EmptyHint(
                          icon: Icons.people_outline,
                          title: widget.title,
                          detail: _error!,
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
                          itemCount: _accounts.length,
                          separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border),
                          itemBuilder: (context, index) {
                            final account = _accounts[index];
                            final already = _isFollowed(account.username);
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.h),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28.w,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.sp,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  _Avatar(url: account.avatarUrl, size: 36),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          account.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14.sp,
                                          ),
                                        ),
                                        Text(
                                          '@${account.username}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12.sp,
                                          ),
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
                          },
                        ),
            ),
          ],
        ),
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
              _Avatar(url: account.avatarUrl, size: 56),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
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
              SizedBox(width: 12.w),
              _stats(),
            ],
          ),
          if (account.description.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              account.description.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r' +'), ' ').trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5.sp),
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
        if (onOpenFollowers != null && account.followers > 0)
          _stat(
            value: _count(account.followers),
            label: '关注者',
            onTap: onOpenFollowers,
          )
        else
          _stat(value: _count(account.followers), label: '关注者'),
        _stat(
          value: _count(account.following),
          label: '关注了',
          onTap: onOpenFollowing,
        ),
        _stat(value: _count(account.tweets), label: '帖子'),
      ],
    );
  }

  Widget _stat({
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    final child = SizedBox(
      width: 72.w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.sp,
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
              fontSize: 11.sp,
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
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _AccountHomeDialog(account: account);
    },
  );
  return result == true;
}

class _AccountHomeDialog extends StatefulWidget {
  const _AccountHomeDialog({required this.account});

  final XAccount account;

  @override
  State<_AccountHomeDialog> createState() => _AccountHomeDialogState();
}

class _AccountHomeDialogState extends State<_AccountHomeDialog> {
  static const _maxPostPages = 30;

  final ScrollController _postsScroll = ScrollController();
  List<XPost> _posts = <XPost>[];
  List<XAccount> _related = <XAccount>[];
  String? _postsCursor;
  String? _hint;
  bool _loadingPosts = true;
  bool _loadingMore = false;
  int _pages = 0;
  bool _followed = false;

  bool get _hasMore {
    final cursor = _postsCursor;
    return cursor != null && cursor.isNotEmpty && _pages < _maxPostPages;
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
    final inDb = await app.accountDb.get(username) != null;
    if (mounted) {
      setState(() => _followed = inSettings || inDb);
    }
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

  Future<void> _unfollow() async {
    final app = AppScope.of(context);
    await app.unfollowXAccount(widget.account.username);
    await app.accountDb.delete(widget.account.username);
    if (!mounted) {
      return;
    }
    showAppSnack(context, '已取消关注 @${widget.account.username}');
    Navigator.of(context).pop(true);
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
    final compact = AppLayout.isCompact(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16.w : 48.w,
        vertical: compact ? 20.h : 32.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560.w,
          maxHeight: size.height * 0.86,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  if (_followed)
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
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            _ProfileHeader(
              account: widget.account,
              onOpenFollowers: () => _openFollowers(),
              onOpenFollowing: () => _openFollowing(),
            ),
            Divider(height: 1.h, color: AppColors.border),
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
                          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 20.h),
                          itemCount: _posts.length + (_loadingMore || _hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => SizedBox(height: 10.h),
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
                            return _PostCard(
                              key: ValueKey(_posts[index].id),
                              post: _posts[index],
                              onDownload: _downloadPost,
                              onTap: () => showPostComments(context, _posts[index]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

void showPostSearch(BuildContext context, {String query = ''}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _SearchDialog(initialQuery: query);
    },
  );
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({this.initialQuery = ''});

  final String initialQuery;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchFeed {
  const _SearchFeed(this.id, this.label);

  final String id;
  final String label;
}

class _SearchDialogState extends State<_SearchDialog> {
  static const _feeds = <_SearchFeed>[
    _SearchFeed('latest', '最新'),
    _SearchFeed('top', '热门'),
    _SearchFeed('media', '媒体'),
  ];

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<XPost> _posts = <XPost>[];
  String _feed = 'latest';
  String? _cursor;
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;

  bool get _hasMore {
    final cursor = _cursor;
    return cursor != null && cursor.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _scroll.addListener(_onScroll);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _query.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_hasMore || _loadingMore || _loading) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 160) {
      _search(more: true);
    }
  }

  Future<void> _search({bool more = false}) async {
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() {
        _posts = <XPost>[];
        _cursor = null;
        _error = null;
      });
      return;
    }
    if (more) {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _cursor = null;
      });
    }
    try {
      final page = await AppScope.of(context).xFollowingService.searchPosts(
        q,
        feed: _feed,
        cursor: more ? _cursor : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = more ? <XPost>[..._posts, ...page.posts] : page.posts;
        _cursor = page.cursor;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (!more) {
          _posts = <XPost>[];
        }
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
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
    final compact = AppLayout.isCompact(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16.w : 48.w,
        vertical: compact ? 20.h : 32.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560.w,
          maxHeight: size.height * 0.86,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '搜索',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
              child: AppTextField(
                controller: _query,
                hint: '关键词、#话题 或 @用户',
                prefixIcon: Icons.search,
                onSubmitted: (_) => _search(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
              child: Wrap(
                spacing: 8.w,
                children: [
                  for (final feed in _feeds)
                    Material(
                      color: _feed == feed.id ? AppColors.x : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(999.w),
                      child: InkWell(
                        onTap: () {
                          if (_feed == feed.id) {
                            return;
                          }
                          setState(() => _feed = feed.id);
                          _search();
                        },
                        borderRadius: BorderRadius.circular(999.w),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                          child: Text(
                            feed.label,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w700,
                              color: _feed == feed.id ? Colors.black : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1.h, color: AppColors.border),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _posts.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '搜索失败',
        detail: '$_error',
      );
    }
    if (_query.text.trim().isEmpty) {
      return const EmptyHint(
        icon: Icons.search,
        title: '搜一搜',
        detail: '输入关键词、话题或用户名。热点可以直接点进来搜。',
      );
    }
    if (_posts.isEmpty) {
      return const EmptyHint(
        icon: Icons.article_outlined,
        title: '没有结果',
        detail: '换个关键词，或切到「热门 / 媒体」再试。',
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 20.h),
      itemCount: _posts.length + (_loadingMore || _hasMore ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
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
        return _PostCard(
          key: ValueKey(_posts[index].id),
          post: _posts[index],
          showAuthor: true,
          onDownload: _downloadPost,
          onTap: () => showPostComments(context, _posts[index]),
        );
      },
    );
  }
}

void showPostComments(BuildContext context, XPost post) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _CommentsDialog(post: post);
    },
  );
}

class _CommentsDialog extends StatefulWidget {
  const _CommentsDialog({required this.post});

  final XPost post;

  @override
  State<_CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<_CommentsDialog> {
  static const _maxPages = 30;

  final List<XPost> _replies = <XPost>[];
  final ScrollController _scroll = ScrollController();
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  int _pages = 0;

  bool get _hasMore {
    final cursor = _cursor;
    return cursor != null && cursor.isNotEmpty && _pages < _maxPages;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_hasMore || _loadingMore || _moreError != null) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 120.h) {
      _load(more: true);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() {
        _loadingMore = true;
        _moreError = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _moreError = null;
      });
    }
    try {
      final page = await AppScope.of(context).xFollowingService.fetchReplies(
        widget.post.id,
        cursor: more ? _cursor : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (more) {
          final seen = _replies.map((item) => item.id).toSet();
          final added = page.replies.where((item) => seen.add(item.id)).toList();
          _replies.addAll(added);
          _cursor = added.isEmpty ? null : page.cursor;
        } else {
          _replies
            ..clear()
            ..addAll(page.replies);
          _cursor = page.cursor;
        }
        _pages += 1;
        _error = null;
        _moreError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (more) {
          _moreError = error.toString();
        } else {
          _error = error.toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = AppLayout.isCompact(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16.w : 48.w,
        vertical: compact ? 20.h : 40.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560.w,
          maxHeight: size.height * 0.82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 8.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '评论',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
              child: _RichPostText(
                text: widget.post.displayText.isEmpty
                    ? '@${widget.post.username}'
                    : widget.post.displayText,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp, height: 1.4),
                maxLines: 3,
              ),
            ),
            Divider(height: 1.h, color: AppColors.border),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _replies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _replies.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '评论加载失败',
        detail: '$_error\n请确认 VPN 已开启后再试。',
      );
    }
    if (_replies.isEmpty) {
      return const EmptyHint(
        icon: Icons.chat_bubble_outline,
        title: '还没有评论',
        detail: '这条帖子暂时没有可展示的评论。',
      );
    }
    final showFooter = _hasMore || _loadingMore || _moreError != null;
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 20.h),
      itemCount: _replies.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder: (context, index) {
        if (index >= _replies.length) {
          return _buildFooter();
        }
        final reply = _replies[index];
        return Container(
          padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12.w),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '@${reply.username}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.sp),
                    ),
                  ),
                  if (reply.publishedAt != null)
                    Text(
                      _time(reply.publishedAt!),
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.sp),
                    ),
                ],
              ),
              if (reply.displayText.isNotEmpty) ...[
                SizedBox(height: 6.h),
                _RichPostText(
                  text: reply.displayText,
                  style: TextStyle(height: 1.45, fontSize: 13.sp),
                  selectable: true,
                ),
                if (reply.hasTranslation) ...[
                  SizedBox(height: 4.h),
                  _RichPostText(
                    text: reply.text,
                    style: TextStyle(
                      height: 1.4,
                      fontSize: 12.sp,
                      color: AppColors.textMuted,
                    ),
                    selectable: true,
                  ),
                ],
              ],
              if (reply.media.isNotEmpty) ...[
                SizedBox(height: 8.h),
                _PostMediaGrid(media: reply.media),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Center(
          child: SizedBox(
            width: 20.w,
            height: 20.w,
            child: CircularProgressIndicator(strokeWidth: 2.w),
          ),
        ),
      );
    }
    if (_moreError != null) {
      return Center(
        child: GhostButton(
          label: '重试',
          icon: Icons.refresh,
          onPressed: () => _load(more: true),
        ),
      );
    }
    if (!_hasMore) {
      return const SizedBox.shrink();
    }
    return Center(
      child: GhostButton(
        label: '加载更多',
        icon: Icons.expand_more,
        onPressed: () => _load(more: true),
      ),
    );
  }
}

class _PostWaterfall extends StatelessWidget {
  const _PostWaterfall({
    required this.posts,
    required this.controller,
    required this.loadingMore,
    required this.hasMore,
    required this.onDownload,
    this.columns = 3,
    this.showAuthor = false,
  });

  final int columns;
  final bool showAuthor;
  final List<XPost> posts;
  final ScrollController controller;
  final bool loadingMore;
  final bool hasMore;
  final ValueChanged<XPost> onDownload;

  @override
  Widget build(BuildContext context) {
    final count = columns < 1 ? 1 : columns;
    final buckets = List<List<XPost>>.generate(count, (_) => <XPost>[]);
    for (var i = 0; i < posts.length; i++) {
      buckets[i % count].add(posts[i]);
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < count; c++) ...[
                  if (c > 0) SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      children: [
                        for (final post in buckets[c])
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: _PostCard(
                              key: ValueKey(post.id),
                              post: post,
                              dense: true,
                              showAuthor: showAuthor,
                              onDownload: onDownload,
                              onTap: () => showPostComments(context, post),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (loadingMore || hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 4.h, 0, 20.h),
              child: Center(
                child: loadingMore
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: CircularProgressIndicator(strokeWidth: 2.w),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}

class _PostCard extends StatefulWidget {
  const _PostCard({
    super.key,
    required this.post,
    required this.onDownload,
    this.onOpen,
    this.onComments,
    this.onTap,
    this.showAuthor = false,
    this.dense = false,
  });

  final XPost post;
  final ValueChanged<XPost> onDownload;
  final ValueChanged<String>? onOpen;
  final VoidCallback? onComments;
  final VoidCallback? onTap;
  final bool showAuthor;
  final bool dense;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  Timer? _hoverTimer;
  Timer? _exitTimer;
  String _translation = '';
  bool _translating = false;
  bool _pointerInside = false;

  XPost get post => widget.post;
  bool get dense => widget.dense;

  String get _shownTranslation {
    final hovered = _translation.trim();
    if (hovered.isNotEmpty) {
      return hovered;
    }
    return post.translation.trim();
  }

  bool get _hasTranslation {
    final translated = _shownTranslation;
    return translated.isNotEmpty && translated != post.text.trim();
  }

  String get _mainText {
    return _hasTranslation ? _shownTranslation : post.displayText;
  }

  @override
  void initState() {
    super.initState();
    _translation = post.translation;
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != post.id) {
      _hoverTimer?.cancel();
      _exitTimer?.cancel();
      _hoverTimer = null;
      _exitTimer = null;
      _translating = false;
      _translation = post.translation;
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    _pointerInside = true;
    _exitTimer?.cancel();
    _exitTimer = null;
    _armHoverTranslate();
  }

  void _onExit(PointerEvent _) {
    _pointerInside = false;
    _exitTimer?.cancel();
    // 卡片高度变化时 Flutter 会误触发 onExit；稍等一下，还在上面就不要取消。
    _exitTimer = Timer(const Duration(milliseconds: 160), () {
      if (_pointerInside) {
        return;
      }
      _hoverTimer?.cancel();
      _hoverTimer = null;
    });
  }

  void _armHoverTranslate() {
    if (post.text.trim().isEmpty || post.isChinese || _hasTranslation || _translating) {
      return;
    }
    final cached = XFollowingService.cachedTranslation(post.id);
    if (cached != null) {
      setState(() => _translation = cached);
      return;
    }
    if (_hoverTimer?.isActive ?? false) {
      return;
    }
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(seconds: 2), _translate);
  }

  Future<void> _translate() async {
    if (!mounted || post.isChinese || _hasTranslation || _translating) {
      return;
    }
    _translating = true;
    try {
      final text = await AppScope.of(context).xFollowingService.fetchPostTranslation(post.id);
      if (!mounted || post.id != widget.post.id) {
        return;
      }
      setState(() {
        _translation = text;
        _translating = false;
      });
    } catch (_) {
      if (mounted) {
        _translating = false;
      }
    }
  }

  Widget _bodyText(String value, {bool muted = false, int? maxLines}) {
    final style = TextStyle(
      height: 1.45,
      fontSize: muted ? (dense ? 11.sp : 12.sp) : (dense ? 12.sp : 14.sp),
      color: muted ? AppColors.textMuted : null,
    );
    return _RichPostText(
      text: value,
      style: style,
      maxLines: maxLines,
      selectable: widget.onTap == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: dense
          ? EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 8.h)
          : EdgeInsets.fromLTRB(14.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12.w),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showAuthor)
            GestureDetector(
              onTap: () => _openMention(context, post.username),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  _Avatar(url: post.avatarUrl, size: dense ? 22 : 32),
                  SizedBox(width: dense ? 6.w : 8.w),
                  Expanded(
                    child: Text(
                      post.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: dense ? 11.sp : 13.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_mainText.isNotEmpty) ...[
            if (widget.showAuthor) SizedBox(height: dense ? 4.h : 6.h),
            _bodyText(_mainText, maxLines: dense ? 8 : null),
            if (_hasTranslation) ...[
              SizedBox(height: dense ? 4.h : 6.h),
              _bodyText(post.text, muted: true, maxLines: dense ? 4 : null),
            ],
          ],
          if (post.media.isNotEmpty) ...[
            SizedBox(height: dense ? 6.h : 10.h),
            _PostMediaGrid(media: post.media, dense: dense),
          ],
          if (!dense && (widget.onOpen != null || widget.onComments != null)) ...[
            SizedBox(height: 10.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                if (widget.onComments != null)
                  GhostButton(
                    label: '评论',
                    icon: Icons.chat_bubble_outline,
                    onPressed: widget.onComments,
                  ),
                if (widget.onOpen != null)
                  GhostButton(
                    label: '打开',
                    icon: Icons.open_in_browser,
                    onPressed: () => widget.onOpen!(post.url),
                  ),
              ],
            ),
          ],
          if (post.publishedAt != null) ...[
            SizedBox(height: dense ? 6.h : 8.h),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _time(post.publishedAt!),
                style: TextStyle(color: AppColors.textMuted, fontSize: dense ? 10.sp : 11.sp),
              ),
            ),
          ],
        ],
      ),
    );
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: _onEnter,
      onExit: _onExit,
      child: widget.onTap == null
          ? card
          : GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.translucent,
              child: card,
            ),
    );
  }
}

class _RichPostText extends StatefulWidget {
  const _RichPostText({
    required this.text,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  State<_RichPostText> createState() => _RichPostTextState();
}

class _RichPostTextState extends State<_RichPostText> {
  static final _token = RegExp(
    r'@[A-Za-z0-9_]{1,15}|#[^\s#@]+',
    unicode: true,
  );
  static final _trailing = RegExp(
    r'''[.,!?;:'")\]}，。！？、；：）】》」』]+$''',
  );

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  TextSpan? _spanCache;
  String _cachedText = '';

  @override
  void didUpdateWidget(covariant _RichPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style.color != widget.style.color ||
        oldWidget.style.fontSize != widget.style.fontSize) {
      _spanCache = null;
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final item in _recognizers) {
      item.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextSpan _span() {
    _clearRecognizers();
    final base = widget.style;
    final link = base.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
    );
    final children = <InlineSpan>[];
    final text = widget.text;
    var start = 0;
    for (final match in _token.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(text: text.substring(start, match.start)));
      }
      var token = match.group(0) ?? '';
      var extra = '';
      if (token.startsWith('#')) {
        final cleaned = token.replaceFirst(_trailing, '');
        extra = token.substring(cleaned.length);
        token = cleaned;
      }
      if (token.length > 1) {
        final value = token;
        children.add(
          TextSpan(
            text: value,
            style: link,
            mouseCursor: SystemMouseCursors.click,
            recognizer: _tap(() {
              if (!mounted) {
                return;
              }
              if (value.startsWith('@')) {
                _openMention(context, value);
              } else {
                showPostSearch(context, query: value);
              }
            }),
          ),
        );
      } else {
        extra = '$token$extra';
      }
      if (extra.isNotEmpty) {
        children.add(TextSpan(text: extra));
      }
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    if (_spanCache == null || _cachedText != widget.text) {
      _spanCache = _span();
      _cachedText = widget.text;
    }
    final span = _spanCache!;
    if (widget.selectable) {
      return SelectableText.rich(span, maxLines: widget.maxLines);
    }
    return Text.rich(
      span,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

Future<void> _openMention(BuildContext context, String raw) async {
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
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    showAppSnack(context, '无法打开 @$username', error: true);
  }
}

class _PostMediaGrid extends StatelessWidget {
  const _PostMediaGrid({required this.media, this.dense = false});

  final List<XMedia> media;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (dense) {
      final item = media.first;
      var ratio = 0.85;
      if (item.width > 0 && item.height > 0) {
        ratio = item.width / item.height;
        if (ratio < 0.55) {
          ratio = 0.55;
        } else if (ratio > 1.4) {
          ratio = 1.4;
        }
      }
      return AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MediaThumb(item: item, media: media, index: 0),
            if (media.length > 1)
              Positioned(
                right: 6.w,
                top: 6.h,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(6.w),
                  ),
                  child: Text(
                    '+${media.length - 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 6.w;
        final items = media.take(4).toList();
        final width = items.length == 1 ? constraints.maxWidth : (constraints.maxWidth - gap) / 2;
        final height = items.length == 1 ? 220.h : 128.h;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                height: height,
                child: _MediaThumb(
                  item: items[i],
                  media: media,
                  index: i,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.item,
    required this.media,
    required this.index,
  });

  final XMedia item;
  final List<XMedia> media;
  final int index;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.previewUrl.isNotEmpty ? item.previewUrl : item.url;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showPostMedia(context, media, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.w),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.surface,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                  ),
                ),
              ),
              if (item.isVideo) ...[
                const ColoredBox(color: Color(0x33000000)),
                Center(
                  child: Icon(
                    item.kind == XMediaKind.gif ? Icons.gif_box_outlined : Icons.play_circle_fill,
                    size: 36.w,
                    color: Colors.white,
                  ),
                ),
                if (item.durationLabel.isNotEmpty)
                  Positioned(
                    right: 8.w,
                    bottom: 8.h,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(6.w),
                      ),
                      child: Text(
                        item.durationLabel,
                        style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final side = size.w;
    return ClipOval(
      child: ColoredBox(
        color: AppColors.surfaceAlt,
        child: url.isEmpty
            ? SizedBox(
                width: side,
                height: side,
                child: Icon(Icons.person, size: (size * 0.57).w, color: AppColors.textMuted),
              )
            : Image.network(
                url,
                width: side,
                height: side,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: side,
                  height: side,
                  child: Icon(Icons.person, size: (size * 0.57).w, color: AppColors.textMuted),
                ),
              ),
      ),
    );
  }
}

String _count(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}

String _time(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
