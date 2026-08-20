import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';
import '../services/account_db.dart';
import '../services/category_excel.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import 'x_following_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final TextEditingController _newCategory = TextEditingController();
  Map<String, int> _categoryCounts = <String, int>{};
  List<String> _visibleCategories = <String>[];
  List<String> _categories = <String>[];
  Map<String, CategoryMediaConfig> _categoryMedia = <String, CategoryMediaConfig>{};
  bool _hydrated = false;
  bool _loaded = false;
  String? _syncingCategory;
  String? _exportingCategory;
  bool _syncCancel = false;
  int _syncDone = 0;
  int _syncTotal = 0;
  int _syncFailed = 0;
  String _syncCurrent = '';
  bool _purging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) {
      return;
    }
    _hydrated = true;
    final settings = AppScope.of(context).settings;
    _visibleCategories = List<String>.from(settings.visibleCategories);
    _categories = List<String>.from(settings.categories);
    _categoryMedia = Map<String, CategoryMediaConfig>.from(settings.categoryMedia);
  }

  @override
  void dispose() {
    _newCategory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    final next = app.settings.copy();
    next.visibleCategories = List<String>.from(_visibleCategories);
    next.categories = List<String>.from(_categories);
    next.categoryMedia = Map<String, CategoryMediaConfig>.from(_categoryMedia);
    await app.saveSettings(next);
  }

  Future<void> _loadCategories() async {
    try {
      final app = AppScope.of(context);
      final counts = await app.accountDb.categoryCounts(
        following: app.settings.xFollowing.toSet(),
      );
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
    await _save();
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

  Future<List<XAccount>> _followedInCategory(String category) async {
    final app = AppScope.of(context);
    final key = category.trim().toLowerCase();
    final followed = app.settings.xFollowing
        .map((name) => name.toLowerCase())
        .toSet();
    return (await app.accountDb.loadAll()).where((account) {
      if (account.categoryKey != key) {
        return false;
      }
      return followed.contains(account.username.toLowerCase());
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _exportCategory(String category) async {
    if (_exportingCategory != null || _purging || _syncingCategory != null) {
      return;
    }
    final label = XAccount.categoryLabel(category);
    setState(() => _exportingCategory = category);
    try {
      final rows = await _followedInCategory(category);
      if (!mounted) {
        return;
      }
      if (rows.isEmpty) {
        showAppSnack(context, '「$label」里没有关注人');
        return;
      }
      await CategoryExcel.export(
        accounts: rows,
        categoryLabel: label,
      );
      if (!mounted) {
        return;
      }
      showAppSnack(
        context,
        AppLayout.isIOS
            ? '已导出「$label」${rows.length} 人'
            : '已导出「$label」${rows.length} 人，已打开文件',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _exportingCategory = null);
      }
    }
  }

  Future<void> _deleteCategory(String category) async {
    if (_purging || _syncingCategory != null) {
      return;
    }
    final app = AppScope.of(context);
    final label = XAccount.categoryLabel(category);
    final names = await app.accountDb.usernamesInCategory(category);
    if (!mounted) {
      return;
    }
    final detail = names.isEmpty
        ? '将删除分类「$label」，不可恢复。'
        : '将取消关注并删除「$label」下的 ${names.length} 个账号，同时删除该分类，不可恢复。';
    final ok = await _confirmClear(
      '删除「$label」',
      detail,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _purging = true);
    try {
      final removed = await app.purgeAccounts(names);
      final key = category.trim().toLowerCase();
      setState(() {
        _categories.removeWhere((item) => item.trim().toLowerCase() == key);
        _visibleCategories.removeWhere(
          (item) => item.trim().toLowerCase() == key,
        );
        _categoryMedia.remove(key);
      });
      await _save();
      if (!mounted) {
        return;
      }
      await _loadCategories();
      showAppSnack(
        context,
        removed > 0 ? '已删除「$label」，并清除 $removed 人' : '已删除分类「$label」',
      );
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

  Future<bool> _confirmClear(String title, String detail) async {
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
              child: Text('删除', style: TextStyle(color: AppColors.danger, fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _toggleCategory(String category, bool enabled) async {
    setState(() {
      final key = category.trim().toLowerCase();
      _visibleCategories.removeWhere((item) => item.trim().toLowerCase() == key);
      if (enabled) {
        _visibleCategories.add(key);
      }
    });
    await _save();
  }

  CategoryMediaConfig _mediaFor(String category) {
    final key = category.trim().toLowerCase();
    return _categoryMedia[key] ?? CategoryMediaConfig.all;
  }

  Future<void> _toggleCategoryMedia(
    String category, {
    bool? posts,
    bool? photos,
    bool? videos,
  }) async {
    final key = category.trim().toLowerCase();
    final next = _mediaFor(key).copyWith(
      posts: posts,
      photos: photos,
      videos: videos,
    );
    if (next.isEmpty) {
      showAppSnack(context, '至少保留一种内容', error: true);
      return;
    }
    setState(() => _categoryMedia[key] = next);
    await _save();
  }

  Widget _mediaChip({
    required String asset,
    required String tooltip,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: on ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10.w),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.w),
          child: Padding(
            padding: EdgeInsets.all(8.w),
            child: SvgPicture.asset(
              asset,
              width: 18.w,
              height: 18.w,
              colorFilter: ColorFilter.mode(
                on ? AppColors.accent : AppColors.textMuted,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconAction({
    required String asset,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
    bool busy = false,
  }) {
    final enabled = onPressed != null && !busy;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.all(8.w),
      constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
      icon: busy
          ? SizedBox(
              width: 16.w,
              height: 16.w,
              child: CircularProgressIndicator(
                strokeWidth: 2.w,
                color: AppColors.textMuted,
              ),
            )
          : SvgPicture.asset(
              asset,
              width: 18.w,
              height: 18.w,
              colorFilter: ColorFilter.mode(
                enabled
                    ? (color ?? AppColors.textMuted)
                    : AppColors.textMuted.withValues(alpha: 0.35),
                BlendMode.srcIn,
              ),
            ),
    );
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

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.of(context);
    if (visible && !_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final settings = AppScope.of(context).settings;
        setState(() {
          _visibleCategories = List<String>.from(settings.visibleCategories);
          _categories = List<String>.from(settings.categories);
          _categoryMedia = Map<String, CategoryMediaConfig>.from(
            settings.categoryMedia,
          );
        });
        _loadCategories();
      });
    }
    if (!visible) {
      _loaded = false;
    }
    final compact = AppLayout.isCompact(context);
    final canPop = Navigator.of(context).canPop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact || canPop)
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
            padding: EdgeInsets.fromLTRB(
              16.w,
              compact || canPop ? 0 : 16.h,
              16.w,
              16.h,
            ),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('关注分类', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
                   
                    SizedBox(height: 12.h),
                    InlineActionField(
                      controller: _newCategory,
                      hint: '新分类名，例如 news',
                      actionLabel: '新增',
                      onAction: _addCategory,
                    ),
                    SizedBox(height: 8.h),
                    ..._categoryKeys.map((key) {
                      final count = _categoryCounts[key] ?? 0;
                      final on = _visibleCategories.any(
                        (item) => item.trim().toLowerCase() == key,
                      );
                      final media = _mediaFor(key);
                      final syncing = _syncingCategory == key;
                      final exporting = _exportingCategory == key;
                      final busy = _purging || _syncingCategory != null;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                _iconAction(
                                  asset: 'assets/images/watch.svg',
                                  tooltip: '查看',
                                  onPressed: () => _viewCategory(key),
                                ),
                                _iconAction(
                                  asset: 'assets/images/export.svg',
                                  tooltip: exporting ? '导出中' : '导出',
                                  busy: exporting,
                                  onPressed: busy || _exportingCategory != null
                                      ? null
                                      : () => _exportCategory(key),
                                ),
                                _iconAction(
                                  asset: 'assets/images/delete.svg',
                                  tooltip: '删除',
                                  color: AppColors.danger,
                                  onPressed: busy
                                      ? null
                                      : () => _deleteCategory(key),
                                ),
                                _iconAction(
                                  asset: 'assets/images/sync.svg',
                                  tooltip: syncing ? '同步中' : '同步资料',
                                  busy: syncing,
                                  onPressed: _syncingCategory != null
                                      ? null
                                      : () => _syncCategory(key),
                                ),
                                Switch(
                                  value: on,
                                  activeThumbColor: AppColors.accent,
                                  onChanged: (value) =>
                                      _toggleCategory(key, value),
                                ),
                              ],
                            ),
                            SizedBox(height: 6.h),
                            Wrap(
                              spacing: 6.w,
                              runSpacing: 6.h,
                              children: [
                                _mediaChip(
                                  asset: 'assets/images/posts.svg',
                                  tooltip: '帖子',
                                  on: media.posts,
                                  onTap: () => _toggleCategoryMedia(
                                    key,
                                    posts: !media.posts,
                                  ),
                                ),
                                _mediaChip(
                                  asset: 'assets/images/image.svg',
                                  tooltip: '图片',
                                  on: media.photos,
                                  onTap: () => _toggleCategoryMedia(
                                    key,
                                    photos: !media.photos,
                                  ),
                                ),
                                _mediaChip(
                                  asset: 'assets/images/video.svg',
                                  tooltip: '视频',
                                  on: media.videos,
                                  onTap: () => _toggleCategoryMedia(
                                    key,
                                    videos: !media.videos,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
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
  static const _rowHeight = 48.0;
  static const _headerHeight = 38.0;

  static const _columns = <_SheetColumn>[
    _SheetColumn('#', 40, align: TextAlign.right),
    _SheetColumn('avatar', 48),
    _SheetColumn('name', 140),
    _SheetColumn('description', 280, wrap: true),
    _SheetColumn('followers', 88, align: TextAlign.right),
    _SheetColumn('following', 88, align: TextAlign.right),
    _SheetColumn('tweets', 80, align: TextAlign.right),
    _SheetColumn('updated_at', 150),
  ];

  static double get _tableWidth {
    return _columns.fold<double>(0, (sum, column) => sum + column.width);
  }

  final TextEditingController _query = TextEditingController();
  final TextEditingController _followersMax = TextEditingController();
  final TextEditingController _tweetsMax = TextEditingController();
  final TextEditingController _followingMax = TextEditingController();
  final TextEditingController _descKeyword = TextEditingController();
  final TextEditingController _inactiveDays = TextEditingController(text: '15');
  final ScrollController _hScroll = ScrollController();
  List<XAccount> _all = <XAccount>[];
  bool _loading = true;
  bool _busy = false;
  bool _scanCancel = false;
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
    _followersMax.dispose();
    _tweetsMax.dispose();
    _followingMax.dispose();
    _descKeyword.dispose();
    _inactiveDays.dispose();
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
    if (_busy) {
      return;
    }
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

  Future<bool> _confirm(String title, String detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18.sp),
          ),
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
              child: Text('删除', style: TextStyle(color: AppColors.danger, fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _purgeWhere({
    required String title,
    required String Function(int count) detail,
    required bool Function(XAccount account) match,
    required String emptyMessage,
  }) async {
    if (_busy) {
      return;
    }
    final targets = _all.where(match).toList();
    if (targets.isEmpty) {
      showAppSnack(context, emptyMessage, error: true);
      return;
    }
    final ok = await _confirm(title, detail(targets.length));
    if (!ok || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final names = targets.map((item) => item.username).toList();
      final removed = await AppScope.of(context).purgeAccounts(names);
      if (!mounted) {
        return;
      }
      final removedSet = names.map((name) => name.toLowerCase()).toSet();
      setState(() {
        _all.removeWhere(
          (item) => removedSet.contains(item.username.toLowerCase()),
        );
      });
      showAppSnack(context, '已删除 $removed 人');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _purgeFollowersLessThan() async {
    final max = int.tryParse(_followersMax.text.trim());
    if (max == null || max < 0) {
      showAppSnack(context, '请输入有效的粉丝数，例如 100', error: true);
      return;
    }
    await _purgeWhere(
      title: '删除粉丝过少的关注',
      detail: (count) => '将取消关注并删除粉丝少于 $max 的 $count 个账号，不可恢复。',
      match: (account) => account.followers < max,
      emptyMessage: '没有粉丝少于 $max 的关注',
    );
  }

  Future<void> _purgeTweetsLessThan() async {
    final max = int.tryParse(_tweetsMax.text.trim());
    if (max == null || max < 0) {
      showAppSnack(context, '请输入有效的推文数，例如 50', error: true);
      return;
    }
    await _purgeWhere(
      title: '删除推文过少的关注',
      detail: (count) => '将取消关注并删除推文少于 $max 的 $count 个账号，不可恢复。',
      match: (account) => account.tweets < max,
      emptyMessage: '没有推文少于 $max 的关注',
    );
  }

  Future<void> _purgeFollowingLessThan() async {
    final max = int.tryParse(_followingMax.text.trim());
    if (max == null || max < 0) {
      showAppSnack(context, '请输入有效的关注数，例如 100', error: true);
      return;
    }
    await _purgeWhere(
      title: '删除关注过少的账号',
      detail: (count) => '将取消关注并删除关注数少于 $max 的 $count 个账号，不可恢复。',
      match: (account) => account.following < max,
      emptyMessage: '没有关注数少于 $max 的账号',
    );
  }

  Future<void> _purgeDescriptionMissingKeyword() async {
    final keyword = _descKeyword.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      showAppSnack(context, '请输入描述里要包含的关键字', error: true);
      return;
    }
    await _purgeWhere(
      title: '删除简介不含关键字的关注',
      detail: (count) => '将取消关注并删除简介不含「$keyword」的 $count 个账号，不可恢复。',
      match: (account) => !account.description.toLowerCase().contains(keyword),
      emptyMessage: '没有简介不含「$keyword」的关注',
    );
  }

  Future<void> _scanInactive() async {
    if (_busy) {
      return;
    }
    final days = int.tryParse(_inactiveDays.text.trim());
    if (days == null || days < 1) {
      showAppSnack(context, '请输入有效天数，例如 15', error: true);
      return;
    }
    if (_all.isEmpty) {
      showAppSnack(context, '这个分类还没有关注人', error: true);
      return;
    }
    _scanCancel = false;
    setState(() => _busy = true);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final service = AppScope.of(context).xFollowingService;
    var removed = 0;
    var done = 0;
    var failed = 0;
    var current = '';
    final total = _all.length;
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
              final progress = total == 0 ? 0.0 : done / total;
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  '扫描 $days 天未发帖',
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
                        '$done / $total',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        current.isEmpty ? '准备中…' : '@$current',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
                      ),
                      if (removed > 0 || failed > 0) ...[
                        SizedBox(height: 6.h),
                        Text(
                          '已删除 $removed 人${failed > 0 ? '，失败 $failed 人已跳过' : ''}',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _scanCancel = true;
                      dialogOpen = false;
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
      openDialog();
      for (final account in List<XAccount>.from(_all)) {
        if (_scanCancel) {
          break;
        }
        current = account.username;
        setDialog?.call(() {});
        try {
          final page = await service.fetchPostsPage(account.username, count: 8);
          DateTime? latest;
          for (final post in page.posts) {
            final time = post.publishedAt;
            if (time == null) {
              continue;
            }
            if (latest == null || time.isAfter(latest)) {
              latest = time;
            }
          }
          final inactive = page.posts.isEmpty ||
              (latest != null && latest.isBefore(cutoff));
          if (page.posts.isNotEmpty && latest == null) {
            failed += 1;
          } else if (inactive) {
            await AppScope.of(context).purgeAccounts([account.username]);
            removed += 1;
            if (mounted) {
              setState(() {
                _all.removeWhere(
                  (item) =>
                      item.username.toLowerCase() ==
                      account.username.toLowerCase(),
                );
              });
            }
          }
        } catch (_) {
          failed += 1;
        }
        done += 1;
        setDialog?.call(() {});
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }
      if (!mounted) {
        return;
      }
      if (removed == 0) {
        showAppSnack(
          context,
          _scanCancel
              ? '已停止。还没扫到 $days 天未发帖的账号。'
              : failed > 0
                  ? '没有 $days 天未发帖的账号。失败 $failed 人已跳过。'
                  : '没有 $days 天未发帖的账号',
        );
        return;
      }
      showAppSnack(
        context,
        _scanCancel
            ? '已停止。已删除 $removed 人${failed > 0 ? '，失败 $failed 人已跳过' : ''}'
            : '已删除 $removed 人${failed > 0 ? '，失败 $failed 人已跳过' : ''}',
      );
    } catch (error) {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }
      if (!mounted) {
        return;
      }
      showAppSnack(context, error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _purgeField({
    required TextEditingController controller,
    required String hint,
    required VoidCallback? onDelete,
    String actionLabel = '删除',
    Color? actionColor,
  }) {
    return SizedBox(
      height: 48.h,
      child: AppTextField(
        controller: controller,
        hint: hint,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        onSubmitted: (_) => onDelete?.call(),
        suffix: TextButton(
          onPressed: onDelete,
          style: TextButton.styleFrom(
            foregroundColor: actionColor ?? AppColors.danger,
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            minimumSize: Size(0, 32.h),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            actionLabel,
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
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
              child: Column(
                children: [
                  SizedBox(
                    height: 48.h,
                    child: AppTextField(
                      controller: _query,
                      hint: '搜索 name / username / description',
                      prefixIcon: Icons.search,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(
                        child: _purgeField(
                          controller: _followersMax,
                          hint: '粉丝少于，例如 100',
                          onDelete: _busy ? null : _purgeFollowersLessThan,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _purgeField(
                          controller: _tweetsMax,
                          hint: '推文少于，例如 50',
                          onDelete: _busy ? null : _purgeTweetsLessThan,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _purgeField(
                          controller: _followingMax,
                          hint: '关注少于，例如 100',
                          onDelete: _busy ? null : _purgeFollowingLessThan,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _purgeField(
                          controller: _descKeyword,
                          hint: '描述不含关键字',
                          onDelete: _busy ? null : _purgeDescriptionMissingKeyword,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _purgeField(
                          controller: _inactiveDays,
                          hint: '未发帖天数，例如 15',
                          actionLabel: '扫描',
                          actionColor: AppColors.accent,
                          onDelete: _busy ? null : _scanInactive,
                        ),
                      ),
                    ],
                  ),
                ],
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
    final displayName = account.name.trim().isEmpty ? account.username : account.name;
    final values = <String>[
      '$number',
      '',
      displayName,
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
                          onTap: _busy ? null : () => _delete(account),
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
                            child: XAvatar(url: account.avatarUrl, size: 28),
                          ),
                        ),
                      )
                    : i == 2
                    ? Tooltip(
                        message: '$displayName  @${account.username}',
                        waitDuration: const Duration(milliseconds: 400),
                        child: GestureDetector(
                          onDoubleTap: () async {
                            await copyText(account.username);
                            if (!mounted) {
                              return;
                            }
                            showAppSnack(context, '已复制 username');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '@${account.username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  height: 1.35,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
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
                              color: AppColors.text,
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

