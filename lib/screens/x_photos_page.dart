import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import '../widgets/media_viewer.dart';

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
  String? _error;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
    });
    final app = AppScope.of(context);
    final names = await app.visibleUsernames(from: app.settings.xFollowing);
    try {
      if (names.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _photos = <_FollowedPhoto>[];
          _error = null;
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

  int _columns(BuildContext context) {
    return AppLayout.isCompact(context) ? 2 : 5;
  }

  @override
  Widget build(BuildContext context) {
    final names = AppScope.of(context).settings.xFollowing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '关注图片',
          trailing: _started
              ? GhostButton(
                  label: _loading ? '刷新中' : '刷新',
                  icon: Icons.refresh,
                  onPressed: _loading ? null : _load,
                )
              : null,
        ),
        Expanded(child: _buildBody(names.isEmpty)),
      ],
    );
  }

  Widget _buildBody(bool emptyFollowing) {
    if (!_started) {
      return Center(
        child: PrimaryButton(
          label: '加载图片',
          icon: Icons.photo_outlined,
          onPressed: _load,
        ),
      );
    }
    if (_loading && _photos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
        detail: '关注的人最近没有发图片。过一会儿再刷新，或到「关注」里加几个账号。',
      );
    }
    return _PhotoWaterfall(
      photos: _photos,
      controller: _scroll,
      columns: _columns(context),
    );
  }
}

class _PhotoWaterfall extends StatelessWidget {
  const _PhotoWaterfall({
    required this.photos,
    required this.controller,
    required this.columns,
  });

  final List<_FollowedPhoto> photos;
  final ScrollController controller;
  final int columns;

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
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 20.h),
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
                            child: _PhotoTile(item: photo),
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
  const _PhotoTile({required this.item});

  final _FollowedPhoto item;

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
      child: InkWell(
        onTap: () => showPostMedia(context, item.post.media, item.index),
        child: AspectRatio(
          aspectRatio: _photoRatio(item.media),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.surface,
                child: imageUrl.isEmpty
                    ? Icon(Icons.photo_outlined, size: 36.w, color: AppColors.textMuted)
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32.w),
                        ),
                      ),
              ),
              if (extra > 1)
                Positioned(
                  top: 8.h,
                  right: 8.w,
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
                    child: Text(
                      '@${item.post.username}',
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
            ],
          ),
        ),
      ),
    );
  }
}
