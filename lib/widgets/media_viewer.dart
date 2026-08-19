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

void showPostMedia(
  BuildContext context,
  List<XMedia> media,
  int index, {
  String username = '',
  String displayName = '',
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
