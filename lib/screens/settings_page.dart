import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/account_db.dart';
import '../services/io_helpers.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import 'x_following_page.dart';

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
  bool _proxyEnabled = true;
  bool _hydrated = false;
  bool _saving = false;
  String? _diagnose;
  Map<String, int> _categoryCounts = <String, int>{};
  List<String> _visibleCategories = <String>[];
  List<String> _categories = <String>[];
  bool _categoriesVisible = false;
  String? _syncingCategory;
  bool _syncCancel = false;
  int _syncDone = 0;
  int _syncTotal = 0;
  int _syncFailed = 0;
  String _syncCurrent = '';
  bool _purging = false;
  final TextEditingController _newCategory = TextEditingController();
  final TextEditingController _purgeTweets = TextEditingController(text: '50');
  final TextEditingController _purgeFollowers = TextEditingController(text: '100');

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
    _proxyEnabled = settings.proxyEnabled;
    _visibleCategories = List<String>.from(settings.visibleCategories);
    _categories = List<String>.from(settings.categories);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _ffmpeg.dispose();
    _dir.dispose();
    _newCategory.dispose();
    _purgeTweets.dispose();
    _purgeFollowers.dispose();
    super.dispose();
  }

  AppSettings _collect() {
    return AppSettings(
      proxyEnabled: _proxyEnabled,
      proxyHost: _host.text.trim(),
      proxyPort: _port.text.trim(),
      ffmpegPath: _ffmpeg.text.trim(),
      downloadDir: _dir.text.trim().isEmpty
          ? IoHelpers.defaultDownloadDir()
          : _dir.text.trim(),
      xFollowing: AppScope.of(context).settings.xFollowing,
      visibleCategories: List<String>.from(_visibleCategories),
      categories: List<String>.from(_categories),
    );
  }

  Future<void> _loadCategories() async {
    try {
      final counts = await AppScope.of(context).accountDb.categoryCounts();
      if (!mounted) {
        return;
      }
      final fromDb = counts.keys.where((item) => item.isNotEmpty);
      setState(() {
        _categoryCounts = counts;
        for (final key in fromDb) {
          if (!_categories.any((item) => item == key)) {
            _categories.add(key);
          }
        }
      });
    } catch (_) {}
  }

  List<String> get _categoryKeys {
    final keys = <String>{..._categories, ..._categoryCounts.keys};
    final list = keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) {
          return 1;
        }
        if (b.isEmpty) {
          return -1;
        }
        return a.compareTo(b);
      });
    return list;
  }

  Future<void> _addCategory() async {
    final key = _newCategory.text.trim().toLowerCase();
    if (key.isEmpty) {
      showAppSnack(context, '请输入分类名', error: true);
      return;
    }
    if (_categoryKeys.contains(key)) {
      showAppSnack(context, '分类「$key」已存在', error: true);
      return;
    }
    setState(() {
      _categories.add(key);
      _newCategory.clear();
    });
    await _save(snack: false);
    if (!mounted) {
      return;
    }
    showAppSnack(context, '已新增分类 $key，默认关闭');
  }

  Future<void> _viewCategory(String category) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return _CategoryMembersDialog(category: category);
      },
    );
    if (!mounted) {
      return;
    }
    await _loadCategories();
  }

  Future<void> _clearCategory(String category) async {
    if (_purging || _syncingCategory != null) {
      return;
    }
    final app = AppScope.of(context);
    final label = XAccount.categoryLabel(category);
    final names = await app.accountDb.usernamesInCategory(category);
    if (!mounted) {
      return;
    }
    if (names.isEmpty) {
      showAppSnack(context, '「$label」里没有关注人');
      return;
    }
    final ok = await _confirmPurge(
      '清空「$label」',
      '将取消关注并删除「$label」下的 ${names.length} 个账号，不可恢复。',
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _purging = true);
    try {
      final removed = await app.purgeAccounts(names);
      if (!mounted) {
        return;
      }
      await _loadCategories();
      showAppSnack(context, '已清空「$label」$removed 人');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _purging = false);
      }
    }
  }

  Future<bool> _confirmPurge(String title, String detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18.sp)),
          content: Text(
            detail,
            style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('取消', style: TextStyle(color: AppColors.textMuted, fontSize: 14.sp)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('清除', style: TextStyle(color: AppColors.danger, fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _purgeByTweets() async {
    if (_purging) {
      return;
    }
    final maxTweets = int.tryParse(_purgeTweets.text.trim());
    if (maxTweets == null || maxTweets < 0) {
      showAppSnack(context, '请输入有效的推文数，例如 50', error: true);
      return;
    }
    final app = AppScope.of(context);
    final names = await app.accountDb.usernamesWithTweetsLessThan(maxTweets);
    if (!mounted) {
      return;
    }
    if (names.isEmpty) {
      showAppSnack(context, '没有推文少于 $maxTweets 的关注');
      return;
    }
    final ok = await _confirmPurge(
      '清除推文过少的关注',
      '将取消关注并删除 ${names.length} 个推文少于 $maxTweets 的账号，不可恢复。',
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _purging = true);
    try {
      final removed = await app.purgeAccounts(names);
      if (!mounted) {
        return;
      }
      await _loadCategories();
      showAppSnack(context, '已清除 $removed 人');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _purging = false);
      }
    }
  }

  Future<void> _purgeByFollowers() async {
    if (_purging) {
      return;
    }
    final maxFollowers = int.tryParse(_purgeFollowers.text.trim());
    if (maxFollowers == null || maxFollowers < 0) {
      showAppSnack(context, '请输入有效的粉丝数，例如 100', error: true);
      return;
    }
    final app = AppScope.of(context);
    final names = await app.accountDb.usernamesWithFollowersLessThan(maxFollowers);
    if (!mounted) {
      return;
    }
    if (names.isEmpty) {
      showAppSnack(context, '没有粉丝少于 $maxFollowers 的关注');
      return;
    }
    final ok = await _confirmPurge(
      '清除粉丝过少的关注',
      '将取消关注并删除 ${names.length} 个关注他的人少于 $maxFollowers 的账号，不可恢复。',
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _purging = true);
    try {
      final removed = await app.purgeAccounts(names);
      if (!mounted) {
        return;
      }
      await _loadCategories();
      showAppSnack(context, '已清除 $removed 人');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _purging = false);
      }
    }
  }

  Future<void> _purgeEmptyDescription() async {
    if (_purging) {
      return;
    }
    final app = AppScope.of(context);
    final names = await app.accountDb.usernamesWithEmptyDescription();
    if (!mounted) {
      return;
    }
    if (names.isEmpty) {
      showAppSnack(context, '没有个人描述为空的关注');
      return;
    }
    final ok = await _confirmPurge(
      '清除无简介的关注',
      '将取消关注并删除 ${names.length} 个个人描述为空的账号，不可恢复。',
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _purging = true);
    try {
      final removed = await app.purgeAccounts(names);
      if (!mounted) {
        return;
      }
      await _loadCategories();
      showAppSnack(context, '已清除 $removed 人');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _purging = false);
      }
    }
  }

  Future<void> _toggleCategory(String category, bool enabled) async {
    setState(() {
      final key = category.trim().toLowerCase();
      _visibleCategories.removeWhere((item) => item.trim().toLowerCase() == key);
      if (enabled) {
        _visibleCategories.add(key);
      }
    });
    await _save(snack: false);
  }

  Future<void> _syncCategory(String category) async {
    if (_syncingCategory != null) {
      return;
    }
    final label = XAccount.categoryLabel(category);
    final app = AppScope.of(context);
    _syncCancel = false;
    setState(() {
      _syncingCategory = category;
      _syncDone = 0;
      _syncTotal = 0;
      _syncFailed = 0;
      _syncCurrent = '';
    });
    StateSetter? setDialog;
    var dialogOpen = false;
    void openDialog() {
      if (dialogOpen) {
        return;
      }
      dialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setLocal) {
              setDialog = setLocal;
              final progress = _syncTotal == 0 ? 0.0 : _syncDone / _syncTotal;
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  '同步「$label」资料',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: 360.w,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        color: AppColors.accent,
                        backgroundColor: AppColors.surfaceAlt,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        '$_syncDone / $_syncTotal',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        _syncCurrent.isEmpty ? '准备中…' : '@$_syncCurrent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
                      ),
                      if (_syncFailed > 0) ...[
                        SizedBox(height: 6.h),
                        Text(
                          '失败 $_syncFailed 个，完成后可再点一次补齐',
                          style: TextStyle(color: AppColors.danger, fontSize: 12.sp),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _syncCancel = true;
                      Navigator.of(dialogContext).pop();
                    },
                    child: Text(
                      '停止',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14.sp),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      final result = await app.syncFollowingProfiles(
        category: category,
        isCanceled: () => _syncCancel,
        onProgress: (done, total, failed, current) {
          if (!mounted) {
            return;
          }
          setState(() {
            _syncDone = done;
            _syncTotal = total;
            _syncFailed = failed;
            _syncCurrent = current;
          });
          if (total > 0) {
            openDialog();
          }
          setDialog?.call(() {});
        },
      );
      if (!mounted) {
        return;
      }
      if (dialogOpen && Navigator.of(context).canPop() && !_syncCancel) {
        Navigator.of(context).pop();
      }
      if (result.pending == 0 && !result.alreadyDone) {
        showAppSnack(context, '「$label」下还没有关注');
      } else if (result.alreadyDone) {
        showAppSnack(context, '「$label」资料已经全部在数据库里，共 ${result.stored} 人。');
      } else if (result.canceled) {
        showAppSnack(context, '已停止。数据库里现有 ${result.stored} 人。');
      } else if (result.failed > 0) {
        showAppSnack(
          context,
          '「$label」同步完成：成功 ${result.pending - result.failed}，失败 ${result.failed}。',
          error: true,
        );
      } else {
        showAppSnack(context, '「$label」已写入数据库 ${result.stored} 人。\n${AccountDb.filePath}');
      }
      await _loadCategories();
    } finally {
      if (mounted) {
        setState(() => _syncingCategory = null);
      }
    }
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
    final visible = TickerMode.of(context);
    if (visible && !_categoriesVisible) {
      _categoriesVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
    }
    if (!visible) {
      _categoriesVisible = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '设置',
 
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_ios_new, size: 18.w),
                ),
              PrimaryButton(
                label: _saving ? '保存中' : '保存设置',
                icon: Icons.save_outlined,
                busy: _saving,
                onPressed: _save,
              ),
            ],
          ),
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
                    Text('关注分类', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      '默认全部关闭。打开某个分类后，关注列表、关注动态、关注图片、视频才会展示这一类账号。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _newCategory,
                            hint: '新分类名，例如 news',
                            onSubmitted: (_) => _addCategory(),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        GhostButton(
                          label: '新增',
                          icon: Icons.add,
                          onPressed: _addCategory,
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    ..._categoryKeys.map((key) {
                      final count = _categoryCounts[key] ?? 0;
                      final on = _visibleCategories.any(
                        (item) => item.trim().toLowerCase() == key,
                      );
                      final syncing = _syncingCategory == key;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    XAccount.categoryLabel(key),
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$count 人',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12.sp,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _viewCategory(key),
                              child: Text(
                                '查看',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                            TextButton(
                              onPressed: _purging || _syncingCategory != null
                                  ? null
                                  : () => _clearCategory(key),
                              child: Text(
                                '清空',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: _purging || _syncingCategory != null
                                      ? AppColors.textMuted
                                      : AppColors.danger,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _syncingCategory != null
                                  ? null
                                  : () => _syncCategory(key),
                              child: Text(
                                syncing ? '同步中' : '同步资料',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                            Switch(
                              value: on,
                              activeThumbColor: AppColors.accent,
                              onChanged: (value) => _toggleCategory(key, value),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('清理关注', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6.h),
                    Text(
                      '按资料库里的推文数、粉丝数或简介清理。会同时取消关注并删除资料，不可恢复。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _purgeTweets,
                            hint: '50',
                            prefixIcon: Icons.filter_alt_outlined,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        GhostButton(
                          label: _purging ? '清除中' : '清除推文过少',
                          icon: Icons.delete_outline,
                          onPressed: _purging ? null : _purgeByTweets,
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      '推文数少于上面这个数字的关注会被清掉，默认 50。',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _purgeFollowers,
                            hint: '100',
                            prefixIcon: Icons.people_outline,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        GhostButton(
                          label: _purging ? '清除中' : '清除粉丝过少',
                          icon: Icons.delete_outline,
                          onPressed: _purging ? null : _purgeByFollowers,
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      '关注他的人少于上面这个数字的会被清掉，默认 100。',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                    ),
                    SizedBox(height: 12.h),
                    GhostButton(
                      label: _purging ? '清除中' : '清除简介为空',
                      icon: Icons.notes,
                      onPressed: _purging ? null : _purgeEmptyDescription,
                    ),
                  ],
                ),
              ),
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
                          : '默认保存到系统下载文件夹下的 MediaDownloader。',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
                    ),
                    SizedBox(height: 12.h),
                    AppTextField(
                      controller: _dir,
                      hint: IoHelpers.defaultDownloadDir(),
                      prefixIcon: Icons.folder_outlined,
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
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryMembersDialog extends StatefulWidget {
  const _CategoryMembersDialog({required this.category});

  final String category;

  @override
  State<_CategoryMembersDialog> createState() => _CategoryMembersDialogState();
}

class _CategoryMembersDialogState extends State<_CategoryMembersDialog> {
  static const _rowHeight = 56.0;
  static const _headerHeight = 38.0;

  static const _columns = <_SheetColumn>[
    _SheetColumn('#', 56, align: TextAlign.right),
    _SheetColumn('avatar', 72),
    _SheetColumn('name', 140),
    _SheetColumn('username', 140),
    _SheetColumn('description', 280, wrap: true),
    _SheetColumn('followers', 88, align: TextAlign.right),
    _SheetColumn('following', 88, align: TextAlign.right),
    _SheetColumn('tweets', 80, align: TextAlign.right),
    _SheetColumn('updated_at', 168),
  ];

  static double get _tableWidth {
    return _columns.fold<double>(0, (sum, column) => sum + column.width);
  }

  final TextEditingController _query = TextEditingController();
  final ScrollController _hScroll = ScrollController();
  List<XAccount> _all = <XAccount>[];
  bool _loading = true;
  String? _error;
  String _sortKey = 'name';
  bool _sortAsc = true;

  String get _label => XAccount.categoryLabel(widget.category);

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _query.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = AppScope.of(context);
      final key = widget.category.trim().toLowerCase();
      final followed = app.settings.xFollowing
          .map((name) => name.toLowerCase())
          .toSet();
      final rows = (await app.accountDb.loadAll()).where((account) {
        if (account.categoryKey != key) {
          return false;
        }
        return followed.contains(account.username.toLowerCase());
      }).toList();
      if (!mounted) {
        return;
      }
      setState(() => _all = rows);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _all = <XAccount>[];
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<XAccount> get _filtered {
    final query = _query.text.trim().toLowerCase();
    final rows = query.isEmpty
        ? List<XAccount>.from(_all)
        : _all.where((account) {
            return account.name.toLowerCase().contains(query) ||
                account.username.toLowerCase().contains(query) ||
                account.description.toLowerCase().contains(query);
          }).toList();
    rows.sort((a, b) {
      final compared = _compare(a, b);
      return _sortAsc ? compared : -compared;
    });
    return rows;
  }

  int _compare(XAccount a, XAccount b) {
    switch (_sortKey) {
      case 'username':
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      case 'description':
        return a.description.toLowerCase().compareTo(b.description.toLowerCase());
      case 'followers':
        return a.followers.compareTo(b.followers);
      case 'following':
        return a.following.compareTo(b.following);
      case 'tweets':
        return a.tweets.compareTo(b.tweets);
      case 'updated_at':
        return a.updatedAt.compareTo(b.updatedAt);
      case 'name':
      default:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  }

  void _sortBy(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
    });
  }

  Future<void> _delete(XAccount account) async {
    final app = AppScope.of(context);
    await app.accountDb.delete(account.username);
    await app.unfollowXAccount(account.username);
    if (!mounted) {
      return;
    }
    setState(() {
      _all.removeWhere(
        (item) => item.username.toLowerCase() == account.username.toLowerCase(),
      );
    });
    showAppSnack(context, '已删除 @${account.username}');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = AppLayout.isCompact(context);
    final rows = _filtered;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12.w : 36.w,
        vertical: compact ? 16.h : 28.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980.w,
          maxHeight: size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_label · ${rows.length} 人',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
              child: AppTextField(
                controller: _query,
                hint: '搜索 name / username / description',
                prefixIcon: Icons.search,
              ),
            ),
            Expanded(child: _buildBody(rows)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<XAccount> rows) {
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _all.isEmpty) {
      return EmptyHint(
        icon: Icons.storage_outlined,
        title: '读取失败',
        detail: '$_error',
      );
    }
    if (_all.isEmpty) {
      return EmptyHint(
        icon: Icons.people_outline,
        title: '这个分类还没有关注人',
        detail: '在关注页添加账号，或先同步资料。',
      );
    }
    if (rows.isEmpty) {
      return const EmptyHint(
        icon: Icons.search_off,
        title: '没有匹配的记录',
        detail: '换个关键词再试。',
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12.w),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.w),
          child: Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            notificationPredicate: (notification) => notification.depth == 0,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth.w,
                child: Column(
                  children: [
                    _headerRow(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          return _dataRow(index + 1, rows[index], index.isOdd);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow() {
    return SizedBox(
      height: _headerHeight.h,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: _columns.map((column) {
            final sortable = column.key != '#' && column.key != 'avatar';
            final active = _sortKey == column.key;
            return _cell(
              width: column.width,
              fillHeight: true,
              child: sortable
                  ? InkWell(
                      onTap: () => _sortBy(column.key),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              column.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: column.align,
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w800,
                                color: active ? AppColors.accent : AppColors.text,
                              ),
                            ),
                          ),
                          if (active)
                            Icon(
                              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 12.w,
                              color: AppColors.accent,
                            ),
                        ],
                      ),
                    )
                  : Text(
                      column.key,
                      maxLines: 1,
                      textAlign: column.align,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                      ),
                    ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _dataRow(int number, XAccount account, bool striped) {
    final values = <String>[
      '$number',
      '',
      account.name.trim().isEmpty ? account.username : account.name,
      account.username,
      account.description,
      '${account.followers}',
      '${account.following}',
      '${account.tweets}',
      _formatUpdatedAt(account.updatedAt),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: striped ? AppColors.surfaceAlt : AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _columns.length; i++)
              _cell(
                width: _columns[i].width,
                child: i == 0
                    ? Tooltip(
                        message: '点击删除',
                        child: InkWell(
                          onTap: () => _delete(account),
                          child: Text(
                            '$number',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.sp,
                              height: 1.35,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : i == 1
                    ? Align(
                        alignment: Alignment.center,
                        child: Tooltip(
                          message: '打开主页',
                          child: InkWell(
                            onTap: () => showAccountHome(context, account),
                            customBorder: const CircleBorder(),
                            child: _SheetAvatar(url: account.avatarUrl, size: 44),
                          ),
                        ),
                      )
                    : Tooltip(
                        message: values[i].isEmpty || _columns[i].wrap ? '' : values[i],
                        waitDuration: const Duration(milliseconds: 400),
                        child: GestureDetector(
                          onDoubleTap: values[i].isEmpty
                              ? null
                              : () async {
                                  await copyText(values[i]);
                                  if (!mounted) {
                                    return;
                                  }
                                  showAppSnack(context, '已复制 ${_columns[i].key}');
                                },
                          child: Text(
                            values[i].isEmpty ? '' : values[i],
                            maxLines: _columns[i].wrap ? null : 1,
                            overflow: _columns[i].wrap
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            softWrap: _columns[i].wrap,
                            textAlign: _columns[i].align,
                            style: TextStyle(
                              fontSize: 12.sp,
                              height: 1.35,
                              color: i == 0 ? AppColors.textMuted : AppColors.text,
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

  Widget _cell({
    required double width,
    required Widget child,
    bool fillHeight = false,
  }) {
    return Container(
      width: width.w,
      height: fillHeight ? double.infinity : null,
      constraints: fillHeight ? null : BoxConstraints(minHeight: _rowHeight.h),
      alignment: Alignment.topLeft,
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
  }

  String _formatUpdatedAt(int millis) {
    if (millis <= 0) {
      return '0';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _SheetColumn {
  const _SheetColumn(
    this.key,
    this.width, {
    this.align = TextAlign.left,
    this.wrap = false,
  });

  final String key;
  final double width;
  final TextAlign align;
  final bool wrap;
}

class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final side = size.w;
    return ClipOval(
      child: ColoredBox(
        color: AppColors.bg,
        child: url.isEmpty
            ? SizedBox(width: side, height: side)
            : Image.network(
                url,
                width: side,
                height: side,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(width: side, height: side),
              ),
      ),
    );
  }
}
