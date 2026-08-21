import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'models.dart';
import 'screens/categories_page.dart';
import 'screens/downloads_page.dart';
import 'screens/settings_page.dart';
import 'screens/video_page.dart';
import 'screens/x_accounts_page.dart';
import 'screens/x_following_page.dart';
import 'screens/x_photos_page.dart';
import 'screens/x_search_page.dart';
import 'theme.dart';
import 'widgets/app_layout.dart';
import 'widgets/app_scope.dart';
import 'widgets/home_shell.dart';
import 'widgets/x_feed_links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  XFeedLinks.openMention = openXMention;
  XFeedLinks.openSearch = showPostSearch;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  if (!Platform.isMacOS) {
    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
  }
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1024, 768),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'C',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const MediaDownloaderApp());
}

class MediaDownloaderApp extends StatefulWidget {
  const MediaDownloaderApp({super.key});

  @override
  State<MediaDownloaderApp> createState() => _MediaDownloaderAppState();
}

class _MediaDownloaderAppState extends State<MediaDownloaderApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: ScreenUtilInit(
        designSize: Platform.isIOS ? const Size(390, 844) : const Size(1024, 768),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return MaterialApp(
            title: '',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: child,
          );
        },
        child: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  static const _stackOrder = <AppPage>[
    AppPage.search,
    AppPage.xFeed,
    AppPage.xPhotos,
    AppPage.x,
    AppPage.xFollowing,
    AppPage.xAccounts,
    AppPage.downloads,
    AppPage.categories,
    AppPage.settings,
  ];

  AppPage _page = Platform.isIOS ? AppPage.xFeed : AppPage.search;
  AppPage _mediaPage = AppPage.xFeed;
  final Map<AppPage, Widget> _pages = <AppPage, Widget>{};
  final Map<AppPage, GlobalKey> _pageKeys = <AppPage, GlobalKey>{};
  PageController? _mediaPager;

  @override
  void initState() {
    super.initState();
    _ensurePage(_page);
    _ensurePage(AppPage.downloads);
    _ensurePage(AppPage.xFeed);
    _ensurePage(AppPage.xPhotos);
    _ensurePage(AppPage.x);
    _ensurePage(AppPage.xFollowing);
    _mediaPager = PageController();
  }

  @override
  void dispose() {
    _mediaPager?.dispose();
    super.dispose();
  }

  void _select(AppPage page, {bool fromPager = false}) {
    setState(() {
      final media = AppScope.of(context).settings.visibleMedia;
      if (page == AppPage.xFeed && !_page.isMediaHub) {
        page = media.allows(_mediaPage) ? _mediaPage : media.defaultPage;
      }
      if (page.isMediaHub) {
        if (!media.allows(page)) {
          page = media.defaultPage;
        }
        _mediaPage = page;
        _ensurePage(AppPage.xFeed);
        _ensurePage(AppPage.xPhotos);
        _ensurePage(AppPage.x);
      }
      _ensurePage(page);
      _page = page;
    });
    if (fromPager || !page.isMediaHub) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final tabs = AppScope.of(context).settings.visibleMedia.allowedPages;
      final index = tabs.indexOf(_page);
      final pager = _mediaPager;
      if (index < 0 || pager == null || !pager.hasClients) {
        return;
      }
      if (pager.page?.round() != index) {
        pager.jumpToPage(index);
      }
    });
  }

  void _ensurePage(AppPage page) {
    _pages.putIfAbsent(page, () => _createPage(page));
  }

  Widget _shellChild(CategoryMediaConfig media) {
    final compact = AppLayout.isCompact(context);
    final tabs = media.allowedPages;
    final usePager = compact && tabs.length > 1;
    if (usePager) {
      final onMedia = _page.isMediaHub;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: !onMedia,
            child: TickerMode(
              enabled: onMedia,
              child: IgnorePointer(
                ignoring: !onMedia,
                child: PageView(
                  controller: _mediaPager,
                  onPageChanged: (value) {
                    if (!onMedia || value < 0 || value >= tabs.length) {
                      return;
                    }
                    final next = tabs[value];
                    if (next != _page) {
                      _select(next, fromPager: true);
                    }
                  },
                  children: [
                    for (final page in tabs)
                      _KeepAlivePage(
                        key: ValueKey(page),
                        child: _pages[page]!,
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final page in _stackOrder.where(_pages.containsKey))
            if (!page.isMediaHub)
              Offstage(
                key: ValueKey(page),
                offstage: page != _page,
                child: TickerMode(
                  enabled: page == _page,
                  child: IgnorePointer(
                    ignoring: page != _page,
                    child: _pages[page]!,
                  ),
                ),
              ),
        ],
      );
    }
    final stacked = _stackOrder.where(_pages.containsKey).toList();
    final index = stacked.indexOf(_page);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < stacked.length; i++)
          Offstage(
            key: ValueKey(stacked[i]),
            offstage: i != index,
            child: TickerMode(
              enabled: true,
              child: IgnorePointer(
                ignoring: i != index,
                child: _pages[stacked[i]]!,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final media = app.settings.visibleMedia;
    if (_page.isMediaHub && !media.allows(_page)) {
      final next = media.defaultPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _select(next);
      });
    }
    return Scaffold(
      body: HomeShell(
        page: _page,
        activeCount: app.activeCount,
        onSelect: _select,
        child: _shellChild(media),
      ),
    );
  }

  Widget _createPage(AppPage page) {
    final key = _pageKeys.putIfAbsent(page, GlobalKey.new);
    switch (page) {
      case AppPage.xFeed:
        return XFeedPage(key: key);
      case AppPage.xPhotos:
        return XPhotosPage(key: key);
      case AppPage.search:
        return XSearchPage(key: key);
      case AppPage.xFollowing:
        return XFollowingPage(key: key);
      case AppPage.xAccounts:
        return XAccountsPage(key: key);
      case AppPage.x:
        return VideoPage(key: key);
      case AppPage.downloads:
        return DownloadsPage(key: key);
      case AppPage.categories:
        return CategoriesPage(key: key);
      case AppPage.settings:
        return SettingsPage(key: key);
    }
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
