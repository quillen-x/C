import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../theme.dart';

void showPostMedia(BuildContext context, List<XMedia> media, int index) {
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
        pageBuilder: (_, __, ___) => _VideoViewerPage(media: item),
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
      ),
    ),
  );
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.photos,
    required this.initialIndex,
  });

  final List<XMedia> photos;
  final int initialIndex;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _controller;
  late final TransformationController _transform;
  late int _index;

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
                child: _CloseButton(onTap: () => Navigator.of(context).pop()),
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

  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://x.com/',
  };

  Widget _spinner() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _image(String url, {ImageErrorWidgetBuilder? onError}) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: false,
      headers: _headers,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) {
          return child;
        }
        final ready = frame != null;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: ready ? 1 : 0, child: child),
            if (!ready) _spinner(),
          ],
        );
      },
      errorBuilder: onError,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _image(
      photo.originalUrl,
      onError: (_, __, ___) => _image(
        photo.url,
        onError: (_, __, ___) => Icon(
          Icons.broken_image_outlined,
          color: AppColors.textMuted,
          size: 48.w,
        ),
      ),
    );
  }
}

class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({required this.media});

  final XMedia media;

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
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
                        : GestureDetector(
                            onTap: _toggle,
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio == 0
                                  ? 16 / 9
                                  : controller.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(controller),
                                  if (!controller.value.isPlaying)
                                    Icon(
                                      Icons.play_circle_fill,
                                      color: Colors.white,
                                      size: 64.w,
                                    ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: VideoProgressIndicator(
                                      controller,
                                      allowScrubbing: true,
                                      colors: const VideoProgressColors(
                                        playedColor: AppColors.accent,
                                        bufferedColor: Color(0x66FFFFFF),
                                        backgroundColor: Color(0x33FFFFFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
              Positioned(
                top: 12.h,
                right: 12.w,
                child: _CloseButton(onTap: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: '关闭',
        onPressed: onTap,
        icon: Icon(Icons.close, color: Colors.white, size: 22.w),
      ),
    );
  }
}
