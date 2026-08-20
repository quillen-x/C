import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../services/io_helpers.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'common.dart';
import 'x_feed_links.dart';

void showPostMedia(
  BuildContext context,
  List<XMedia> media,
  int index, {
  String username = '',
  String displayName = '',
  String text = '',
}) {
  if (media.isEmpty || index < 0 || index >= media.length) {
    return;
  }
  final item = media[index];
  if (item.isVideo) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: const Color(0xF2000000),
        pageBuilder: (_, __, ___) => _VideoViewerPage(
          media: item,
          username: username,
          displayName: displayName,
          text: text,
        ),
      ),
    );
    return;
  }
  final photos = media.where((entry) => entry.kind == XMediaKind.photo).toList();
  var start = photos.indexWhere((entry) => entry.url == item.url);
  if (start < 0) {
    start = 0;
  }
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0xF2000000),
      pageBuilder: (_, __, ___) => _PhotoViewerPage(
        photos: photos.isEmpty ? <XMedia>[item] : photos,
        initialIndex: start,
        username: username,
        displayName: displayName,
      ),
    ),
  );
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.photos,
    required this.initialIndex,
    this.username = '',
    this.displayName = '',
  });

  final List<XMedia> photos;
  final int initialIndex;
  final String username;
  final String displayName;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _controller;
  late final TransformationController _transform;
  late int _index;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _transform = TransformationController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _transform.dispose();
    super.dispose();
  }

  bool get _zoomed {
    return _transform.value.getMaxScaleOnAxis() > 1.05;
  }

  XMedia get _current => widget.photos[_index];

  Future<void> _downloadCurrent() async {
    if (_downloading) {
      return;
    }
    setState(() => _downloading = true);
    try {
      final app = AppScope.of(context);
      final url = _current.originalUrl.trim().isEmpty
          ? _current.url.trim()
          : _current.originalUrl.trim();
      if (url.isEmpty) {
        throw StateError('没有可下载的图片地址');
      }
      final username = widget.username.trim().replaceFirst(RegExp(r'^@'), '');
      var category = '未分类';
      var displayName = widget.displayName.trim();
      if (username.isNotEmpty) {
        final accounts = await app.accountDb.loadMap();
        final account = accounts[username.toLowerCase()];
        category = XAccount.categoryLabel(account?.category ?? '');
        if (displayName.isEmpty) {
          displayName = (account?.name ?? '').trim();
        }
      }
      final dir = await IoHelpers.ensurePhotoSaveDir(
        downloadDir: app.settings.downloadDir,
        category: category,
        username: username,
      );
      final path = await _savePhoto(
        url,
        dir.path,
        displayName: displayName.isEmpty ? username : displayName,
      );
      if (Platform.isIOS) {
        await IoHelpers.saveToPhotos(path);
      }
      await app.recordDownloadedFile(
        title: displayName.isNotEmpty
            ? (username.isEmpty ? displayName : '$displayName @$username')
            : (username.isEmpty ? '图片' : '@$username'),
        path: path,
        sourceUrl: url,
      );
      if (!mounted) {
        return;
      }
      showDownloadDoneSnack(context, path);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<String> _savePhoto(
    String url,
    String dir, {
    String displayName = '',
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.userAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Referer', 'https://x.com/');
      request.followRedirects = true;
      request.maxRedirects = 8;
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('图片下载失败（HTTP ${response.statusCode}）');
      }
      final ext = _photoExt(
        uri.path,
        response.headers.contentType?.mimeType ?? '',
      );
      final stamp = IoHelpers.formatSavedStamp(DateTime.now());
      final label = IoHelpers.sanitizeFileName(
        displayName.trim().isEmpty ? stamp : '${displayName.trim()}_$stamp',
      );
      var name = '$label$ext';
      var path = '$dir/$name';
      var index = 2;
      while (await File(path).exists()) {
        name = '${label}_$index$ext';
        path = '$dir/$name';
        index += 1;
      }
      final file = File(path);
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
        }
        await sink.flush();
      } catch (error) {
        await sink.close();
        try {
          await file.delete();
        } catch (_) {}
        rethrow;
      }
      await sink.close();
      if (await file.length() <= 0) {
        try {
          await file.delete();
        } catch (_) {}
        throw StateError('图片文件为空');
      }
      return path;
    } finally {
      client.close(force: true);
    }
  }

  String _photoExt(String path, String mime) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png') || mime.contains('png')) {
      return '.png';
    }
    if (lowerPath.endsWith('.gif') || mime.contains('gif')) {
      return '.gif';
    }
    if (lowerPath.endsWith('.webp') || mime.contains('webp')) {
      return '.webp';
    }
    return '.jpg';
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.photos.length) {
      return;
    }
    _transform.value = Matrix4.identity();
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = widget.photos.length > 1 && _index > 0;
    final canNext = widget.photos.length > 1 && _index < widget.photos.length - 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.photos.length,
                onPageChanged: (value) {
                  _transform.value = Matrix4.identity();
                  setState(() => _index = value);
                },
                itemBuilder: (context, index) {
                  final photo = widget.photos[index];
                  return InteractiveViewer(
                    transformationController: index == _index ? _transform : null,
                    minScale: 1,
                    maxScale: 5,
                    panEnabled: _zoomed,
                    onInteractionEnd: (_) => setState(() {}),
                    child: Center(
                      child: _HiResPhoto(photo: photo),
                    ),
                  );
                },
              ),
              Positioned(
                top: 12.h,
                right: 12.w,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CircleActionButton(
                      tooltip: '下载',
                      onTap: _downloading ? null : _downloadCurrent,
                      child: _downloading
                          ? SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.w,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 22.w,
                            ),
                    ),
                    SizedBox(width: 8.w),
                    _CloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              if (canPrev)
                Positioned(
                  left: 12.w,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.chevron_left,
                      onTap: () => _go(-1),
                    ),
                  ),
                ),
              if (canNext)
                Positioned(
                  right: 12.w,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.chevron_right,
                      onTap: () => _go(1),
                    ),
                  ),
                ),
              if (widget.photos.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20.h,
                  child: Text(
                    '${_index + 1} / ${widget.photos.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
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

class _HiResPhoto extends StatelessWidget {
  const _HiResPhoto({required this.photo});

  final XMedia photo;

  Widget _spinner() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _image(String url, {Widget? onError}) {
    return AppNetworkImage(
      url: url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      placeholder: _spinner(),
      error: onError ??
          Icon(
            Icons.broken_image_outlined,
            color: AppColors.textMuted,
            size: 48.w,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _image(
      photo.originalUrl,
      onError: _image(
        photo.url,
        onError: Icon(
          Icons.broken_image_outlined,
          color: AppColors.textMuted,
          size: 48.w,
        ),
      ),
    );
  }
}

class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({
    required this.media,
    this.username = '',
    this.displayName = '',
    this.text = '',
  });

  final XMedia media;
  final String username;
  final String displayName;
  final String text;

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _startingDownload = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.media.url),
      httpHeaders: const <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://x.com/',
      },
    );
    _controller = controller;
    controller.setLooping(widget.media.kind == XMediaKind.gif);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
      controller.play();
    }).catchError((Object error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    });
    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null || !_ready) {
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  String _videoExt(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mov')) {
      return '.mov';
    }
    if (lower.contains('.m4v')) {
      return '.m4v';
    }
    if (widget.media.kind == XMediaKind.gif && lower.contains('.gif')) {
      return '.gif';
    }
    return '.mp4';
  }

  String get _authorLabel {
    final name = widget.displayName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final user = widget.username.trim().replaceFirst(RegExp(r'^@'), '');
    return user.isEmpty ? '' : '@$user';
  }

  Future<void> _openAuthor() async {
    final user = widget.username.trim().replaceFirst(RegExp(r'^@'), '');
    if (user.isEmpty) {
      return;
    }
    await XFeedLinks.openMention?.call(context, user);
  }

  Future<void> _download() async {
    if (_startingDownload) {
      return;
    }
    final url = widget.media.url.trim();
    if (url.isEmpty) {
      showAppSnack(context, '没有可下载的视频地址', error: true);
      return;
    }
    final app = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    if (app == null) {
      return;
    }
    if (app.activeTaskFor(url) != null) {
      showAppSnack(context, '已在下载中');
      return;
    }
    _startingDownload = true;
    showAppSnack(context, '已加入下载');
    unawaited(
      app
          .downloadDirectMedia(
            url: url,
            username: widget.username,
            displayName: widget.displayName,
            ext: _videoExt(url),
          )
          .then((task) {
            if (!mounted) {
              return;
            }
            if (task.status == TaskStatus.failed) {
              showAppSnack(context, task.error, error: true);
            } else if (task.status == TaskStatus.done) {
              showDownloadDoneSnack(context, task.savePath);
            }
          })
          .catchError((Object error) {
            if (!mounted) {
              return;
            }
            showAppSnack(context, error.toString(), error: true);
          })
          .whenComplete(() {
            _startingDownload = false;
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.space): _toggle,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const ColoredBox(
                  color: Colors.transparent,
                  child: SizedBox.expand(),
                ),
              ),
              Center(
                child: _error != null
                    ? Padding(
                        padding: EdgeInsets.all(24.w),
                        child: Text(
                          '无法播放\n$_error',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 14.sp, height: 1.5),
                        ),
                      )
                    : !_ready || controller == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(
                            aspectRatio: controller.value.aspectRatio == 0
                                ? 16 / 9
                                : controller.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                GestureDetector(
                                  onTap: _toggle,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    alignment: Alignment.center,
                                    children: [
                                      VideoPlayer(controller),
                                      if (!controller.value.isPlaying)
                                        Icon(
                                          Icons.play_circle_fill,
                                          color: Colors.white,
                                          size: 64.w,
                                        ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: <Color>[
                                            Color(0xCC000000),
                                            Color(0x00000000),
                                          ],
                                        ),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(16.w, 12.h, 88.w, 28.h),
                                        child: widget.text.trim().isEmpty
                                            ? const SizedBox.shrink()
                                            : Text(
                                                widget.text.trim(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14.sp,
                                                  height: 1.35,
                                                  fontWeight: FontWeight.w600,
                                                ),
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
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: <Color>[
                                          Color(0xCC000000),
                                          Color(0x00000000),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (_authorLabel.isNotEmpty)
                                            Padding(
                                              padding: EdgeInsets.only(bottom: 10.h),
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: _openAuthor,
                                                  child: Text(
                                                    _authorLabel,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13.sp,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          _VideoScrubBar(controller: controller),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
              Positioned(
                top: 12.h,
                right: 12.w,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _VideoDownloadButton(
                      sourceUrl: widget.media.url,
                      onTap: _download,
                    ),
                    SizedBox(width: 8.w),
                    _CloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoScrubBar extends StatelessWidget {
  const _VideoScrubBar({required this.controller});

  final VideoPlayerController controller;

  static String _format(Duration duration) {
    final clamped = duration.isNegative ? Duration.zero : duration;
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes.remainder(60);
    final seconds = clamped.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  void _seek(double relative) {
    final duration = controller.value.duration;
    if (duration <= Duration.zero) {
      return;
    }
    controller.seekTo(duration * relative.clamp(0.0, 1.0));
  }

  void _seekFromLocal(Offset local, double width) {
    if (width <= 0) {
      return;
    }
    _seek(local.dx / width);
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    final played = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    var buffered = 0.0;
    for (final range in value.buffered) {
      final end = duration.inMilliseconds <= 0
          ? 0.0
          : range.end.inMilliseconds / duration.inMilliseconds;
      if (end > buffered) {
        buffered = end;
      }
    }
    buffered = buffered.clamp(0.0, 1.0);
    final timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    return Row(
      children: [
        SizedBox(
          width: 42.w,
          child: Text(_format(position), style: timeStyle),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _seekFromLocal(details.localPosition, width),
                onHorizontalDragStart: (details) {
                  _seekFromLocal(details.localPosition, width);
                },
                onHorizontalDragUpdate: (details) {
                  _seekFromLocal(details.localPosition, width);
                },
                child: SizedBox(
                  height: 28.h,
                  child: Center(
                    child: SizedBox(
                      height: 4.h,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0x55FFFFFF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const SizedBox.expand(),
                          ),
                          FractionallySizedBox(
                            widthFactor: buffered,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x99FFFFFF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: played,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned(
                            left: (width * played - 6.w).clamp(
                              0.0,
                              (width - 12.w).clamp(0.0, width),
                            ),
                            child: Container(
                              width: 12.w,
                              height: 12.w,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
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
        SizedBox(width: 8.w),
        SizedBox(
          width: 42.w,
          child: Text(
            _format(duration),
            textAlign: TextAlign.right,
            style: timeStyle,
          ),
        ),
      ],
    );
  }
}

class _VideoDownloadButton extends StatelessWidget {
  const _VideoDownloadButton({
    required this.sourceUrl,
    required this.onTap,
  });

  final String sourceUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final task = AppScope.of(context).activeTaskFor(sourceUrl);
    final active = task != null;
    final progress = task?.progress ?? 0;
    return _CircleActionButton(
      tooltip: active ? '下载中' : '下载',
      onTap: active ? null : onTap,
      child: active
          ? SizedBox(
              width: 18.w,
              height: 18.w,
              child: CircularProgressIndicator(
                value: progress > 0.05 && progress < 1 ? progress : null,
                strokeWidth: 2.w,
                color: Colors.white,
              ),
            )
          : Icon(
              Icons.download_rounded,
              color: Colors.white,
              size: 22.w,
            ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 32.w),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.tooltip,
    required this.child,
    this.onTap,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: child,
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CircleActionButton(
      tooltip: '关闭',
      onTap: onTap,
      child: Icon(Icons.close, color: Colors.white, size: 22.w),
    );
  }
}
