import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../app_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/media_viewer.dart';
import '../widgets/x_feed_widgets.dart';
import 'x_following_page.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final ScrollController _scroll = ScrollController();
  List<_FollowedVideo> _videos = <_FollowedVideo>[];
  bool _loading = false;
  bool _started = false;
  bool _autoLoadScheduled = false;
  bool _noSpecial = false;
  bool _downloadingPopular = false;
  String? _error;
  String _loadedCategoryKey = '';
  int _loadId = 0;

  static const _batchDownloadCount = 5;
  static const _batchLikesMin = 100;

  String _categoryWatchKey(AppController app) {
    return app.settings.visibleCategories.join('|');
  }

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
    final id = ++_loadId;
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
      _noSpecial = false;
      if (!compact || _videos.isEmpty) {
        _videos = <_FollowedVideo>[];
      }
    });
    try {
      final accounts = await app.visibleAccounts(
        specialOnly: true,
        mediaPage: AppPage.x,
      );
      final accountMap = await app.accountDb.loadMap();
      final names = accounts.map((account) => account.username).toList();
      if (names.isEmpty) {
        if (!mounted || id != _loadId) {
          return;
        }
        setState(() {
          _videos = <_FollowedVideo>[];
          _error = null;
          _noSpecial = true;
        });
        return;
      }
      final batch = await app.xFollowingService.fetchVideoFeed(
        names,
        onProgress: (items, done, total) {
          if (!mounted || id != _loadId) {
            return;
          }
          setState(() {
            _videos = _flatten(items, accountMap: accountMap);
            _loadedCategoryKey = _categoryWatchKey(app);
          });
        },
      );
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() {
        _videos = _flatten(batch.posts, accountMap: accountMap);
        _loadedCategoryKey = _categoryWatchKey(app);
      });
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

  List<_FollowedVideo> _flatten(
    List<XPost> posts, {
    required Map<String, XAccount> accountMap,
  }) {
    final app = AppScope.of(context);
    final videos = <_FollowedVideo>[];
    for (final post in posts) {
      final account = accountMap[post.username.toLowerCase()];
      for (var index = 0; index < post.media.length; index++) {
        final media = post.media[index];
        if (!app.allowsVideoTabMedia(account, media)) {
          continue;
        }
        videos.add(_FollowedVideo(post: post, media: media, index: index));
      }
    }
    videos.sort((a, b) => b.post.likes.compareTo(a.post.likes));
    final load = app.settings.videoLoad;
    final counts = <String, int>{};
    return videos.where((item) {
      if (!load.allowsLikes(item.post.likes)) {
        return false;
      }
      final key = item.post.username.toLowerCase();
      final n = counts[key] ?? 0;
      if (n >= load.perUser) {
        return false;
      }
      counts[key] = n + 1;
      return true;
    }).toList();
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
    final url = item.post.url.trim();
    if (app.isInDownloadList(url)) {
      showAppSnack(context, '已经在下载列表中');
      return;
    }
    showQuickSnack(context, '已加入下载：${item.post.text}');
    unawaited(
      app
          .downloadVideo(
            url: url,
            title: item.post.text,
            quality: VideoQuality.best,
          )
          .then((task) {
            if (!mounted || !task.alreadyDownloaded) {
              return;
            }
            showAppSnack(context, '已经在下载列表中');
          }),
    );
  }

  String _postKey(_FollowedVideo item) {
    final id = item.post.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return item.post.url.trim();
  }

  Future<void> _downloadPopular() async {
    if (_downloadingPopular) {
      return;
    }
    final app = AppScope.of(context);
    final seen = <String>{};
    final batch = <_FollowedVideo>[];
    for (final item in _videos) {
      final key = _postKey(item);
      final url = item.post.url.trim();
      if (item.post.likes <= _batchLikesMin) {
        continue;
      }
      if (key.isEmpty || url.isEmpty || !seen.add(key)) {
        continue;
      }
      if (app.activeTaskFor(url) != null) {
        continue;
      }
      if (app.findExistingDownload(url) != null) {
        continue;
      }
      if (await app.findExistingPostVideoPath(url) != null) {
        continue;
      }
      batch.add(item);
      if (batch.length >= _batchDownloadCount) {
        break;
      }
    }
    if (batch.isEmpty) {
      showQuickSnack(context, '没有喜爱数超过 $_batchLikesMin 的视频');
      return;
    }
    setState(() => _downloadingPopular = true);
    var done = 0;
    try {
      showQuickSnack(context, '开始下载 ${batch.length} 个视频');
      for (final item in batch) {
        if (!mounted) {
          return;
        }
        await app.downloadVideo(
          url: item.post.url,
          title: item.post.text,
          quality: VideoQuality.best,
        );
        done += 1;
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingPopular = false);
      }
    }
    if (!mounted) {
      return;
    }
    showQuickSnack(context, '已下载 $done 个视频');
  }

  int _columns(BuildContext context) {
    if (AppLayout.isCompact(context)) {
      return 2;
    }
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final categoryKey = _categoryWatchKey(app);
    final active = TickerMode.of(context);
    if (active &&
        _started &&
        !_loading &&
        categoryKey != _loadedCategoryKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load();
        }
      });
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBody(),
        MediaHubFabs(
          onRefresh: _load,
          refreshBusy: _loading,
          onDownload: _downloadPopular,
          downloadBusy: _downloadingPopular,
        ),
      ],
    );
  }

  Widget _wrapPhone(Widget child, {required bool empty}) {
    return child;
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
          detail: '$_error\n请确认 VPN 已开启后再点右下角刷新。',
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
        EmptyHint(
          icon: Icons.smart_display_outlined,
          title: '暂时没有视频',
          detail:
              '这里只显示已打开分类里特别关注的账号、近 ${AppScope.of(context).settings.videoLoad.hours} 小时内符合条件的视频。',
        ),
      );
    }
    final columns = _columns(context);
    return _wrapPhone(
      empty: false,
      CustomScrollView(
        controller: _scroll,
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
          if (_loading)
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
                child: Row(
                  children: [
                    Expanded(
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
                    if (item.post.likes > 0) ...[
                      SizedBox(width: 8.w),
                      Icon(Icons.favorite_border, size: 13.sp, color: Colors.white),
                      SizedBox(width: 4.w),
                      Text(
                        formatCount(item.post.likes),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
