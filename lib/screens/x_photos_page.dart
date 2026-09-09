import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/media_viewer.dart';
import '../widgets/x_feed_widgets.dart';
import 'x_following_page.dart';

class XPhotosPage extends StatefulWidget {
  const XPhotosPage({super.key});

  @override
  State<XPhotosPage> createState() => _XPhotosPageState();
}

class _XPhotosPageState extends State<XPhotosPage> {
  final ScrollController _scroll = ScrollController();
  List<_FollowedPhoto> _photos = <_FollowedPhoto>[];
  bool _loading = false;
  bool _started = false;
  bool _autoLoadScheduled = false;
  bool _noSpecial = false;
  bool _downloadingPopular = false;
  String? _error;
  int _loadId = 0;

  static const _popularLikesMin = 1000;

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
    final id = ++_loadId;
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
      _noSpecial = false;
      if (!compact || _photos.isEmpty) {
        _photos = <_FollowedPhoto>[];
      }
    });
    final app = AppScope.of(context);
    final names = await app.visibleUsernames(
      from: app.settings.xFollowing,
      specialOnly: true,
      mediaPage: AppPage.xPhotos,
    );
    final accountMap = await app.accountDb.loadMap();
    try {
      if (names.isEmpty) {
        if (!mounted || id != _loadId) {
          return;
        }
        setState(() {
          _photos = <_FollowedPhoto>[];
          _error = null;
          _noSpecial = true;
        });
        return;
      }
      final batch = await app.xFollowingService.fetchPhotoFeed(
        names,
        onProgress: (items, done, total) {
          if (!mounted || id != _loadId) {
            return;
          }
          setState(() {
            _photos = _flatten(items, accountMap: accountMap);
          });
        },
      );
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() {
        _photos = _flatten(batch.posts, accountMap: accountMap);
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

  List<_FollowedPhoto> _flatten(
    List<XPost> posts, {
    Map<String, XAccount> accountMap = const <String, XAccount>{},
  }) {
    final photos = <_FollowedPhoto>[];
    for (final raw in posts) {
      var post = raw;
      final account = accountMap[post.username.toLowerCase()];
      if (account != null &&
          (post.avatarUrl.isEmpty || post.authorName.isEmpty)) {
        post = post.copyWith(
          avatarUrl: post.avatarUrl.isNotEmpty ? post.avatarUrl : account.avatarUrl,
          authorName: post.authorName.isNotEmpty ? post.authorName : account.name,
        );
      }
      for (var index = 0; index < post.media.length; index++) {
        final media = post.media[index];
        if (media.kind == XMediaKind.photo) {
          photos.add(_FollowedPhoto(post: post, media: media, index: index));
        }
      }
    }
    photos.sort((a, b) => b.post.likes.compareTo(a.post.likes));
    final load = AppScope.of(context).settings.photoLoad;
    final postCounts = <String, int>{};
    final keptPosts = <String>{};
    return photos.where((item) {
      if (!load.allowsLikes(item.post.likes)) {
        return false;
      }
      final postId = item.post.id.trim().isEmpty
          ? item.post.url.trim()
          : item.post.id.trim();
      if (postId.isNotEmpty && keptPosts.contains(postId)) {
        return true;
      }
      final key = item.post.username.toLowerCase();
      final n = postCounts[key] ?? 0;
      if (n >= load.perUser) {
        return false;
      }
      postCounts[key] = n + 1;
      if (postId.isNotEmpty) {
        keptPosts.add(postId);
      }
      return true;
    }).toList();
  }

  String _photoUrl(_FollowedPhoto item) {
    final original = item.media.originalUrl.trim();
    if (original.isNotEmpty) {
      return original;
    }
    return item.media.url.trim();
  }

  Future<void> _downloadPopular() async {
    if (_downloadingPopular) {
      return;
    }
    final app = AppScope.of(context);
    final seen = <String>{};
    final batch = <_FollowedPhoto>[];
    for (final item in _photos) {
      if (item.post.likes <= _popularLikesMin) {
        continue;
      }
      final url = _photoUrl(item);
      if (url.isEmpty || !seen.add(url)) {
        continue;
      }
      if (app.isInDownloadList(url) || app.findExistingDownload(url) != null) {
        continue;
      }
      batch.add(item);
    }
    if (batch.isEmpty) {
      showQuickSnack(context, '没有喜爱数超过 $_popularLikesMin 的图片');
      return;
    }
    setState(() => _downloadingPopular = true);
    var done = 0;
    try {
      showQuickSnack(context, '开始下载 ${batch.length} 张图片');
      for (final item in batch) {
        if (!mounted) {
          return;
        }
        await app.downloadDirectMedia(
          url: _photoUrl(item),
          username: item.post.username,
          displayName: item.post.displayName,
          ext: _photoExtFromUrl(_photoUrl(item)),
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
    showQuickSnack(context, '已下载 $done 张图片');
  }

  String _photoExtFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final format = uri?.queryParameters['format']?.toLowerCase() ?? '';
    final path = (uri?.path ?? url).toLowerCase();
    final hay = '$path $format';
    if (hay.contains('png')) {
      return '.png';
    }
    if (hay.contains('gif')) {
      return '.gif';
    }
    if (hay.contains('webp')) {
      return '.webp';
    }
    return '.jpg';
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
      _photos.removeWhere(
        (item) => item.post.username.toLowerCase() == username.toLowerCase(),
      );
    });
  }

  int _columns(BuildContext context) {
    return AppLayout.isCompact(context) ? 2 : 4;
  }

  @override
  Widget build(BuildContext context) {
    final names = AppScope.of(context).settings.xFollowing;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBody(names.isEmpty),
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

  Widget _buildBody(bool emptyFollowing) {
    final compact = AppLayout.isCompact(context);
    if (!_started || (_loading && _photos.isEmpty)) {
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
          detail: '打开「关注」添加账号后，他们发布的图片会出现在这里。',
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
          detail: '当前分类里没有特别关注的账号。到「关注」里给想看的人点特别关注，这里只会加载这些人的图片。',
        ),
      );
    }
    if (_error != null && _photos.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.wifi_off_rounded,
          title: '图片加载失败',
          detail: '$_error\n请确认 VPN 已开启后再点右下角刷新。',
        ),
      );
    }
    if (_photos.isEmpty) {
      return _wrapPhone(
        empty: true,
        EmptyHint(
          icon: Icons.photo_outlined,
          title: '暂时没有图片',
          detail:
              '特别关注的人近 ${AppScope.of(context).settings.photoLoad.hours} 小时内没有符合条件的图片。点右下角刷新。',
        ),
      );
    }
    return _wrapPhone(
      empty: false,
      _PhotoWaterfall(
        photos: _photos,
        controller: _scroll,
        columns: _columns(context),
        loadingMore: _loading,
        onOpenProfile: _openProfile,
      ),
    );
  }
}

class _PhotoWaterfall extends StatelessWidget {
  const _PhotoWaterfall({
    required this.photos,
    required this.controller,
    required this.columns,
    required this.onOpenProfile,
    this.loadingMore = false,
  });

  final List<_FollowedPhoto> photos;
  final ScrollController controller;
  final int columns;
  final ValueChanged<String> onOpenProfile;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final count = columns < 1 ? 1 : columns;
    final buckets = List<List<_FollowedPhoto>>.generate(count, (_) => <_FollowedPhoto>[]);
    final heights = List<double>.filled(count, 0);
    for (final photo in photos) {
      var shortest = 0;
      for (var i = 1; i < count; i++) {
        if (heights[i] < heights[shortest]) {
          shortest = i;
        }
      }
      buckets[shortest].add(photo);
      heights[shortest] += 1 / _photoRatio(photo.media);
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: AppLayout.mediaHubPadding(context),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < count; c++) ...[
                  if (c > 0) SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      children: [
                        for (final photo in buckets[c])
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: _PhotoTile(
                              item: photo,
                              onOpenProfile: () => onOpenProfile(photo.post.username),
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
        if (loadingMore)
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
    );
  }
}

class _FollowedPhoto {
  const _FollowedPhoto({
    required this.post,
    required this.media,
    required this.index,
  });

  final XPost post;
  final XMedia media;
  final int index;
}

double _photoRatio(XMedia media) {
  if (media.width > 0 && media.height > 0) {
    final ratio = media.width / media.height;
    if (ratio < 0.45) {
      return 0.45;
    }
    if (ratio > 1.8) {
      return 1.8;
    }
    return ratio;
  }
  return 0.85;
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.item,
    required this.onOpenProfile,
  });

  final _FollowedPhoto item;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.media.listUrl;
    final name = item.post.displayName.isEmpty
        ? '@${item.post.username}'
        : item.post.displayName;
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12.w),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: _photoRatio(item.media),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: () => showPostMedia(
                  context,
                  <XMedia>[item.media],
                  0,
                  username: item.post.username,
                  displayName: item.post.displayName,
                ),
                child: ColoredBox(
                  color: AppColors.surface,
                  child: imageUrl.isEmpty
                      ? Icon(Icons.photo_outlined, size: 36.w, color: AppColors.textMuted)
                      : AppNetworkImage(
                          url: imageUrl,
                          fit: BoxFit.cover,
                          error: Center(
                            child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32.w),
                          ),
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
                            child: Row(
                              children: [
                                XAvatar(url: item.post.avatarUrl, size: 18),
                                SizedBox(width: 6.w),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }
}
