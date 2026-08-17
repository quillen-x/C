import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import 'x_following_page.dart';

class XAccountsPage extends StatefulWidget {
  const XAccountsPage({super.key});

  @override
  State<XAccountsPage> createState() => _XAccountsPageState();
}

class _XAccountsPageState extends State<XAccountsPage> {
  static const _rowHeight = 36.0;
  static const _headerHeight = 38.0;

  final TextEditingController _query = TextEditingController();
  final ScrollController _hScroll = ScrollController();
  List<XAccount> _all = <XAccount>[];
  bool _loading = false;
  String? _error;
  String _sortKey = 'name';
  bool _sortAsc = true;

  static const _columns = <_SheetColumn>[
    _SheetColumn('#', 56, align: TextAlign.right),
    _SheetColumn('avatar', 52),
    _SheetColumn('name', 120),
    _SheetColumn('category', 88),
    _SheetColumn('description', 280, wrap: true),
    _SheetColumn('followers', 88, align: TextAlign.right),
    _SheetColumn('following', 88, align: TextAlign.right),
    _SheetColumn('tweets', 80, align: TextAlign.right),
    _SheetColumn('updated_at', 168),
  ];

  static double get _tableWidth {
    return _columns.fold<double>(0, (sum, column) => sum + column.width);
  }

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
      final rows = await AppScope.of(context).accountDb.loadAll();
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
    final settings = AppScope.of(context).settings;
    Iterable<XAccount> source = _all.where(
      (account) => settings.showsCategory(account.category),
    );
    final rows = query.isEmpty
        ? List<XAccount>.from(source)
        : source.where((account) {
            return account.name.toLowerCase().contains(query) ||
                account.description.toLowerCase().contains(query) ||
                account.username.toLowerCase().contains(query) ||
                account.category.toLowerCase().contains(query);
          }).toList();
    rows.sort((a, b) {
      final compared = _compare(a, b);
      return _sortAsc ? compared : -compared;
    });
    return rows;
  }

  List<String> get _categories {
    final names = <String>{
      ...AppScope.of(context).settings.categories,
    };
    for (final account in _all) {
      final category = account.category.trim();
      if (category.isNotEmpty) {
        names.add(category);
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  int _compare(XAccount a, XAccount b) {
    switch (_sortKey) {
      case 'category':
        return a.category.toLowerCase().compareTo(b.category.toLowerCase());
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
  }

  Future<void> _editCategory(XAccount account) async {
    final controller = TextEditingController(text: account.category);
    final known = _categories;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('分类'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.text),
                  cursorColor: AppColors.accent,
                  decoration: const InputDecoration(
                    hintText: '例如 sex',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  onSubmitted: (value) => Navigator.pop(context, value),
                ),
                if (known.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: known
                        .map(
                          (item) => ActionChip(
                            label: Text(item),
                            onPressed: () => Navigator.pop(context, item),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('清除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) {
      return;
    }
    final category = result.trim();
    final app = AppScope.of(context);
    await app.accountDb.updateCategory(account.username, category);
    await app.ensureCategory(category);
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _all.indexWhere(
        (item) => item.username.toLowerCase() == account.username.toLowerCase(),
      );
      if (index >= 0) {
        _all[index] = _all[index].copyWith(category: category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '关注列表',
          trailing: GhostButton(
            label: _loading ? '刷新中' : '刷新',
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
          ),
        ),
        Padding(
          padding: AppLayout.pagePadding(context, bottom: 12),
          child: AppTextField(
            controller: _query,
            hint: '搜索 name / description / category',
            prefixIcon: Icons.search,
          ),
        ),
        Padding(
          padding: AppLayout.pagePadding(context, bottom: 8),
          child: Text(
            _statusText(rows),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
          ),
        ),
        Expanded(child: _buildBody(rows)),
      ],
    );
  }

  Widget _buildBody(List<XAccount> rows) {
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _all.isEmpty) {
      return EmptyHint(
        icon: Icons.storage_outlined,
        title: '读取数据库失败',
        detail: '$_error',
      );
    }
    if (_all.isEmpty) {
      return const EmptyHint(
        icon: Icons.people_outline,
        title: '数据库还是空的',
        detail: '先在「关注」同步资料，或从别人的关注列表里关注账号。',
      );
    }
    if (rows.isEmpty) {
      final enabled = AppScope.of(context).settings.visibleCategories;
      return EmptyHint(
        icon: Icons.search_off,
        title: enabled.isEmpty ? '还没有打开任何分类' : '没有匹配的记录',
        detail: enabled.isEmpty
            ? '到「设置 → 关注分类」打开要展示的类别。'
            : '换个关键词再试，或到设置里打开更多分类。',
      );
    }
    final padding = AppLayout.pagePadding(context, bottom: 16);
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
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
      account.category,
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
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Tooltip(
                            message: '打开主页',
                            child: InkWell(
                              onTap: () => showAccountHome(context, account),
                              customBorder: const CircleBorder(),
                              child: _Avatar(url: account.avatarUrl, size: 22),
                            ),
                          ),
                        ),
                      )
                    : i == 3
                    ? Tooltip(
                        message: '点击修改分类',
                        child: InkWell(
                          onTap: () => _editCategory(account),
                          child: Text(
                            account.category.trim().isEmpty
                                ? '未分类'
                                : account.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.sp,
                              height: 1.35,
                              color: account.category.trim().isEmpty
                                  ? AppColors.textMuted
                                  : AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : Tooltip(
                        message: values[i].isEmpty || _columns[i].wrap
                            ? ''
                            : values[i],
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

  String _statusText(List<XAccount> rows) {
    final enabled = AppScope.of(context).settings.visibleCategories;
    if (enabled.isEmpty) {
      return '设置里还没打开分类 · 共 ${_all.length} 人';
    }
    final names = enabled.map(XAccount.categoryLabel).join('、');
    return '已打开 $names · 显示 ${rows.length} / ${_all.length} 人';
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

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
