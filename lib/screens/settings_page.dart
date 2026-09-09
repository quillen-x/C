import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/io_helpers.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _ffmpeg = TextEditingController();
  final TextEditingController _dir = TextEditingController();
  final TextEditingController _photoHours = TextEditingController();
  final TextEditingController _photoPerUser = TextEditingController();
  final TextEditingController _photoMinLikes = TextEditingController();
  final TextEditingController _videoHours = TextEditingController();
  final TextEditingController _videoPerUser = TextEditingController();
  final TextEditingController _videoMinLikes = TextEditingController();
  final TextEditingController _videoMinMinutes = TextEditingController();
  final TextEditingController _videoMaxMinutes = TextEditingController();
  bool _proxyEnabled = true;
  bool _hydrated = false;
  bool _saving = false;
  String? _diagnose;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) {
      return;
    }
    _hydrated = true;
    final settings = AppScope.of(context).settings;
    _host.text = settings.proxyHost;
    _port.text = settings.proxyPort;
    _ffmpeg.text = settings.ffmpegPath;
    _dir.text = settings.downloadDir;
    _photoHours.text = '${settings.photoLoad.hours}';
    _photoPerUser.text = '${settings.photoLoad.perUser}';
    _photoMinLikes.text = '${settings.photoLoad.minLikes}';
    _videoHours.text = '${settings.videoLoad.hours}';
    _videoPerUser.text = '${settings.videoLoad.perUser}';
    _videoMinLikes.text = '${settings.videoLoad.minLikes}';
    _videoMinMinutes.text = '${settings.videoLoad.minDurationMinutes}';
    _videoMaxMinutes.text = '${settings.videoLoad.maxDurationMinutes}';
    _proxyEnabled = settings.proxyEnabled;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _ffmpeg.dispose();
    _dir.dispose();
    _photoHours.dispose();
    _photoPerUser.dispose();
    _photoMinLikes.dispose();
    _videoHours.dispose();
    _videoPerUser.dispose();
    _videoMinLikes.dispose();
    _videoMinMinutes.dispose();
    _videoMaxMinutes.dispose();
    super.dispose();
  }

  int _readInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  AppSettings _collect() {
    final current = AppScope.of(context).settings;
    return AppSettings(
      proxyEnabled: _proxyEnabled,
      proxyHost: _host.text.trim(),
      proxyPort: _port.text.trim(),
      ffmpegPath: _ffmpeg.text.trim(),
      downloadDir: _dir.text.trim().isEmpty
          ? IoHelpers.defaultDownloadDir()
          : _dir.text.trim(),
      photoLoad: MediaLoadConfig(
        hours: _readInt(_photoHours, current.photoLoad.hours),
        perUser: _readInt(_photoPerUser, current.photoLoad.perUser),
        minLikes: _readInt(_photoMinLikes, current.photoLoad.minLikes),
      ),
      videoLoad: MediaLoadConfig(
        hours: _readInt(_videoHours, current.videoLoad.hours),
        perUser: _readInt(_videoPerUser, current.videoLoad.perUser),
        minLikes: _readInt(_videoMinLikes, current.videoLoad.minLikes),
        minDurationMinutes:
            _readInt(_videoMinMinutes, current.videoLoad.minDurationMinutes),
        maxDurationMinutes:
            _readInt(_videoMaxMinutes, current.videoLoad.maxDurationMinutes),
      ),
      xFollowing: current.xFollowing,
      visibleCategories: List<String>.from(current.visibleCategories),
      categories: List<String>.from(current.categories),
      hiddenDownloads: List<String>.from(current.hiddenDownloads),
      categoryMedia: Map<String, CategoryMediaConfig>.from(current.categoryMedia),
    );
  }

  Future<void> _save({bool snack = true}) async {
    setState(() => _saving = true);
    await AppScope.of(context).saveSettings(_collect());
    if (!mounted) return;
    setState(() => _saving = false);
    if (snack) {
      showAppSnack(context, '设置已保存，代理已立即生效');
    }
  }

  Future<void> _runDiagnose() async {
    final app = AppScope.of(context);
    await app.saveSettings(_collect());
    final text = await app.diagnose();
    if (!mounted) return;
    setState(() => _diagnose = text);
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final canPop = Navigator.of(context).canPop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          PhoneNavBar(
            title: '设置',
            centerTitle: true,
            onBack: canPop ? () => Navigator.of(context).pop() : null,
          )
        else
          PageHeader(
            trailing: canPop
                ? IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_ios_new, size: 18.w),
                  )
                : null,
          ),
        Expanded(
          child: ListView(
            padding: AppLayout.pagePadding(context, bottom: 28),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('网络代理', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      AppLayout.isIOS
                          ? 'iPhone 请优先使用系统 VPN。只有本机 App 提供了 HTTP 端口（少见）才需要打开下面的开关。'
                          : '本应用不会内置 VPN。请先打开 Clash Verge / 其他代理，再把本地端口填在这里。常见端口：7890、7897、1080。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用 HTTP 代理'),
                      value: _proxyEnabled,
                      activeThumbColor: AppColors.accent,
                      onChanged: (value) => setState(() => _proxyEnabled = value),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppTextField(controller: _host, hint: '127.0.0.1'),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: AppTextField(controller: _port, hint: '7890'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!AppLayout.isIOS) ...[
                SizedBox(height: 14.h),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ffmpeg', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6.h),
                      Text(
                        '仅在选择「仅音频」时需要。若尚未安装：brew install ffmpeg',
                        style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                      ),
                      SizedBox(height: 12.h),
                      AppTextField(controller: _ffmpeg, hint: 'ffmpeg 路径', prefixIcon: Icons.video_settings),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 14.h),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('保存目录', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      AppLayout.isIOS
                          ? '下载完成后会写入相册。也可在「下载」页点分享，或到「文件」App → 浏览 → 我的 iPhone → C。'
                          : '默认保存到文稿（Documents）下的 MediaDownloader。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    AppTextField(
                      controller: _dir,
                      hint: IoHelpers.defaultDownloadDir(),
                      prefixIcon: Icons.folder_outlined,
                    ),
                    SizedBox(height: 12.h),
                    GhostButton(
                      label: '打开下载目录',
                      icon: Icons.folder_open,
                      onPressed: () {
                        final dir = _dir.text.trim().isEmpty
                            ? IoHelpers.defaultDownloadDir()
                            : _dir.text.trim();
                        IoHelpers.openInFinder(dir);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('图片', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      '只拉取特别关注账号的近期图片。喜爱数填 0 表示不限制。保存后点右下角刷新生效。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            label: '近几小时',
                            controller: _photoHours,
                            hint: '${MediaLoadConfig.defaultHours}',
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _NumberField(
                            label: '每人最多',
                            controller: _photoPerUser,
                            hint: '${MediaLoadConfig.defaultPerUser}',
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _NumberField(
                            label: '最低喜爱数',
                            controller: _photoMinLikes,
                            hint: '${MediaLoadConfig.defaultMinLikes}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('视频', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      '只拉取特别关注账号的近期视频。喜爱数和时长填 0 表示不限制。保存后点右下角刷新生效。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            label: '近几小时',
                            controller: _videoHours,
                            hint: '${MediaLoadConfig.defaultHours}',
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _NumberField(
                            label: '每人最多',
                            controller: _videoPerUser,
                            hint: '${MediaLoadConfig.defaultPerUser}',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            label: '最低喜爱数',
                            controller: _videoMinLikes,
                            hint: '${MediaLoadConfig.defaultMinLikes}',
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _NumberField(
                            label: '最短（分钟）',
                            controller: _videoMinMinutes,
                            hint: '${MediaLoadConfig.defaultMinDurationMinutes}',
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _NumberField(
                            label: '最长（分钟）',
                            controller: _videoMaxMinutes,
                            hint: '${MediaLoadConfig.defaultMaxDurationMinutes}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('使用说明', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8.h),
                    Text(
                      AppLayout.isIOS
                          ? '1. 先打开系统 VPN（小火箭 / Stash），再打开本应用。\n'
                              '2. 视频仅用于下载你拥有权利或已被授权的内容。\n'
                              '3. 本应用不会绕过付费墙或 DRM。'
                          : '1. 先启动 Clash / VPN，再打开本应用。\n'
                              '2. 本应用仅用于下载你拥有权利或已被授权的内容，请勿未授权传播。\n'
                              '3. 本应用不会绕过付费墙或 DRM。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.6, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    GhostButton(
                      label: '检查环境',
                      icon: Icons.fact_check_outlined,
                      onPressed: _runDiagnose,
                    ),
                    if (_diagnose != null) ...[
                      SizedBox(height: 12.h),
                      SelectableText(
                        _diagnose!,
                        style: TextStyle(color: AppColors.text, height: 1.5, fontSize: 13.sp),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _saving ? '保存中' : '保存设置',
                  icon: Icons.save_outlined,
                  busy: _saving,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
        ),
        SizedBox(height: 6.h),
        AppTextField(
          controller: controller,
          hint: hint,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
      ],
    );
  }
}
