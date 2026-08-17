import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/x_trends_service.dart';
import '../theme.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/home_shell.dart';
import 'x_following_page.dart';

class XTrendsPage extends StatefulWidget {
  const XTrendsPage({super.key});

  @override
  State<XTrendsPage> createState() => _XTrendsPageState();
}

class _XTrendsPageState extends State<XTrendsPage> {
  XTrendRegion _region = XTrendsService.regions.first;
  XTrendSnapshot? _snapshot;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await app.xTrends.fetch(_region);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _updatedLabel() {
    final time = _snapshot?.updatedAt;
    if (time == null) {
      return '实时热搜，点击在应用内搜索。';
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '更新于 ${two(time.hour)}:${two(time.minute)} · 点击在应用内搜索';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '热点',
        
          trailing: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            alignment: WrapAlignment.end,
            children: [
              GhostButton(
                label: '搜索',
                icon: Icons.search,
                onPressed: () => showPostSearch(context),
              ),
              GhostButton(
                label: _loading ? '刷新中' : '刷新',
                icon: Icons.refresh,
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Padding(
          padding: AppLayout.pagePadding(context),
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: XTrendsService.regions.map((region) {
              final selected = region.id == _region.id;
              return Material(
                color: selected ? AppColors.x : AppColors.surface,
                borderRadius: BorderRadius.circular(999.w),
                child: InkWell(
                  onTap: () {
                    if (selected) {
                      return;
                    }
                    setState(() {
                      _region = region;
                      _snapshot = null;
                    });
                    _load();
                  },
                  borderRadius: BorderRadius.circular(999.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    child: Text(
                      region.label,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.black : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return EmptyHint(
        icon: Icons.wifi_off_rounded,
        title: '热点加载失败',
        detail: '$_error\n请确认 VPN/代理已开启后再刷新。',
      );
    }
    final items = _snapshot?.items ?? const <XTrend>[];
    if (items.isEmpty) {
      return const EmptyHint(
        icon: Icons.local_fire_department_outlined,
        title: '暂无热点',
        detail: '换一个地区或稍后再刷新。',
      );
    }
    return GridView.builder(
      padding: AppLayout.pagePadding(context, bottom: 28),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280.w,
        mainAxisSpacing: 12.h,
        crossAxisSpacing: 12.w,
        childAspectRatio: 2.4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _TrendCard(trend: items[index]),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.trend});

  final XTrend trend;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final trend = widget.trend;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? AppColors.surfaceAlt : AppColors.surface,
        borderRadius: BorderRadius.circular(16.w),
        child: InkWell(
          onTap: () => showPostSearch(context, query: trend.name),
          borderRadius: BorderRadius.circular(16.w),
          child: Container(
            padding: EdgeInsets.fromLTRB(14.w, 12.h, 10.w, 12.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.w),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Text(
                  '${trend.rank}',
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                    color: trend.rank <= 3 ? AppColors.warning : AppColors.textMuted,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        trend.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                          height: 1.3,
                          color: trend.name.startsWith('#') ? AppColors.accent : AppColors.text,
                        ),
                      ),
                      if (trend.detail.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          trend.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await copyText(trend.name);
                    if (!mounted) return;
                    showAppSnack(context, '已复制 ${trend.name}');
                  },
                  icon: Icon(Icons.copy, size: 15.w, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
