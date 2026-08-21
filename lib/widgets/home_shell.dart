import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../theme.dart';
import 'app_layout.dart';
import 'app_scope.dart';
import 'phone_routes.dart';

class _NavAssets {
  static const search = 'assets/images/search.svg';
  static const media = 'assets/images/media.svg';
  static const following = 'assets/images/single_focus.svg';
  static const download = 'assets/images/download.svg';
  static const category = 'assets/images/focus.svg';
  static const setting = 'assets/images/setting.svg';
}

class _NavSvg extends StatelessWidget {
  const _NavSvg({
    required this.asset,
    this.color,
    this.size = 18,
  });

  final String asset;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? AppColors.textMuted;
    return SvgPicture.asset(
      asset,
      width: size.w,
      height: size.w,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );
  }
}

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
    final compact = AppLayout.isCompact(context);
    final media = AppScope.of(context).settings.visibleMedia;
    final showSwitcher = page.isMediaHub && media.allowedPages.length > 1;
    if (compact) {
      return Scaffold(
        backgroundColor: AppColors.navBar,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (page.isMediaHub)
                _PhoneMediaTopBar(
                  page: page,
                  allowed: media,
                  onSelect: onSelect,
                ),
              Expanded(
                child: ColoredBox(
                  color: AppColors.bg,
                  child: child,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ColoredBox(
          color: AppColors.navBar,
          child: SafeArea(
            top: false,
            child: _BottomNav(
              page: page,
              activeCount: activeCount,
              onSelect: onSelect,
            ),
          ),
        ),
      );
    }
    final content = Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 16.h,
          child: IgnorePointer(
            ignoring: !showSwitcher,
            child: Opacity(
              opacity: showSwitcher ? 1 : 0,
              child: Center(
                child: _MediaSubTabs(
                  page: page.isMediaHub ? page : media.defaultPage,
                  allowed: media,
                  onSelect: onSelect,
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
            child: content,
          ),
        ),
      ],
    );
    if (!Platform.isMacOS) {
      return SafeArea(child: desktopBody);
    }
    return desktopBody;
  }
}

class _BottomNav extends StatefulWidget {
  const _BottomNav({
    required this.page,
    required this.activeCount,
    required this.onSelect,
  });

  final AppPage page;
  final int activeCount;
  final ValueChanged<AppPage> onSelect;

  @override
  State<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<_BottomNav> with SingleTickerProviderStateMixin {
  late final TabController _controller;

  int get _index {
    switch (widget.page) {
      case AppPage.xFeed:
      case AppPage.xPhotos:
      case AppPage.x:
      case AppPage.search:
        return 0;
      case AppPage.xFollowing:
      case AppPage.xAccounts:
      case AppPage.categories:
        return 1;
      case AppPage.downloads:
        return 2;
      case AppPage.settings:
        return 3;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this, initialIndex: _index);
  }

  @override
  void didUpdateWidget(covariant _BottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _index;
    if (_controller.index != next) {
      _controller.index = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    switch (index) {
      case 0:
        if (!widget.page.isMediaHub) {
          widget.onSelect(AppPage.xFeed);
        }
        break;
      case 1:
        widget.onSelect(AppPage.xFollowing);
        break;
      case 2:
        widget.onSelect(AppPage.downloads);
        break;
      case 3:
        widget.onSelect(AppPage.settings);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 22.0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: TabBar(
        controller: _controller,
        onTap: _onTap,
        indicator: const BoxDecoration(),
        dividerColor: Colors.transparent,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          fontFamily: AppFonts.family,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w500,
          fontFamily: AppFonts.family,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        tabs: [
          const Tab(
            height: 56,
            iconMargin: EdgeInsets.only(bottom: 4),
            icon: _NavSvg(asset: _NavAssets.media, size: iconSize),
            text: '动态',
          ),
          const Tab(
            height: 56,
            iconMargin: EdgeInsets.only(bottom: 4),
            icon: _NavSvg(asset: _NavAssets.following, size: iconSize),
            text: '关注',
          ),
          Tab(
            height: 56,
            iconMargin: const EdgeInsets.only(bottom: 4),
            icon: widget.activeCount > 0
                ? Badge(
                    label: Text('${widget.activeCount}'),
                    child: const _NavSvg(asset: _NavAssets.download, size: iconSize),
                  )
                : const _NavSvg(asset: _NavAssets.download, size: iconSize),
            text: '下载',
          ),
          const Tab(
            height: 56,
            iconMargin: EdgeInsets.only(bottom: 4),
            icon: _NavSvg(asset: _NavAssets.setting, size: iconSize),
            text: '设置',
          ),
        ],
      ),
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
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isMacOS)
            const DragToMoveArea(
              child: SizedBox(height: 28, width: double.infinity),
            ),
          _NavItem(
            icon: _NavAssets.search,
            label: '搜索',
            selected: page == AppPage.search,
            color: AppColors.accent,
            onTap: () => onSelect(AppPage.search),
          ),
          _NavItem(
            icon: _NavAssets.media,
            label: '动态',
            selected: page.isMediaHub,
            color: AppColors.accent,
            onTap: () {
              if (!page.isMediaHub) {
                onSelect(AppPage.xFeed);
              }
            },
          ),
          _NavItem(
            icon: _NavAssets.following,
            label: '关注',
            selected: page == AppPage.xFollowing || page == AppPage.xAccounts,
            color: AppColors.accent,
            onTap: () => onSelect(AppPage.xFollowing),
          ),
          _NavItem(
            icon: _NavAssets.download,
            label: '下载',
            selected: page == AppPage.downloads,
            color: AppColors.accent,
            badge: activeCount,
            onTap: () => onSelect(AppPage.downloads),
          ),
          const Spacer(),
          SizedBox(height: 10.h),
          _NavItem(
            icon: _NavAssets.category,
            label: '分类',
            selected: page == AppPage.categories,
            color: AppColors.accent,
            onTap: () => onSelect(AppPage.categories),
          ),
          _NavItem(
            icon: _NavAssets.setting,
            label: '设置',
            selected: page == AppPage.settings,
            color: AppColors.accent,
            onTap: () => onSelect(AppPage.settings),
          ),
        ],
      ),
    );
  }
}

class _PhoneMediaTopBar extends StatelessWidget {
  const _PhoneMediaTopBar({
    required this.page,
    required this.allowed,
    required this.onSelect,
  });

  static const _indicator = Color(0xFFFF3B5C);

  final AppPage page;
  final CategoryMediaConfig allowed;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.navBar,
      child: SizedBox(
        height: 48.h,
        child: Row(
          children: [
            SizedBox(width: 48.w),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (allowed.posts)
                    _tab(label: '动态', target: AppPage.xFeed),
                  if (allowed.photos)
                    _tab(label: '图片', target: AppPage.xPhotos),
                  if (allowed.videos)
                    _tab(label: '视频', target: AppPage.x),
                ],
              ),
            ),
            SizedBox(
              width: 48.w,
              height: 48.h,
              child: const PhoneSearchButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab({
    required String label,
    required AppPage target,
  }) {
    final selected = page == target;
    return GestureDetector(
      onTap: selected ? null : () => onSelect(target),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: selected ? 18.sp : 16.sp,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppColors.text : AppColors.textMuted,
                height: 1.1,
              ),
            ),
            SizedBox(height: 5.h),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 18.w : 0,
              height: 3.h,
              decoration: BoxDecoration(
                color: selected ? _indicator : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaSubTabs extends StatelessWidget {
  const _MediaSubTabs({
    required this.page,
    required this.allowed,
    required this.onSelect,
  });

  final AppPage page;
  final CategoryMediaConfig allowed;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999.w),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999.w),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18.w,
                offset: Offset(0, 8.h),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowed.posts)
                _item(
                  label: '动态',
                  icon: Icons.dynamic_feed_outlined,
                  target: AppPage.xFeed,
                ),
              if (allowed.photos)
                _item(
                  label: '图片',
                  icon: Icons.photo_outlined,
                  target: AppPage.xPhotos,
                ),
              if (allowed.videos)
                _item(
                  label: '视频',
                  icon: Icons.smart_display_outlined,
                  target: AppPage.x,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item({
    required String label,
    required IconData icon,
    required AppPage target,
  }) {
    final selected = page == target;
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.22) : Colors.transparent,
      borderRadius: BorderRadius.circular(999.w),
      child: InkWell(
        onTap: selected ? null : () => onSelect(target),
        borderRadius: BorderRadius.circular(999.w),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16.w,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              SizedBox(width: 6.w),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
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

  final String icon;
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
                _NavSvg(
                  asset: icon,
                  color: selected ? color : AppColors.textMuted,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? color : AppColors.textMuted,
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
    this.trailing,
  });

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final drag = Platform.isMacOS
        ? const DragToMoveArea(child: SizedBox(height: 28, width: double.infinity))
        : const SizedBox.shrink();
    final header = trailing == null
        ? drag
        : Row(
            children: [
              Expanded(child: drag),
              trailing!,
            ],
          );
    return Padding(
      padding: AppLayout.headerPadding(context),
      child: header,
    );
  }
}
