import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/media_viewer.dart';
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
  bool _noSpecial = false;
  String? _error;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
      _noSpecial = false;
    });
    final app = AppScope.of(context);
    final names = await app.visibleUsernames(
      from: app.settings.xFollowing,
      specialOnly: true,
      mediaPage: AppPage.xPhotos,
    );
    try {
      if (names.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _photos = <_FollowedPhoto>[];
          _error = null;
          _noSpecial = true;
        });
        return;
      }
      final posts = await app.xFollowingService.fetchPhotoFeed(names);
      if (!mounted) {
        return;
      }
      setState(() => _photos = _flatten(posts));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _photos = <_FollowedPhoto>[];
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<_FollowedPhoto> _flatten(List<XPost> posts) {
    final photos = <_FollowedPhoto>[];
    for (final post in posts) {
      for (var index = 0; index < post.media.length; index++) {
        final media = post.media[index];
        if (media.kind == XMediaKind.photo) {
          photos.add(_FollowedPhoto(post: post, media: media, index: index));
        }
      }
    }
    return photos;
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
        RefreshFab(onPressed: _load, busy: _loading),
      ],
    );
  }

  Widget _buildBody(bool emptyFollowing) {
    if (!_started || (_loading && _photos.isEmpty)) {
      return const SizedBox.expand();
    }
    if (emptyFollowing) {
      return const EmptyHint(
        icon: Icons.people_outline,
        title: '还没有关注任何人',
        detail: '打开「关注」添加账号后，他们发布的图片会出现在这里。',
      );
    }
    if (AppScope.of(context).settings.visibleCategories.isEmpty) {
      return const EmptyHint(
        icon: Icons.tune,
        title: '还没有打开任何分类',
        detail: '到「分类」打开要看的类别。',
      );
    }
    if (_noSpecial) {
      return const EmptyHint(
        icon: Icons.favorite_border_rounded,
        title: '还没有特别关注',
        detail: '当前分类里没有特别关注的账号。到「关注」里给想看的人点特别关注，这里只会加载这些人的图片。',
      );
    }
    if (_error != null && _photos.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '图片加载失败',
        detail: '$_error\n请确认 VPN 已开启后再刷新。',
      );
    }
    if (_photos.isEmpty) {
      return const EmptyHint(
        icon: Icons.photo_outlined,
        title: '暂时没有图片',
        detail: '特别关注的人最近没有发图片。过一会儿再刷新，或到「关注」里再特别关注几个账号。',
      );
    }
    return _PhotoWaterfall(
      photos: _photos,
      controller: _scroll,
      columns: _columns(context),
      onOpenProfile: _openProfile,
    );
  }
}

class _PhotoWaterfall extends StatelessWidget {
  const _PhotoWaterfall({
    required this.photos,
    required this.controller,
    required this.columns,
    required this.onOpenProfile,
  });

  final List<_FollowedPhoto> photos;
  final ScrollController controller;
  final int columns;
  final ValueChanged<String> onOpenProfile;

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
          padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, AppLayout.mediaHubBarClearance.h),
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
    final imageUrl = item.media.previewUrl.isNotEmpty
        ? item.media.previewUrl
        : item.media.url;
    final extra = item.post.photoCount > 1 ? item.post.photoCount : 0;
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
                  item.post.media,
                  item.index,
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
                          memCacheWidth: 480,
                          error: Center(
                            child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32.w),
                          ),
                        ),
                ),
              ),
            ),
            if (extra > 1)
              Positioned(
                top: 8.h,
                right: 8.w,
                child: IgnorePointer(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(6.w),
                    ),
                    child: Text(
                      '$extra',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
