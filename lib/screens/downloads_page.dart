import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../screens/settings_page.dart';
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
    final dir = AppScope.of(context).settings.downloadDir;
    final files = await IoHelpers.listSavedFiles(dir);
    if (!mounted) return;
    setState(() => _files = files);
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
              child: const Text('删除'),
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
      detail: '将删除文件「$name」。',
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
      return;
    }
    if (!mounted) {
      return;
    }
    AppScope.of(context).removeTasksByPath(file.path);
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
      detail: task.title.trim().isEmpty ? '将从下载列表里去掉。' : '将删除「${task.title}」。',
    );
    if (!ok || !mounted) {
      return;
    }
    if (task.savePath.isNotEmpty) {
      final file = File(task.savePath);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    AppScope.of(context).removeTask(task.id);
    await _reloadFiles();
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
      detail: '会删除列表里的文件，进行中的下载会保留。',
    );
    if (!ok || !mounted) {
      return;
    }
    for (final file in List<File>.from(_files)) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    for (final task in idle) {
      if (task.savePath.isEmpty) {
        continue;
      }
      try {
        final file = File(task.savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    AppScope.of(context).clearIdleTasks();
    await _reloadFiles();
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
          seen.add(task.savePath) &&
          File(task.savePath).existsSync()) {
        files.insert(0, File(task.savePath));
      }
    }
    final empty = activeTasks.isEmpty && files.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '下载',
          trailing: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              if (compact)
                GhostButton(
                  label: '设置',
                  icon: Icons.settings_outlined,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          backgroundColor: AppColors.bg,
                          body: SafeArea(child: SettingsPage()),
                        ),
                      ),
                    );
                  },
                ),
              GhostButton(
                label: compact ? '刷新' : '打开下载目录',
                icon: compact ? Icons.refresh : Icons.folder_open,
                onPressed: compact
                    ? _reloadFiles
                    : () => IoHelpers.openInFinder(app.settings.downloadDir),
              ),
              if (!empty)
                GhostButton(
                  label: '清空记录',
                  icon: Icons.delete_sweep_outlined,
                  onPressed: _clearAll,
                ),
            ],
          ),
        ),
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
                  padding: AppLayout.pagePadding(context, bottom: 28),
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
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final File file;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final video = IoHelpers.isPlayable(name) &&
        (name.toLowerCase().endsWith('.mp4') ||
            name.toLowerCase().endsWith('.mov') ||
            name.toLowerCase().endsWith('.m4v') ||
            name.toLowerCase().endsWith('.m4a'));
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.w),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16.w),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.w),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.h,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12.w),
                ),
                child: Icon(
                  video ? Icons.play_circle_fill : Icons.image_outlined,
                  color: AppColors.accent,
                  size: 24.w,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      video ? '点击播放' : '点击查看',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLayout.isIOS ? '分享' : '在访达中显示',
                onPressed: onShare,
                icon: Icon(
                  AppLayout.isIOS ? Icons.ios_share : Icons.folder_open,
                  color: AppColors.textMuted,
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
