import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../theme.dart';
import 'app_layout.dart';
import 'common.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.page,
    required this.activeCount,
    required this.onSelect,
    required this.child,
  });

  final AppPage page;
  final int activeCount;
  final ValueChanged<AppPage> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppLayout.isCompact(context)) {
      return Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: ColoredBox(
                color: AppColors.bg,
                child: child,
              ),
            ),
          ),
          ColoredBox(
            color: AppColors.sidebar,
            child: SafeArea(
              top: false,
              child: _BottomNav(
                page: page,
                activeCount: activeCount,
                onSelect: onSelect,
              ),
            ),
          ),
        ],
      );
    }
    final desktopBody = Row(
      children: [
        _Sidebar(
          page: page,
          activeCount: activeCount,
          onSelect: onSelect,
        ),
        Expanded(
          child: ColoredBox(
            color: AppColors.bg,
            child: child,
          ),
        ),
      ],
    );
    if (!Platform.isMacOS) {
      return SafeArea(child: desktopBody);
    }
    return Column(
      children: [
        DragToMoveArea(
          child: SizedBox(
            height: 32.h,
            width: double.infinity,
            child: const ColoredBox(color: AppColors.sidebar),
          ),
        ),
        Expanded(child: desktopBody),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.page,
    required this.activeCount,
    required this.onSelect,
  });

  final AppPage page;
  final int activeCount;
  final ValueChanged<AppPage> onSelect;

  int get _index {
    switch (page) {
      case AppPage.xFeed:
        return 0;
      case AppPage.xPhotos:
        return 1;
      case AppPage.xFollowing:
      case AppPage.xAccounts:
        return 2;
      case AppPage.xTrends:
        return 3;
      case AppPage.downloads:
      case AppPage.settings:
      case AppPage.x:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _index,
      backgroundColor: AppColors.sidebar,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textMuted,
      selectedFontSize: 11.sp,
      unselectedFontSize: 11.sp,
      onTap: (index) {
        switch (index) {
          case 0:
            onSelect(AppPage.xFeed);
            break;
          case 1:
            onSelect(AppPage.xPhotos);
            break;
          case 2:
            onSelect(AppPage.xFollowing);
            break;
          case 3:
            onSelect(AppPage.xTrends);
            break;
          case 4:
            onSelect(AppPage.downloads);
            break;
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.dynamic_feed_outlined),
          activeIcon: Icon(Icons.dynamic_feed),
          label: '动态',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.photo_outlined),
          activeIcon: Icon(Icons.photo),
          label: '图片',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people),
          label: '关注',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.local_fire_department_outlined),
          activeIcon: Icon(Icons.local_fire_department),
          label: '热点',
        ),
        BottomNavigationBarItem(
          icon: activeCount > 0
              ? Badge(
                  label: Text('$activeCount'),
                  child: const Icon(Icons.download_outlined),
                )
              : const Icon(Icons.download_outlined),
          activeIcon: activeCount > 0
              ? Badge(
                  label: Text('$activeCount'),
                  child: const Icon(Icons.download),
                )
              : const Icon(Icons.download),
          label: '下载',
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.activeCount,
    required this.onSelect,
  });

  final AppPage page;
  final int activeCount;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180.w,
      color: AppColors.sidebar,
      padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavItem(
            icon: Icons.local_fire_department,
            label: '热点',
            selected: page == AppPage.xTrends,
            color: AppColors.warning,
            onTap: () => onSelect(AppPage.xTrends),
          ),
          _NavItem(
            icon: Icons.dynamic_feed_outlined,
            label: '动态',
            selected: page == AppPage.xFeed,
            color: AppColors.x,
            onTap: () => onSelect(AppPage.xFeed),
          ),
          _NavItem(
            icon: Icons.photo_outlined,
            label: '图片',
            selected: page == AppPage.xPhotos,
            color: AppColors.x,
            onTap: () => onSelect(AppPage.xPhotos),
          ),
          _NavItem(
            icon: Icons.people_outline,
            label: '关注',
            selected: page == AppPage.xFollowing || page == AppPage.xAccounts,
            color: AppColors.x,
            onTap: () => onSelect(AppPage.xFollowing),
          ),
          _NavItem(
            icon: Icons.alternate_email,
            label: '视频',
            selected: page == AppPage.x,
            color: AppColors.x,
            onTap: () => onSelect(AppPage.x),
          ),
          _NavItem(
            icon: Icons.download_outlined,
            label: '下载任务',
            selected: page == AppPage.downloads,
            color: AppColors.success,
            badge: activeCount,
            onTap: () => onSelect(AppPage.downloads),
          ),
          const Spacer(),
          SectionCard(
            padding: EdgeInsets.all(12.w),
            child: Text(
              '请先打开 Clash / VPN，并在设置中填写代理端口（常见 7890 / 7897）。',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp, height: 1.45),
            ),
          ),
          SizedBox(height: 10.h),
          _NavItem(
            icon: Icons.settings_outlined,
            label: '设置与代理',
            selected: page == AppPage.settings,
            color: AppColors.accent,
            onTap: () => onSelect(AppPage.settings),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Material(
        color: selected ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12.w),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.w),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
            child: Row(
              children: [
                Icon(icon, size: 18.w, color: selected ? color : AppColors.textMuted),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.text : AppColors.textMuted,
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999.w),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
   
    const text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
    );
    return Padding(
      padding: AppLayout.headerPadding(context),
      child: compact && trailing != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                SizedBox(height: 12.h),
                trailing!,
              ],
            )
          : Row(
              children: [
                const Expanded(child: text),
                if (trailing != null) trailing!,
              ],
            ),
    );
  }
}
