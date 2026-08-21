import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/x_feed_widgets.dart';

import 'x_following_page.dart';

class XSearchPage extends StatefulWidget {
  const XSearchPage({
    super.key,
    this.initialQuery = '',
    this.dialog = false,
  });

  final String initialQuery;
  final bool dialog;

  @override
  State<XSearchPage> createState() => _XSearchPageState();
}

class _SearchFeed {
  const _SearchFeed(this.id, this.label);

  final String id;
  final String label;
}

class _XSearchPageState extends State<XSearchPage> {
  static const _kinds = <_SearchFeed>[
    _SearchFeed('posts', '帖子'),
    _SearchFeed('users', '成员'),
  ];
  static const _feeds = <_SearchFeed>[
    _SearchFeed('latest', '最新'),
    _SearchFeed('top', '热门'),
    _SearchFeed('media', '媒体'),
  ];

  final TextEditingController _query = TextEditingController();
  final ScrollController _postsScroll = ScrollController();
  final ScrollController _usersScroll = ScrollController();
  List<XPost> _posts = <XPost>[];
  List<XAccount> _users = <XAccount>[];
  String _kind = 'posts';
  String _feed = 'latest';
  String _postsDraft = '';
  String _usersDraft = '';
  String? _postsCursor;
  String? _usersCursor;
  String? _postsError;
  String? _usersError;
  bool _postsLoading = false;
  bool _postsLoadingMore = false;
  bool _usersLoading = false;
  bool _usersLoadingMore = false;
  bool _postsSearched = false;
  bool _usersSearched = false;
  bool _assigning = false;
  String? _targetCategory;

  bool get _searchUsers => _kind == 'users';

  List<String> get _categoryOptions {
    final keys = <String>{};
    for (final item in AppScope.of(context).settings.categories) {
      final key = item.trim().toLowerCase();
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    final selected = _targetCategory?.trim().toLowerCase() ?? '';
    if (selected.isNotEmpty) {
      keys.add(selected);
    }
    final list = keys.toList()..sort();
    return list;
  }

  String? get _effectiveCategory {
    final selected = _targetCategory?.trim().toLowerCase() ?? '';
    if (selected.isNotEmpty) {
      return selected;
    }
    final follow = AppScope.of(context).followCategory.trim().toLowerCase();
    if (follow.isNotEmpty) {
      return follow;
    }
    final options = _categoryOptions;
    return options.isEmpty ? null : options.first;
  }

  bool get _hasMorePosts {
    final cursor = _postsCursor;
    return cursor != null && cursor.isNotEmpty;
  }

  bool get _hasMoreUsers {
    final cursor = _usersCursor;
    return cursor != null && cursor.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _postsDraft = widget.initialQuery;
    _postsScroll.addListener(_onPostsScroll);
    _usersScroll.addListener(_onUsersScroll);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _postsScroll
      ..removeListener(_onPostsScroll)
      ..dispose();
    _usersScroll
      ..removeListener(_onUsersScroll)
      ..dispose();
    _query.dispose();
    super.dispose();
  }

  void _onPostsScroll() {
    if (!_postsScroll.hasClients ||
        !_hasMorePosts ||
        _postsLoadingMore ||
        _postsLoading) {
      return;
    }
    if (_postsScroll.position.pixels >= _postsScroll.position.maxScrollExtent - 160) {
      _search(more: true);
    }
  }

  void _onUsersScroll() {
    if (!_usersScroll.hasClients ||
        !_hasMoreUsers ||
        _usersLoadingMore ||
        _usersLoading) {
      return;
    }
    if (_usersScroll.position.pixels >= _usersScroll.position.maxScrollExtent - 160) {
      _search(more: true);
    }
  }

  void _switchKind(String kind) {
    if (_kind == kind) {
      return;
    }
    setState(() {
      if (_searchUsers) {
        _usersDraft = _query.text;
      } else {
        _postsDraft = _query.text;
      }
      _kind = kind;
      _query.text = kind == 'users' ? _usersDraft : _postsDraft;
      _query.selection = TextSelection.collapsed(offset: _query.text.length);
    });
  }

  Future<void> _search({bool more = false}) async {
    final q = _query.text.trim();
    final users = _searchUsers;
    if (q.isEmpty) {
      setState(() {
        if (users) {
          _users = <XAccount>[];
          _usersCursor = null;
          _usersError = null;
          _usersSearched = false;
          _usersDraft = '';
        } else {
          _posts = <XPost>[];
          _postsCursor = null;
          _postsError = null;
          _postsSearched = false;
          _postsDraft = '';
        }
      });
      return;
    }
    if (more) {
      if (users) {
        if (_usersLoadingMore || !_hasMoreUsers) {
          return;
        }
        setState(() => _usersLoadingMore = true);
      } else {
        if (_postsLoadingMore || !_hasMorePosts) {
          return;
        }
        setState(() => _postsLoadingMore = true);
      }
    } else if (users) {
      setState(() {
        _usersLoading = true;
        _usersError = null;
        _usersCursor = null;
        _usersDraft = _query.text;
      });
    } else {
      setState(() {
        _postsLoading = true;
        _postsError = null;
        _postsCursor = null;
        _postsDraft = _query.text;
      });
    }
    try {
      final service = AppScope.of(context).xFollowingService;
      if (users) {
        final page = await service.searchUsers(
          q,
          cursor: more ? _usersCursor : null,
          exclude: more
              ? _users.map((account) => account.username).toSet()
              : const <String>{},
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _users = more ? <XAccount>[..._users, ...page.accounts] : page.accounts;
          _usersCursor = page.cursor;
          _usersSearched = true;
        });
        return;
      }
      final page = await service.searchPosts(
        q,
        feed: _feed,
        cursor: more ? _postsCursor : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = more ? <XPost>[..._posts, ...page.posts] : page.posts;
        _postsCursor = page.cursor;
        _postsSearched = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (users) {
          if (!more) {
            _users = <XAccount>[];
            _usersCursor = null;
          }
          _usersError = error.toString();
          _usersSearched = true;
        } else {
          if (!more) {
            _posts = <XPost>[];
          }
          _postsError = error.toString();
          _postsSearched = true;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _postsLoading = false;
          _postsLoadingMore = false;
          _usersLoading = false;
          _usersLoadingMore = false;
        });
      }
    }
  }

  Future<void> _followUser(XAccount account) async {
    final app = AppScope.of(context);
    try {
      final saved = await app.followAndSave(
        account,
        category: _effectiveCategory,
      );
      if (!mounted) {
        return;
      }
      showAppSnack(
        context,
        '已关注 @${saved.username}，已加入「${XAccount.categoryLabel(saved.category)}」',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    }
  }

  Future<void> _promptNewCategory() async {
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
    setState(() => _targetCategory = key);
  }

  Future<void> _addUsersToCategory() async {
    if (_assigning || _users.isEmpty) {
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
    setState(() => _assigning = true);
    try {
      final result = await AppScope.of(context).addAccountsToCategory(
        _users,
        category: category,
      );
      if (!mounted) {
        return;
      }
      final label = XAccount.categoryLabel(result.category);
      if (result.total == 0) {
        showAppSnack(context, '没有可加入的成员');
        return;
      }
      if (result.followed == 0) {
        showAppSnack(context, '已将 ${result.updated} 人归入「$label」');
        return;
      }
      if (result.updated == 0) {
        showAppSnack(context, '已关注 ${result.followed} 人，已加入「$label」');
        return;
      }
      showAppSnack(
        context,
        '已将 ${result.total} 人加入「$label」（新增关注 ${result.followed}）',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _assigning = false);
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
    final phone = AppLayout.isCompact(context);
    final busy = _searchUsers ? _usersLoading : _postsLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone)
          PhoneNavBar(
            height: 56,
            onBack: () => Navigator.of(context).pop(),
            titleWidget: AppTextField(
              controller: _query,
              hint: _searchUsers ? '名字或 @用户名' : '关键词、#话题 或 @用户',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              onSubmitted: (_) => _search(),
            ),
            trailing: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
              child: SizedBox(
                height: 40.h,
                child: PrimaryButton(
                  label: '搜索',
                  compact: true,
                  expand: true,
                  busy: busy,
                  onPressed: () => _search(),
                ),
              ),
            ),
          )
        else if (widget.dialog)
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
          )
        else
          const SizedBox.shrink(),
        Padding(
          padding: _searchInset(top: phone ? 8 : (widget.dialog ? 0 : 16), bottom: 8),
          child: phone
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _filterChips(),
                )
              : _searchBar(),
        ),
        if (phone || widget.dialog) Divider(height: 1.h, color: AppColors.border),
        Expanded(
          child: IndexedStack(
            index: _searchUsers ? 1 : 0,
            children: [
              _buildPostsPane(),
              _buildUsers(),
            ],
          ),
        ),
      ],
    );
  }

  EdgeInsets _searchInset({double top = 0, double bottom = 8}) {
    return EdgeInsets.fromLTRB(12.w, top.h, 12.w, bottom.h);
  }

  Widget _searchBar() {
    const actionHeight = 28.0;
    final busy = _searchUsers ? _usersLoading : _postsLoading;
    return Row(
      children: [
        Expanded(
          child: InlineActionField(
            controller: _query,
            hint: _searchUsers ? '名字或 @用户名' : '关键词、#话题 或 @用户',
            actionLabel: '搜索',
            busy: busy,
            onAction: () => _search(),
          ),
        ),
        SizedBox(width: 8.w),
        _filterChips(height: actionHeight),
      ],
    );
  }

  Widget _filterChips({double height = 28}) {
    return Row(
      children: [
        for (final kind in _kinds) ...[
          _chip(
            label: kind.label,
            selected: _kind == kind.id,
            height: height,
            onTap: () => _switchKind(kind.id),
          ),
          SizedBox(width: 6.w),
        ],
        if (!_searchUsers)
          for (final feed in _feeds) ...[
            _chip(
              label: feed.label,
              selected: _feed == feed.id,
              height: height,
              onTap: () {
                if (_feed == feed.id) {
                  return;
                }
                setState(() => _feed = feed.id);
                _search();
              },
            ),
            SizedBox(width: 6.w),
          ],
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required double height,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.x : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height.h,
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

  Widget _buildPostsPane() {
    if (_postsLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_postsError != null && _posts.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '搜索失败',
        detail: '$_postsError',
      );
    }
    if (_posts.isEmpty) {
      return EmptyHint(
        icon: Icons.search,
        title: _postsSearched ? '没有结果' : '搜一搜',
        detail: _postsSearched
            ? '换个关键词，或切到「热门 / 媒体」再试。'
            : '输入关键词、话题或用户名，查找帖子。',
      );
    }
    final compact = AppLayout.isCompact(context);
    return PostWaterfall(
      posts: _posts,
      controller: _postsScroll,
      columns: widget.dialog || compact ? 2 : 3,
      showAuthor: true,
      textSize: 14.sp,
      loadingMore: _postsLoadingMore,
      hasMore: _hasMorePosts,
      onDownload: _downloadPost,
      padding: _searchInset(top: 12, bottom: 8),
    );
  }

  Widget _buildUsers() {
    if (_usersLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_usersError != null && _users.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '搜索失败',
        detail: '$_usersError',
      );
    }
    if (_users.isEmpty) {
      return EmptyHint(
        icon: Icons.people_outline,
        title: _usersSearched ? '没有结果' : '搜一搜',
        detail: _usersSearched ? '换个名字或用户名再试。' : '输入名字或用户名，查找成员。',
      );
    }
    final followed = AppScope.of(context)
        .settings
        .xFollowing
        .map((name) => name.toLowerCase())
        .toSet();
    final padding = _searchInset(top: 8, bottom: 8);
    final footer = _usersLoadingMore || _hasMoreUsers;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _usersScroll,
            padding: padding,
            itemCount: _users.length + (footer ? 1 : 0),
            separatorBuilder: (context, index) {
              if (index >= _users.length - 1) {
                return const SizedBox.shrink();
              }
              return Divider(height: 1.h, color: AppColors.border);
            },
            itemBuilder: (context, index) {
              if (index >= _users.length) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(0, 12.h, 0, 8.h),
                  child: Center(
                    child: _usersLoadingMore
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: CircularProgressIndicator(strokeWidth: 2.w),
                          )
                        : GhostButton(
                            label: '加载更多',
                            icon: Icons.expand_more,
                            onPressed: () => _search(more: true),
                          ),
                  ),
                );
              }
              final account = _users[index];
              final already = followed.contains(account.username.toLowerCase());
              return InkWell(
                onTap: () => showAccountHome(context, account),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  child: Row(
                    children: [
                      XAvatar(url: account.avatarUrl, size: 44),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.name.trim().isEmpty
                                  ? account.username
                                  : account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
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
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.sp,
                              ),
                            )
                          : TextButton(
                              onPressed: () => _followUser(account),
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
                ),
              );
            },
          ),
        ),
        _buildCategoryBar(),
      ],
    );
  }

  Widget _buildCategoryBar() {
    final selected = _effectiveCategory;
    final options = _categoryOptions;
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, widget.dialog ? 12.h : 10.h),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
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
                      height: 28,
                      onTap: () {
                        setState(() => _targetCategory = key);
                      },
                    ),
                    SizedBox(width: 6.w),
                  ],
                  _chip(
                    label: '+ 新增',
                    selected: false,
                    height: 28,
                    onTap: _promptNewCategory,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          PrimaryButton(
            label: '加入 ${_users.length} 人',
            icon: Icons.playlist_add,
            compact: true,
            busy: _assigning,
            onPressed: _assigning ? null : _addUsersToCategory,
          ),
        ],
      ),
    );
  }
}


void showPostSearch(BuildContext context, {String query = ''}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppLayout.isCompact(dialogContext) ? 16.w : 48.w,
          vertical: AppLayout.isCompact(dialogContext) ? 20.h : 32.h,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 880.w,
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
          ),
          child: XSearchPage(initialQuery: query, dialog: true),
        ),
      );
    },
  );
}
