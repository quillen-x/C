import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/media_viewer.dart';
import 'x_following_page.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final ScrollController _scroll = ScrollController();
  List<_FollowedVideo> _videos = <_FollowedVideo>[];
  Map<String, String> _cursors = <String, String>{};
  bool _loading = false;
  bool _loadingMore = false;
  bool _started = false;
  bool _autoLoadScheduled = false;
  bool _noSpecial = false;
  String? _error;

  bool get _hasMore => _cursors.isNotEmpty;

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

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    final compact = AppLayout.isCompact(context);
    final app = AppScope.of(context);
    setState(() {
      _started = true;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _noSpecial = false;
      if (!compact || _videos.isEmpty) {
        _videos = <_FollowedVideo>[];
        _cursors = <String, String>{};
      }
    });
    try {
      final accounts = await app.visibleAccounts(
        specialOnly: true,
        mediaPage: AppPage.x,
      );
      final names = accounts.map((account) => account.username).toList();
      if (names.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _videos = <_FollowedVideo>[];
          _cursors = <String, String>{};
          _error = null;
          _noSpecial = true;
        });
        return;
      }
      final batch = await app.xFollowingService.fetchVideoFeed(names);
      if (!mounted) {
        return;
      }
      setState(() {
        _videos = _flatten(batch.posts);
        _cursors = compact ? batch.cursors : <String, String>{};
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        if (_videos.isEmpty) {
          _cursors = <String, String>{};
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (!AppLayout.isCompact(context) || _loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    final app = AppScope.of(context);
    try {
      final accounts = await app.visibleAccounts(
        specialOnly: true,
        mediaPage: AppPage.x,
      );
      final names = accounts.map((account) => account.username).toList();
      final batch = await app.xFollowingService.fetchVideoFeed(
        names,
        cursors: _cursors,
      );
      if (!mounted) {
        return;
      }
      final seen = _videos.map((item) => '${item.post.id}:${item.index}').toSet();
      final extra = _flatten(batch.posts)
          .where((item) => seen.add('${item.post.id}:${item.index}'));
      setState(() {
        _videos = <_FollowedVideo>[..._videos, ...extra];
        _cursors = batch.cursors;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  List<_FollowedVideo> _flatten(List<XPost> posts) {
    final videos = <_FollowedVideo>[];
    for (final post in posts) {
      for (var index = 0; index < post.media.length; index++) {
        final media = post.media[index];
        if (media.isVideo) {
          videos.add(_FollowedVideo(post: post, media: media, index: index));
        }
      }
    }
    return videos;
  }

  Future<void> _openProfile(String username) async {
    final app = AppScope.of(context);
    XAccount? account = await app.accountDb.get(username);
    if (account == null) {
      try {
        account = await app.xFollowingService.fetchAccount(username);
      } catch (_) {
        account = XAccount(
          username: username,
          name: username,
          description: '',
          avatarUrl: '',
          profileUrl: 'https://x.com/$username',
          followers: 0,
          following: 0,
          tweets: 0,
        );
      }
    }
    if (!mounted) {
      return;
    }
    final removed = await showAccountHome(context, account);
    if (!removed || !mounted) {
      return;
    }
    setState(() {
      _videos.removeWhere(
        (item) => item.post.username.toLowerCase() == username.toLowerCase(),
      );
    });
  }

  Future<void> _download(_FollowedVideo item) async {
    final app = AppScope.of(context);
    showAppSnack(context, '已加入下载：${item.post.text}');
    final task = await app.downloadVideo(
      url: item.post.url,
      title: item.post.text,
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

  int _columns(BuildContext context) {
    if (AppLayout.isCompact(context)) {
      return 2;
    }
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBody(),
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

  Widget _buildBody() {
    final compact = AppLayout.isCompact(context);
    if (!_started || (_loading && _videos.isEmpty)) {
      if (compact) {
        return const Center(child: CircularProgressIndicator());
      }
      return const SizedBox.expand();
    }
    if (_error != null && _videos.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.wifi_off_rounded,
          title: '视频加载失败',
          detail: '$_error\n请确认 VPN 已开启后再下拉刷新。',
        ),
      );
    }
    if (_videos.isEmpty) {
      final noCategory = AppScope.of(context).settings.visibleCategories.isEmpty;
      if (noCategory) {
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
            detail: '当前分类里没有特别关注的账号。到「关注」里给想看的人点特别关注，这里只会加载这些人的视频。',
          ),
        );
      }
      return _wrapPhone(
        empty: true,
        const EmptyHint(
          icon: Icons.smart_display_outlined,
          title: '暂时没有视频',
          detail: '这里只显示已打开分类里特别关注的账号视频。',
        ),
      );
    }
    final columns = _columns(context);
    return _wrapPhone(
      empty: false,
      CustomScrollView(
        controller: _scroll,
        physics: compact ? const AlwaysScrollableScrollPhysics() : null,
        slivers: [
          SliverPadding(
            padding: AppLayout.mediaHubPadding(context),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10.h,
                crossAxisSpacing: 10.w,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _VideoTile(
                    item: _videos[index],
                    onDownload: () => _download(_videos[index]),
                    onOpenProfile: () => _openProfile(_videos[index].post.username),
                  );
                },
                childCount: _videos.length,
              ),
            ),
          ),
          if (_loadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 4.h, 0, 16.h),
                child: Center(
                  child: SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(strokeWidth: 2.w),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowedVideo {
  const _FollowedVideo({
    required this.post,
    required this.media,
    required this.index,
  });

  final XPost post;
  final XMedia media;
  final int index;
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.item,
    required this.onDownload,
    required this.onOpenProfile,
  });

  final _FollowedVideo item;
  final VoidCallback onDownload;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.media.listUrl;
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12.w),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: InkWell(
              onTap: () => showPostMedia(
                context,
                item.post.media,
                item.index,
                username: item.post.username,
                displayName: item.post.displayName,
                text: item.post.displayText,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.surface,
                    child: imageUrl.isEmpty
                        ? Icon(Icons.movie_outlined, size: 36.w, color: AppColors.textMuted)
                        : AppNetworkImage(
                            url: imageUrl,
                            fit: BoxFit.cover,
                            error: Center(
                              child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32.w),
                            ),
                          ),
                  ),
                  const ColoredBox(color: Color(0x33000000)),
                  Center(
                    child: Icon(
                      item.media.kind == XMediaKind.gif
                          ? Icons.gif_box_outlined
                          : Icons.play_circle_fill,
                      size: 42.w,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8.h,
            right: 8.w,
            child: Material(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(999.w),
              child: InkWell(
                onTap: onDownload,
                borderRadius: BorderRadius.circular(999.w),
                child: Padding(
                  padding: EdgeInsets.all(6.w),
                  child: Icon(Icons.download_rounded, size: 16.w, color: Colors.white),
                ),
              ),
            ),
          ),
          if (item.media.durationLabel.isNotEmpty || item.media.kind == XMediaKind.gif)
            Positioned(
              right: 8.w,
              bottom: 36.h,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child: Text(
                  item.media.kind == XMediaKind.gif && item.media.durationLabel.isEmpty
                      ? 'GIF'
                      : item.media.durationLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xCC000000)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(10.w, 18.h, 10.w, 10.h),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onOpenProfile,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      item.post.displayName.isEmpty
                          ? '@${item.post.username}'
                          : item.post.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
