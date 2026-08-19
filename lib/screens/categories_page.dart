import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  final TextEditingController _purgeTweets = TextEditingController(text: '50');
  final TextEditingController _purgeFollowers = TextEditingController(text: '100');
  Map<String, int> _categoryCounts = <String, int>{};
  List<String> _visibleCategories = <String>[];
  List<String> _categories = <String>[];
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
  }

  @override
  void dispose() {
    _newCategory.dispose();
    _purgeTweets.dispose();
    _purgeFollowers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    final next = app.settings.copy();
    next.visibleCategories = List<String>.from(_visibleCategories);
    next.categories = List<String>.from(_categories);
    await app.saveSettings(next);
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
    final ok = await _confirmClear(
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
    final ok = await _confirmClear(
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
    final ok = await _confirmClear(
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
    final ok = await _confirmClear(
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
    await _save();
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
        });
        _loadCategories();
      });
    }
    if (!visible) {
      _loaded = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          trailing: Navigator.of(context).canPop()
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
                      final exporting = _exportingCategory == key;
                      final busy = _purging || _syncingCategory != null;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                Switch(
                                  value: on,
                                  activeThumbColor: AppColors.accent,
                                  onChanged: (value) =>
                                      _toggleCategory(key, value),
                                ),
                              ],
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _viewCategory(key),
                                  child: Text(
                                    '查看',
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ),
                                TextButton(
                                  onPressed: busy || _exportingCategory != null
                                      ? null
                                      : () => _exportCategory(key),
                                  child: Text(
                                    exporting ? '导出中' : '导出Excel',
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ),
                                TextButton(
                                  onPressed: busy ? null : () => _clearCategory(key),
                                  child: Text(
                                    '清空',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: busy
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
                              ],
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
