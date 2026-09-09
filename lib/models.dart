enum AppPage {
  xFeed,
  xPhotos,
  xFollowing,
  xAccounts,
  search,
  x,
  downloads,
  categories,
  settings;

  bool get isMediaHub =>
      this == AppPage.xFeed || this == AppPage.xPhotos || this == AppPage.x;
}

enum DownloadKind { x }

enum TaskStatus { queued, running, done, failed, canceled }

enum VideoQuality { best, p1080, p720, p480, audio }

class CategoryMediaConfig {
  const CategoryMediaConfig({
    this.posts = true,
    this.photos = true,
    this.videos = true,
  });

  final bool posts;
  final bool photos;
  final bool videos;

  static const all = CategoryMediaConfig();

  bool get isEmpty => !posts && !photos && !videos;

  List<AppPage> get allowedPages => <AppPage>[
        if (posts) AppPage.xFeed,
        if (photos) AppPage.xPhotos,
        if (videos) AppPage.x,
      ];

  AppPage get defaultPage =>
      allowedPages.isEmpty ? AppPage.xFeed : allowedPages.first;

  bool allows(AppPage page) {
    switch (page) {
      case AppPage.xFeed:
        return posts;
      case AppPage.xPhotos:
        return photos;
      case AppPage.x:
        return videos;
      default:
        return true;
    }
  }

  CategoryMediaConfig copyWith({bool? posts, bool? photos, bool? videos}) {
    return CategoryMediaConfig(
      posts: posts ?? this.posts,
      photos: photos ?? this.photos,
      videos: videos ?? this.videos,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'posts': posts,
      'photos': photos,
      'videos': videos,
    };
  }

  static CategoryMediaConfig fromJson(dynamic raw) {
    if (raw is! Map) {
      return const CategoryMediaConfig();
    }
    return CategoryMediaConfig(
      posts: raw['posts'] as bool? ?? true,
      photos: raw['photos'] as bool? ?? true,
      videos: raw['videos'] as bool? ?? true,
    );
  }
}

class MediaLoadConfig {
  static const defaultHours = 72;
  static const defaultPerUser = 5;
  static const defaultMinLikes = 100;
  static const defaultMinDurationMinutes = 2;
  static const defaultMaxDurationMinutes = 30;

  MediaLoadConfig({
    int hours = defaultHours,
    int perUser = defaultPerUser,
    int minLikes = defaultMinLikes,
    int minDurationMinutes = 0,
    int maxDurationMinutes = 0,
  })  : hours = _clamp(hours, 1, 720, defaultHours),
        perUser = _clamp(perUser, 1, 50, defaultPerUser),
        minLikes = _clamp(minLikes, 0, 100000000, defaultMinLikes),
        minDurationMinutes = _clamp(minDurationMinutes, 0, 600, 0),
        maxDurationMinutes = _clamp(maxDurationMinutes, 0, 600, 0);

  int hours;
  int perUser;
  int minLikes;
  int minDurationMinutes;
  int maxDurationMinutes;

  bool allowsLikes(int likes) => minLikes <= 0 || likes >= minLikes;

  bool allowsDuration(int seconds) {
    final minSec = minDurationMinutes * 60;
    var maxSec = maxDurationMinutes * 60;
    if (minSec > 0 && maxSec > 0 && maxSec < minSec) {
      maxSec = minSec;
    }
    if (minSec <= 0 && maxSec <= 0) {
      return true;
    }
    if (seconds <= 0) {
      return minSec <= 0;
    }
    if (minSec > 0 && seconds < minSec) {
      return false;
    }
    if (maxSec > 0 && seconds > maxSec) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'hours': hours,
      'perUser': perUser,
      'minLikes': minLikes,
      'minDurationMinutes': minDurationMinutes,
      'maxDurationMinutes': maxDurationMinutes,
    };
  }

  MediaLoadConfig copy() {
    return MediaLoadConfig(
      hours: hours,
      perUser: perUser,
      minLikes: minLikes,
      minDurationMinutes: minDurationMinutes,
      maxDurationMinutes: maxDurationMinutes,
    );
  }

  static MediaLoadConfig fromJson(
    dynamic raw, {
    MediaLoadConfig? fallback,
  }) {
    final base = fallback ?? MediaLoadConfig();
    if (raw is! Map) {
      return MediaLoadConfig(
        hours: base.hours,
        perUser: base.perUser,
        minLikes: base.minLikes,
        minDurationMinutes: base.minDurationMinutes,
        maxDurationMinutes: base.maxDurationMinutes,
      );
    }
    return MediaLoadConfig(
      hours: _read(raw['hours'], base.hours),
      perUser: _read(raw['perUser'], base.perUser),
      minLikes: _read(raw['minLikes'], base.minLikes),
      minDurationMinutes: _read(raw['minDurationMinutes'], base.minDurationMinutes),
      maxDurationMinutes: _read(raw['maxDurationMinutes'], base.maxDurationMinutes),
    );
  }

  static int _read(dynamic raw, int fallback) {
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse('$raw') ?? fallback;
  }

  static int _clamp(int value, int min, int max, int fallback) {
    if (value < min || value > max) {
      if (value < min) {
        return min;
      }
      if (value > max) {
        return max;
      }
      return fallback;
    }
    return value;
  }
}

class AppSettings {
  AppSettings({
    this.proxyEnabled = true,
    this.proxyHost = '127.0.0.1',
    this.proxyPort = '7890',
    this.ffmpegPath = '/opt/homebrew/bin/ffmpeg',
    this.downloadDir = '',
    MediaLoadConfig? photoLoad,
    MediaLoadConfig? videoLoad,
    List<String>? xFollowing,
    List<String>? visibleCategories,
    List<String>? categories,
    List<String>? hiddenDownloads,
    Map<String, CategoryMediaConfig>? categoryMedia,
  })  : photoLoad = photoLoad?.copy() ?? MediaLoadConfig(),
        videoLoad = videoLoad?.copy() ??
            MediaLoadConfig(
              minDurationMinutes: MediaLoadConfig.defaultMinDurationMinutes,
              maxDurationMinutes: MediaLoadConfig.defaultMaxDurationMinutes,
            ),
        xFollowing = xFollowing == null
            ? <String>[]
            : List<String>.from(xFollowing),
        visibleCategories = visibleCategories == null
            ? <String>[]
            : List<String>.from(visibleCategories),
        categories = categories == null
            ? <String>[]
            : List<String>.from(categories),
        hiddenDownloads = hiddenDownloads == null
            ? <String>[]
            : List<String>.from(hiddenDownloads),
        categoryMedia = categoryMedia == null
            ? <String, CategoryMediaConfig>{}
            : Map<String, CategoryMediaConfig>.from(categoryMedia);

  bool proxyEnabled;
  String proxyHost;
  String proxyPort;
  String ffmpegPath;
  String downloadDir;
  MediaLoadConfig photoLoad;
  MediaLoadConfig videoLoad;
  List<String> xFollowing;
  List<String> visibleCategories;
  List<String> categories;
  List<String> hiddenDownloads;
  Map<String, CategoryMediaConfig> categoryMedia;

  String get proxyAddress {
    final host = proxyHost.trim();
    final port = proxyPort.trim();
    if (host.isEmpty || port.isEmpty) {
      return '';
    }
    return '$host:$port';
  }

  String? get proxyUrl {
    if (!proxyEnabled) {
      return null;
    }
    final address = proxyAddress;
    if (address.isEmpty) {
      return null;
    }
    return 'http://$address';
  }

  bool showsCategory(String category) {
    final key = category.trim().toLowerCase();
    return visibleCategories.any((item) => item.trim().toLowerCase() == key);
  }

  CategoryMediaConfig mediaFor(String category) {
    final key = category.trim().toLowerCase();
    return categoryMedia[key] ?? CategoryMediaConfig.all;
  }

  /// 当前打开分类所支持的内容类型（并集）。未打开任何分类时默认全部支持。
  CategoryMediaConfig get visibleMedia {
    final keys = visibleCategories
        .map((item) => item.trim().toLowerCase())
        .toList();
    if (keys.isEmpty) {
      return CategoryMediaConfig.all;
    }
    var posts = false;
    var photos = false;
    var videos = false;
    for (final key in keys) {
      final media = mediaFor(key);
      posts = posts || media.posts;
      photos = photos || media.photos;
      videos = videos || media.videos;
    }
    if (!posts && !photos && !videos) {
      return CategoryMediaConfig.all;
    }
    return CategoryMediaConfig(posts: posts, photos: photos, videos: videos);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'proxyEnabled': proxyEnabled,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'ffmpegPath': ffmpegPath,
      'downloadDir': downloadDir,
      'photoLoad': photoLoad.toJson(),
      'videoLoad': videoLoad.toJson(),
      'xFollowing': xFollowing,
      'visibleCategories': visibleCategories,
      'categories': categories,
      'hiddenDownloads': hiddenDownloads,
      'categoryMedia': categoryMedia.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  static int _int(dynamic raw, int fallback, {int min = 1, int max = 9999}) {
    final parsed = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  static List<String> _stringList(dynamic raw, {bool keepEmpty = false}) {
    return (raw as List<dynamic>? ?? <dynamic>[])
        .map((item) => '$item'.trim().toLowerCase())
        .where((item) => keepEmpty || item.isNotEmpty)
        .toList();
  }

  static Map<String, CategoryMediaConfig> _mediaMap(dynamic raw) {
    if (raw is! Map) {
      return <String, CategoryMediaConfig>{};
    }
    return raw.map<String, CategoryMediaConfig>((key, value) {
      return MapEntry(
        '$key'.trim().toLowerCase(),
        CategoryMediaConfig.fromJson(value),
      );
    });
  }

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      proxyEnabled: json['proxyEnabled'] as bool? ?? true,
      proxyHost: json['proxyHost'] as String? ?? '127.0.0.1',
      proxyPort: json['proxyPort'] as String? ?? '7890',
      ffmpegPath: json['ffmpegPath'] as String? ?? '/opt/homebrew/bin/ffmpeg',
      downloadDir: json['downloadDir'] as String? ?? '',
      photoLoad: MediaLoadConfig.fromJson(
        json['photoLoad'],
        fallback: MediaLoadConfig(
          hours: _int(json['feedHours'], MediaLoadConfig.defaultHours, min: 1, max: 720),
          perUser: _int(
            json['feedPerUser'],
            MediaLoadConfig.defaultPerUser,
            min: 1,
            max: 50,
          ),
        ),
      ),
      videoLoad: MediaLoadConfig.fromJson(
        json['videoLoad'],
        fallback: MediaLoadConfig(
          hours: _int(json['feedHours'], MediaLoadConfig.defaultHours, min: 1, max: 720),
          perUser: _int(
            json['feedPerUser'],
            MediaLoadConfig.defaultPerUser,
            min: 1,
            max: 50,
          ),
          minDurationMinutes: MediaLoadConfig.defaultMinDurationMinutes,
          maxDurationMinutes: MediaLoadConfig.defaultMaxDurationMinutes,
        ),
      ),
      xFollowing: (json['xFollowing'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      visibleCategories: _stringList(json['visibleCategories'], keepEmpty: true),
      categories: _stringList(json['categories']),
      hiddenDownloads: (json['hiddenDownloads'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      categoryMedia: _mediaMap(json['categoryMedia']),
    );
  }

  AppSettings copy() {
    return AppSettings.fromJson(toJson());
  }
}

class VideoInfo {
  VideoInfo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.webpageUrl,
    required this.extractor,
  });

  final String id;
  final String title;
  final String uploader;
  final int duration;
  final String thumbnail;
  final String webpageUrl;
  final String extractor;

  String get durationLabel {
    if (duration <= 0) {
      return '--:--';
    }
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }
}

class XTrend {
  XTrend({
    required this.rank,
    required this.name,
    required this.searchUrl,
    this.detail = '',
  });

  final int rank;
  final String name;
  final String searchUrl;
  final String detail;
}

class XTrendSnapshot {
  XTrendSnapshot({
    required this.regionId,
    required this.updatedAt,
    required this.items,
  });

  final String regionId;
  final DateTime? updatedAt;
  final List<XTrend> items;
}

class XTrendRegion {
  const XTrendRegion(this.id, this.label, this.path);

  final String id;
  final String label;
  final String path;
}

class XAccount {
  XAccount({
    required this.username,
    required this.name,
    required this.description,
    required this.avatarUrl,
    required this.profileUrl,
    required this.followers,
    required this.following,
    required this.tweets,
    this.id = '',
    this.protected = false,
    this.updatedAt = 0,
    this.lastPostAt = 0,
    this.category = '',
    this.special = false,
  });

  final String id;
  final String username;
  final String name;
  final String description;
  final String avatarUrl;
  final String profileUrl;
  final int followers;
  final int following;
  final int tweets;
  final bool protected;
  final int updatedAt;
  final int lastPostAt;
  final String category;
  final bool special;

  static const sexCategoryKey = 'sex';
  static const sexCategoryLabel = '经典';

  String get categoryKey {
    final key = category.trim().toLowerCase();
    if (key == sexCategoryLabel) {
      return sexCategoryKey;
    }
    return key;
  }

  static String categoryLabel(String category) {
    final key = category.trim();
    if (key.isEmpty) {
      return '未分类';
    }
    if (key.toLowerCase() == sexCategoryKey || key == sexCategoryLabel) {
      return sexCategoryLabel;
    }
    return key;
  }

  XAccount copyWith({String? category, bool? special, int? lastPostAt}) {
    return XAccount(
      id: id,
      username: username,
      name: name,
      description: description,
      avatarUrl: avatarUrl,
      profileUrl: profileUrl,
      followers: followers,
      following: following,
      tweets: tweets,
      protected: protected,
      updatedAt: updatedAt,
      lastPostAt: lastPostAt ?? this.lastPostAt,
      category: category ?? this.category,
      special: special ?? this.special,
    );
  }
}

enum XMediaKind { photo, video, gif }

class XMedia {
  XMedia({
    required this.kind,
    required this.url,
    this.previewUrl = '',
    this.width = 0,
    this.height = 0,
    this.duration = 0,
  });

  final XMediaKind kind;
  final String url;
  final String previewUrl;
  final int width;
  final int height;
  final double duration;

  bool get isVideo => kind == XMediaKind.video || kind == XMediaKind.gif;

  static String twitterSizedUrl(String raw, String size) {
    final url = raw.trim();
    if (url.isEmpty) {
      return url;
    }
    var next = url.replaceAll(
      RegExp(r':(orig|large|medium|small|thumb|360x360|900x900)$'),
      ':$size',
    );
    if (RegExp(r'name=').hasMatch(next)) {
      next = next.replaceAll(
        RegExp(r'name=(orig|large|medium|small|thumb|360x360|900x900)'),
        'name=$size',
      );
    }
    return next;
  }

  String get originalUrl {
    final raw = url.trim();
    if (raw.isEmpty || kind != XMediaKind.photo) {
      return raw;
    }
    var next = twitterSizedUrl(raw, 'orig');
    if (next.contains('pbs.twimg.com') || next.contains('twimg.com')) {
      if (!RegExp(r'name=').hasMatch(next) && !RegExp(r':orig$').hasMatch(next)) {
        next = next.contains('?') ? '$next&name=orig' : '$next?name=orig';
      }
    }
    return next;
  }

  String get listUrl {
    final raw = previewUrl.trim().isNotEmpty ? previewUrl : url;
    return twitterSizedUrl(raw, 'medium');
  }

  String get durationLabel {
    if (durationSeconds <= 0) {
      return '';
    }
    final total = durationSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return '$minutes:${two(seconds)}';
  }

  int get durationSeconds { 
    final raw = duration;
    if (raw <= 0) {
      return 0;
    }
    if (raw > 3600) {
      return (raw / 1000).round();
    }
    return raw.round();
  }
}

class XPost {
  XPost({
    required this.id,
    required this.username,
    required this.text,
    required this.url,
    this.publishedAt,
    this.media = const <XMedia>[],
    this.translation = '',
    this.lang = '',
    this.avatarUrl = '',
    this.authorName = '',
    this.likes = 0,
    this.views = 0,
  });

  final String id;
  final String username;
  final String text;
  final String url;
  final DateTime? publishedAt;
  final List<XMedia> media;
  final String translation;
  final String lang;
  final String avatarUrl;
  final String authorName;
  final int likes;
  final int views;

  String get displayName {
    final name = authorName.trim();
    return name.isEmpty ? username : name;
  }

  XPost copyWith({
    String? avatarUrl,
    String? authorName,
  }) {
    return XPost(
      id: id,
      username: username,
      text: text,
      url: url,
      publishedAt: publishedAt,
      media: media,
      translation: translation,
      lang: lang,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      authorName: authorName ?? this.authorName,
      likes: likes,
      views: views,
    );
  }

  bool get hasTranslation {
    final translated = translation.trim();
    return translated.isNotEmpty && translated != text.trim();
  }

  bool get isChinese {
    final code = lang.trim().toLowerCase();
    if (code == 'zh' || code.startsWith('zh-')) {
      return true;
    }
    if (code.isNotEmpty) {
      return false;
    }
    return _looksLikeChinese(text);
  }

  String get displayText {
    final translated = translation.trim();
    return translated.isEmpty ? text : translated;
  }

  bool get hasPhotos => media.any((item) => item.kind == XMediaKind.photo);

  bool get hasVideo => media.any((item) => item.isVideo);

  int get photoCount => media.where((item) => item.kind == XMediaKind.photo).length;

  static int latestMillis(Iterable<XPost> posts) {
    var latest = 0;
    for (final post in posts) {
      final time = post.publishedAt;
      if (time == null) {
        continue;
      }
      final millis = time.millisecondsSinceEpoch;
      if (millis > latest) {
        latest = millis;
      }
    }
    return latest;
  }
}

class XReplyPage {
  XReplyPage({
    required this.replies,
    this.cursor,
  });

  final List<XPost> replies;
  final String? cursor;
}

class XPostPage {
  const XPostPage({
    required this.posts,
    this.cursor,
  });

  final List<XPost> posts;
  final String? cursor;
}

class XFeedBatch {
  const XFeedBatch({
    this.posts = const <XPost>[],
    this.cursors = const <String, String>{},
  });

  final List<XPost> posts;
  final Map<String, String> cursors;

  bool get hasMore => cursors.isNotEmpty;
}

class XAccountPage {
  const XAccountPage({
    required this.accounts,
    this.cursor,
  });

  final List<XAccount> accounts;
  final String? cursor;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.sourceUrl,
    this.status = TaskStatus.queued,
    this.progress = 0,
    this.savePath = '',
    this.error = '',
    this.speed = '',
  });

  final String id;
  final DownloadKind kind;
  final String title;
  final String sourceUrl;
  TaskStatus status;
  double progress;
  String savePath;
  String error;
  String speed;
  bool alreadyDownloaded = false;
}

bool _looksLikeChinese(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  text = text
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'@\w+'), ' ')
      .replaceAll(RegExp(r'#\w+'), ' ');
  final han = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]').allMatches(text).length;
  if (han == 0) {
    return false;
  }
  final kana = RegExp(r'[\u3040-\u30ff]').allMatches(text).length;
  if (kana >= 3) {
    return false;
  }
  final hangul = RegExp(r'[\uac00-\ud7af]').allMatches(text).length;
  if (hangul >= 3) {
    return false;
  }
  final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
  return han >= latin;
}

String qualityLabel(VideoQuality quality) {
  switch (quality) {
    case VideoQuality.best:
      return '最佳画质';
    case VideoQuality.p1080:
      return '1080p';
    case VideoQuality.p720:
      return '720p';
    case VideoQuality.p480:
      return '480p';
    case VideoQuality.audio:
      return '仅音频';
  }
}

