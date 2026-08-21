import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../services/io_helpers.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<File> _files = <File>[];
  Map<String, String> _displayNames = <String, String>{};
  String _taskSig = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reloadFiles();
      }
    });
  }

  Future<void> _reloadFiles() async {
    final app = AppScope.of(context);
    final files = await IoHelpers.listSavedFiles(app.settings.downloadDir);
    final profiles = await app.accountDb.loadMap();
    if (!mounted) return;
    final names = <String, String>{};
    for (final entry in profiles.entries) {
      final name = entry.value.name.trim();
      if (name.isNotEmpty) {
        names[entry.key] = name;
      }
    }
    setState(() {
      _files = files.where((file) => !app.isDownloadHidden(file.path)).toList();
      _displayNames = names;
    });
  }

  Future<void> _open(String path) async {
    try {
      await IoHelpers.openPreview(path);
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString(), error: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String detail,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去掉'),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _deleteFile(File file) async {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final ok = await _confirm(
      title: '删除这条记录？',
      detail: '只从列表里去掉「$name」，不会删除已下载的文件。',
    );
    if (!ok || !mounted) {
      return;
    }
    final app = AppScope.of(context);
    app.removeTasksByPath(file.path);
    await app.hideDownloadRecords([file.path]);
    if (!mounted) {
      return;
    }
    setState(() {
      _files.removeWhere((item) => item.path == file.path);
    });
  }

  Future<void> _deleteTask(DownloadTask task) async {
    if (task.status == TaskStatus.running || task.status == TaskStatus.queued) {
      showAppSnack(context, '进行中的任务不能删除');
      return;
    }
    final ok = await _confirm(
      title: '删除这条记录？',
      detail: task.title.trim().isEmpty
          ? '只从下载列表里去掉，不会删除已下载的文件。'
          : '只从列表里去掉「${task.title}」，不会删除已下载的文件。',
    );
    if (!ok || !mounted) {
      return;
    }
    final app = AppScope.of(context);
    app.removeTask(task.id);
    if (task.savePath.isNotEmpty) {
      await app.hideDownloadRecords([task.savePath]);
    }
    if (mounted) {
      await _reloadFiles();
    }
  }

  Future<void> _clearAll() async {
    final app = AppScope.of(context);
    final idle = app.tasks
        .where(
          (task) =>
              task.status != TaskStatus.running &&
              task.status != TaskStatus.queued,
        )
        .toList();
    if (idle.isEmpty && _files.isEmpty) {
      return;
    }
    final ok = await _confirm(
      title: '清空全部下载记录？',
      detail: '只清空列表，不会删除已下载的文件。进行中的下载会保留。',
    );
    if (!ok || !mounted) {
      return;
    }
    final paths = <String>{
      ..._files.map((file) => file.path),
      ...idle.map((task) => task.savePath).where((path) => path.isNotEmpty),
    };
    app.clearIdleTasks();
    await app.hideDownloadRecords(paths);
    if (mounted) {
      await _reloadFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sig = app.tasks
        .map((task) => '${task.id}:${task.status}:${task.savePath}')
        .join('|');
    if (sig != _taskSig) {
      _taskSig = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reloadFiles();
        }
      });
    }
    final compact = AppLayout.isCompact(context);
    final activeTasks = app.tasks
        .where((task) => task.status != TaskStatus.done)
        .toList();
    final files = List<File>.from(_files);
    final seen = files.map((file) => file.path).toSet();
    for (final task in app.tasks) {
      if (task.status == TaskStatus.done &&
          task.savePath.isNotEmpty &&
          !app.isDownloadHidden(task.savePath) &&
          seen.add(task.savePath) &&
          File(task.savePath).existsSync()) {
        files.insert(0, File(task.savePath));
      }
    }
    final empty = activeTasks.isEmpty && files.isEmpty;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              const PhoneNavBar(title: '下载', centerTitle: true)
            else
              const PageHeader(),
            Expanded(
              child: empty
                  ? EmptyHint(
                      icon: Icons.inbox_outlined,
                      title: '还没有文件',
                      detail: compact
                          ? '打开「动态」，在帖子里点下载。完成后会出现在这里，点一下就能看。'
                          : '打开「动态」或「关注」，在帖子里点下载。',
                    )
                  : ListView(
                      padding: AppLayout.pagePadding(
                        context,
                        bottom: AppLayout.mediaHubBarClearance,
                      ),
                      children: [
                        ...activeTasks.map((task) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: 10.h),
                            child: _TaskTile(
                              task: task,
                              onDelete: () => _deleteTask(task),
                            ),
                          );
                        }),
                        ...files.map((file) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: 10.h),
                            child: _FileTile(
                              file: file,
                              names: _displayNames,
                              onOpen: () => _open(file.path),
                              onShare: () => IoHelpers.openInFinder(file.path),
                              onDelete: () => _deleteFile(file),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
        if (!empty)
          Positioned(
            right: 16.w,
            bottom: 16.h,
            child: Material(
              color: AppColors.surfaceAlt,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999.w),
              child: InkWell(
                onTap: _clearAll,
                borderRadius: BorderRadius.circular(999.w),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        size: 18.w,
                        color: AppColors.danger,
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        '清空所有记录',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecordPreview extends StatefulWidget {
  const _RecordPreview({
    required this.file,
    required this.video,
    required this.image,
    required this.ffmpegPath,
  });

  final File file;
  final bool video;
  final bool image;
  final String ffmpegPath;

  @override
  State<_RecordPreview> createState() => _RecordPreviewState();
}

class _RecordPreviewState extends State<_RecordPreview> {
  File? _thumb;
  VideoPlayerController? _player;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RecordPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _player?.dispose();
      _player = null;
      _thumb = null;
      _ready = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.image) {
      if (mounted) {
        setState(() => _ready = true);
      }
      return;
    }
    if (!widget.video) {
      if (mounted) {
        setState(() => _ready = true);
      }
      return;
    }
    final thumb = await IoHelpers.videoThumbnail(
      widget.file.path,
      ffmpegPath: widget.ffmpegPath,
    );
    if (!mounted) {
      return;
    }
    if (thumb != null) {
      setState(() {
        _thumb = thumb;
        _ready = true;
      });
      return;
    }
    final player = VideoPlayerController.file(widget.file);
    try {
      await player.initialize();
      await player.setVolume(0);
      await player.pause();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _ready = true;
      });
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10.w);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: 96.w,
        height: 64.w,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.surfaceAlt, child: _content()),
            if (widget.video)
              const ColoredBox(color: Color(0x33000000)),
            if (widget.video)
              Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white.withValues(alpha: 0.92),
                  size: 26.w,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (widget.image) {
      return Image.file(
        widget.file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(Icons.image_outlined),
      );
    }
    if (_thumb != null) {
      return Image.file(
        _thumb!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(Icons.play_circle_fill),
      );
    }
    final player = _player;
    if (player != null && player.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: player.value.size.width,
          height: player.value.size.height,
          child: VideoPlayer(player),
        ),
      );
    }
    if (!_ready) {
      return Center(
        child: SizedBox(
          width: 16.w,
          height: 16.w,
          child: CircularProgressIndicator(strokeWidth: 2.w),
        ),
      );
    }
    return _fallbackIcon(
      widget.video ? Icons.play_circle_fill : Icons.audiotrack_outlined,
    );
  }

  Widget _fallbackIcon(IconData icon) {
    return Center(
      child: Icon(icon, color: AppColors.accent, size: 24.w),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.names,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final File file;
  final Map<String, String> names;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final info = IoHelpers.describeSavedFile(
      file,
      AppScope.of(context).settings.downloadDir,
    );
    final video = IoHelpers.isVideoFile(info.fileName);
    final image = IoHelpers.isImageFile(info.fileName);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.w),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16.w),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.w),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _RecordPreview(
                file: file,
                video: video,
                image: image,
                ffmpegPath: AppScope.of(context).settings.ffmpegPath,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.titleFor(names),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      info.subtitleFor(names),
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
              IconButton(
                tooltip: '删除记录',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: AppColors.danger),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onDelete});

  final DownloadTask task;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color, size: 18.w),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                ),
              ),
              Text(_statusLabel, style: TextStyle(color: _color, fontSize: 12.sp)),
              if (task.status != TaskStatus.running &&
                  task.status != TaskStatus.queued)
                IconButton(
                  tooltip: '删除记录',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: AppColors.danger, size: 18.w),
                ),
            ],
          ),
          SizedBox(height: 10.h),
          LinearProgressIndicator(
            value: task.status == TaskStatus.running ? task.progress : 0,
            minHeight: 6.h,
            backgroundColor: AppColors.surfaceAlt,
            color: _color,
          ),
          if (task.status == TaskStatus.failed) ...[
            SizedBox(height: 8.h),
            Text(
              task.error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.danger, fontSize: 12.sp),
            ),
          ] else if (task.speed.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              task.speed,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _icon {
    return Icons.alternate_email;
  }

  Color get _color {
    switch (task.status) {
      case TaskStatus.failed:
        return AppColors.danger;
      case TaskStatus.running:
        return AppColors.accent;
      case TaskStatus.queued:
      case TaskStatus.done:
      case TaskStatus.canceled:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    switch (task.status) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.running:
        return '${(task.progress * 100).toStringAsFixed(0)}%';
      case TaskStatus.done:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
      case TaskStatus.canceled:
        return '已取消';
    }
  }
}
