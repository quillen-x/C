import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/porn91_service.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/x_feed_widgets.dart';

class Porn91Page extends StatefulWidget {
  const Porn91Page({super.key});

  @override
  State<Porn91Page> createState() => _Porn91PageState();
}

class _Porn91PageState extends State<Porn91Page> {
  static const _maxPages = 2;

  final List<Porn91Video> _videos = <Porn91Video>[];
  bool _loading = false;
  bool _started = false;
  bool _downloadingPopular = false;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    final id = ++_loadId;
    setState(() {
      _started = true;
      _error = null;
      _loading = true;
      _videos.clear();
    });
    try {
      final videos = await AppScope.of(context).porn91.fetchTopVideos(pages: _maxPages);
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() => _videos.addAll(videos));
    } catch (error) {
      if (!mounted || id != _loadId) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted && id == _loadId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _download(Porn91Video video) async {
    final app = AppScope.of(context);
    if (app.isInDownloadList(video.pageUrl)) {
      showAppSnack(context, '已经在下载列表中');
      return;
    }
    if (await app.porn91.hasDownloaded(video)) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, '已经下载过');
      return;
    }
    showQuickSnack(context, '已加入下载：${video.title}');
    unawaited(
      app.downloadPorn91(video).then((task) {
        if (!mounted || !task.alreadyDownloaded) {
          return;
        }
        showAppSnack(context, '已经下载过');
      }).catchError((Object error) {
        if (!mounted) {
          return;
        }
        showAppSnack(context, error.toString(), error: true);
      }),
    );
  }

  Future<void> _downloadPopular() async {
    if (_downloadingPopular) {
      return;
    }
    final app = AppScope.of(context);
    final batch = <Porn91Video>[];
    for (final video in _videos) {
      if (app.activeTaskFor(video.pageUrl) != null) {
        continue;
      }
      if (app.findExistingDownload(video.pageUrl) != null) {
        continue;
      }
      if (await app.porn91.hasDownloaded(video)) {
        continue;
      }
      batch.add(video);
    }
    if (!mounted) {
      return;
    }
    if (batch.isEmpty) {
      showQuickSnack(context, '没有可下载的视频');
      return;
    }
    setState(() => _downloadingPopular = true);
    var done = 0;
    var skipped = 0;
    try {
      showQuickSnack(context, '开始下载 ${batch.length} 个视频');
      for (final video in batch) {
        if (!mounted) {
          return;
        }
        final task = await app.downloadPorn91(video);
        if (task.alreadyDownloaded) {
          skipped += 1;
          continue;
        }
        if (task.status == TaskStatus.done) {
          done += 1;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingPopular = false);
      }
    }
    if (!mounted) {
      return;
    }
    if (skipped > 0 && done == 0) {
      showQuickSnack(context, '这些视频都已经下载过');
      return;
    }
    showQuickSnack(
      context,
      skipped > 0 ? '已下载 $done 个视频，跳过 $skipped 个' : '已下载 $done 个视频',
    );
  }

  int _columns(BuildContext context) {
    if (AppLayout.isCompact(context)) {
      return 2;
    }
    return 4;
  }

  @override
  Widget build(BuildContext context) {
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

  Widget _buildBody() {
    if (!_started || (_loading && _videos.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _videos.isEmpty) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '每月最佳 加载失败',
        detail: '$_error\n请确认 VPN 已开启后再点右下角刷新。',
      );
    }
    if (_videos.isEmpty) {
      return const EmptyHint(
        icon: Icons.smart_display_outlined,
        title: '暂时没有视频',
        detail: '没有读到本月最热视频。点右下角刷新。',
      );
    }
    final columns = _columns(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: AppLayout.mediaHubPadding(context),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10.h,
              crossAxisSpacing: 10.w,
              childAspectRatio: 1 / 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final video = _videos[index];
                return _Porn91Tile(
                  video: video,
                  onDownload: () => _download(video),
                );
              },
              childCount: _videos.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Porn91Tile extends StatelessWidget {
  const _Porn91Tile({
    required this.video,
    required this.onDownload,
  });

  final Porn91Video video;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12.w),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.surface,
              child: video.thumbnail.isEmpty
                  ? Icon(Icons.movie_outlined, size: 36.w, color: AppColors.textMuted)
                  : AppNetworkImage(
                      url: video.thumbnail,
                      fit: BoxFit.cover,
                      httpHeaders: Porn91Service.imageHeaders,
                      error: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                          size: 32.w,
                        ),
                      ),
                    ),
            ),
          ),
          const ColoredBox(color: Color(0x33000000)),
          Center(
            child: Icon(Icons.play_circle_fill, size: 42.w, color: Colors.white),
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
          if (video.duration.isNotEmpty || video.likes > 0)
            Positioned(
              left: 8.w,
              right: 8.w,
              bottom: 36.h,
              child: Row(
                children: [
                  if (video.likes > 0)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(6.w),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.favorite, size: 11.w, color: Colors.white),
                          SizedBox(width: 3.w),
                          Text(
                            formatCount(video.likes),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (video.duration.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(6.w),
                      ),
                      child: Text(
                        video.duration,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
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
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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
