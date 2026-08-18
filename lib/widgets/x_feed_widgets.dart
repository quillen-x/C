import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models.dart';
import '../services/x_following_service.dart';
import '../theme.dart';
import 'app_layout.dart';
import 'app_scope.dart';
import 'common.dart';
import 'media_viewer.dart';
import 'x_feed_links.dart';

void showPostComments(BuildContext context, XPost post) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _CommentsDialog(post: post);
    },
  );
}

class _CommentsDialog extends StatefulWidget {
  const _CommentsDialog({required this.post});

  final XPost post;

  @override
  State<_CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<_CommentsDialog> {
  static const _maxPages = 30;

  final List<XPost> _replies = <XPost>[];
  final ScrollController _scroll = ScrollController();
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  int _pages = 0;

  bool get _hasMore {
    final cursor = _cursor;
    return cursor != null && cursor.isNotEmpty && _pages < _maxPages;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_hasMore || _loadingMore || _moreError != null) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 120.h) {
      _load(more: true);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() {
        _loadingMore = true;
        _moreError = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _moreError = null;
      });
    }
    try {
      final page = await AppScope.of(context).xFollowingService.fetchReplies(
        widget.post.id,
        cursor: more ? _cursor : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (more) {
          final seen = _replies.map((item) => item.id).toSet();
          final added = page.replies.where((item) => seen.add(item.id)).toList();
          _replies.addAll(added);
          _cursor = added.isEmpty ? null : page.cursor;
        } else {
          _replies
            ..clear()
            ..addAll(page.replies);
          _cursor = page.cursor;
        }
        _pages += 1;
        _error = null;
        _moreError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (more) {
          _moreError = error.toString();
        } else {
          _error = error.toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = AppLayout.isCompact(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 24.w : 80.w,
        vertical: compact ? 12.h : 16.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420.w,
          maxHeight: size.height * 0.94,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 4.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '帖子',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _originalPost() {
    final post = widget.post;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              XAvatar(url: post.avatarUrl, size: 40),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp),
                    ),
                    Text(
                      '@${post.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (post.displayText.isNotEmpty) ...[
            SizedBox(height: 10.h),
            _RichPostText(
              text: post.displayText,
              style: TextStyle(height: 1.5, fontSize: 15.sp),
              selectable: true,
            ),
            if (post.hasTranslation) ...[
              SizedBox(height: 6.h),
              _RichPostText(
                text: post.text,
                style: TextStyle(
                  height: 1.45,
                  fontSize: 13.sp,
                  color: AppColors.textMuted,
                ),
                selectable: true,
              ),
            ],
          ],
          if (post.media.isNotEmpty) ...[
            SizedBox(height: 10.h),
            _MomentsMediaGrid(media: post.media),
          ],
          if (post.publishedAt != null) ...[
            SizedBox(height: 8.h),
            Text(
              formatPostTime(post.publishedAt!),
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.sp),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    final showFooter = _hasMore || _loadingMore || _moreError != null;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: _originalPost()),
        SliverToBoxAdapter(child: Divider(height: 1.h, color: AppColors.border)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            child: Text(
              '评论',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.sp),
            ),
          ),
        ),
        if (_loading && _replies.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _replies.isEmpty)
          SliverToBoxAdapter(
            child: EmptyHint(
              icon: Icons.wifi_off_rounded,
              title: '评论加载失败',
              detail: '$_error\n请确认 VPN 已开启后再试。',
            ),
          )
        else if (_replies.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
              child: Text(
                '还没有评论',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 20.h),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _replies.length) {
                    return _buildFooter();
                  }
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: _replyTile(_replies[index]),
                  );
                },
                childCount: _replies.length + (showFooter ? 1 : 0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _replyTile(XPost reply) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12.w),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '@${reply.username}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.sp),
                ),
              ),
              if (reply.publishedAt != null)
                Text(
                  formatPostTime(reply.publishedAt!),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.sp),
                ),
            ],
          ),
          if (reply.displayText.isNotEmpty) ...[
            SizedBox(height: 6.h),
            _RichPostText(
              text: reply.displayText,
              style: TextStyle(height: 1.45, fontSize: 13.sp),
              selectable: true,
            ),
            if (reply.hasTranslation) ...[
              SizedBox(height: 4.h),
              _RichPostText(
                text: reply.text,
                style: TextStyle(
                  height: 1.4,
                  fontSize: 12.sp,
                  color: AppColors.textMuted,
                ),
                selectable: true,
              ),
            ],
          ],
          if (reply.media.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _MomentsMediaGrid(media: reply.media),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Center(
          child: SizedBox(
            width: 20.w,
            height: 20.w,
            child: CircularProgressIndicator(strokeWidth: 2.w),
          ),
        ),
      );
    }
    if (_moreError != null) {
      return Center(
        child: GhostButton(
          label: '重试',
          icon: Icons.refresh,
          onPressed: () => _load(more: true),
        ),
      );
    }
    if (!_hasMore) {
      return const SizedBox.shrink();
    }
    return Center(
      child: GhostButton(
        label: '加载更多',
        icon: Icons.expand_more,
        onPressed: () => _load(more: true),
      ),
    );
  }
}

class PostWaterfall extends StatelessWidget {
  const PostWaterfall({
    required this.posts,
    required this.controller,
    required this.loadingMore,
    required this.hasMore,
    required this.onDownload,
    this.columns = 3,
    this.showAuthor = false,
    this.padding,
  });

  final int columns;
  final bool showAuthor;
  final List<XPost> posts;
  final ScrollController controller;
  final bool loadingMore;
  final bool hasMore;
  final ValueChanged<XPost> onDownload;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final count = columns < 1 ? 1 : columns;
    final buckets = List<List<XPost>>.generate(count, (_) => <XPost>[]);
    for (var i = 0; i < posts.length; i++) {
      buckets[i % count].add(posts[i]);
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: padding ?? EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < count; c++) ...[
                  if (c > 0) SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      children: [
                        for (final post in buckets[c])
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: PostCard(
                              key: ValueKey(post.id),
                              post: post,
                              dense: true,
                              showAuthor: showAuthor,
                              onDownload: onDownload,
                              onTap: () => showPostComments(context, post),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (loadingMore || hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 4.h, 0, 20.h),
              child: Center(
                child: loadingMore
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: CircularProgressIndicator(strokeWidth: 2.w),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onDownload,
    this.onOpen,
    this.onComments,
    this.onTap,
    this.showAuthor = false,
    this.dense = false,
  });

  final XPost post;
  final ValueChanged<XPost> onDownload;
  final ValueChanged<String>? onOpen;
  final VoidCallback? onComments;
  final VoidCallback? onTap;
  final bool showAuthor;
  final bool dense;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Timer? _hoverTimer;
  Timer? _exitTimer;
  String _translation = '';
  bool _translating = false;
  bool _pointerInside = false;

  XPost get post => widget.post;
  bool get dense => widget.dense;

  String get _shownTranslation {
    final hovered = _translation.trim();
    if (hovered.isNotEmpty) {
      return hovered;
    }
    return post.translation.trim();
  }

  bool get _hasTranslation {
    final translated = _shownTranslation;
    return translated.isNotEmpty && translated != post.text.trim();
  }

  String get _mainText {
    return _hasTranslation ? _shownTranslation : post.displayText;
  }

  @override
  void initState() {
    super.initState();
    _translation = post.translation;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != post.id) {
      _hoverTimer?.cancel();
      _exitTimer?.cancel();
      _hoverTimer = null;
      _exitTimer = null;
      _translating = false;
      _translation = post.translation;
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    _pointerInside = true;
    _exitTimer?.cancel();
    _exitTimer = null;
    _armHoverTranslate();
  }

  void _onExit(PointerEvent _) {
    _pointerInside = false;
    _exitTimer?.cancel();
    // 卡片高度变化时 Flutter 会误触发 onExit；稍等一下，还在上面就不要取消。
    _exitTimer = Timer(const Duration(milliseconds: 160), () {
      if (_pointerInside) {
        return;
      }
      _hoverTimer?.cancel();
      _hoverTimer = null;
    });
  }

  void _armHoverTranslate() {
    if (post.text.trim().isEmpty || post.isChinese || _hasTranslation || _translating) {
      return;
    }
    final cached = XFollowingService.cachedTranslation(post.id);
    if (cached != null) {
      setState(() => _translation = cached);
      return;
    }
    if (_hoverTimer?.isActive ?? false) {
      return;
    }
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(seconds: 2), _translate);
  }

  Future<void> _translate() async {
    if (!mounted || post.isChinese || _hasTranslation || _translating) {
      return;
    }
    _translating = true;
    try {
      final text = await AppScope.of(context).xFollowingService.fetchPostTranslation(post.id);
      if (!mounted || post.id != widget.post.id) {
        return;
      }
      setState(() {
        _translation = text;
        _translating = false;
      });
    } catch (_) {
      if (mounted) {
        _translating = false;
      }
    }
  }

  Widget _bodyText(String value, {bool muted = false, int? maxLines}) {
    final style = TextStyle(
      height: 1.45,
      fontSize: muted ? (dense ? 11.sp : 12.sp) : (dense ? 12.sp : 14.sp),
      color: muted ? AppColors.textMuted : null,
    );
    return _RichPostText(
      text: value,
      style: style,
      maxLines: maxLines,
      selectable: widget.onTap == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: dense
          ? EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 8.h)
          : EdgeInsets.fromLTRB(14.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12.w),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showAuthor)
            GestureDetector(
              onTap: () => XFeedLinks.openMention?.call(context, post.username),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  XAvatar(url: post.avatarUrl, size: dense ? 22 : 32),
                  SizedBox(width: dense ? 6.w : 8.w),
                  Expanded(
                    child: Text(
                      post.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: dense ? 11.sp : 13.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_mainText.isNotEmpty) ...[
            if (widget.showAuthor) SizedBox(height: dense ? 4.h : 6.h),
            _bodyText(_mainText, maxLines: dense ? 8 : null),
            if (_hasTranslation) ...[
              SizedBox(height: dense ? 4.h : 6.h),
              _bodyText(post.text, muted: true, maxLines: dense ? 4 : null),
            ],
          ],
          if (post.media.isNotEmpty) ...[
            SizedBox(height: dense ? 6.h : 10.h),
            _PostMediaGrid(media: post.media, dense: dense),
          ],
          if (!dense && (widget.onOpen != null || widget.onComments != null)) ...[
            SizedBox(height: 10.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                if (widget.onComments != null)
                  GhostButton(
                    label: '评论',
                    icon: Icons.chat_bubble_outline,
                    onPressed: widget.onComments,
                  ),
                if (widget.onOpen != null)
                  GhostButton(
                    label: '打开',
                    icon: Icons.open_in_browser,
                    onPressed: () => widget.onOpen!(post.url),
                  ),
              ],
            ),
          ],
          if (post.publishedAt != null) ...[
            SizedBox(height: dense ? 6.h : 8.h),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                formatPostTime(post.publishedAt!),
                style: TextStyle(color: AppColors.textMuted, fontSize: dense ? 10.sp : 11.sp),
              ),
            ),
          ],
        ],
      ),
    );
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: _onEnter,
      onExit: _onExit,
      child: widget.onTap == null
          ? card
          : GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.translucent,
              child: card,
            ),
    );
  }
}

class _RichPostText extends StatefulWidget {
  const _RichPostText({
    required this.text,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  State<_RichPostText> createState() => _RichPostTextState();
}

class _RichPostTextState extends State<_RichPostText> {
  static final _token = RegExp(
    r'@[A-Za-z0-9_]{1,15}|#[^\s#@]+',
    unicode: true,
  );
  static final _trailing = RegExp(
    r'''[.,!?;:'")\]}，。！？、；：）】》」』]+$''',
  );

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  TextSpan? _spanCache;
  String _cachedText = '';

  @override
  void didUpdateWidget(covariant _RichPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style.color != widget.style.color ||
        oldWidget.style.fontSize != widget.style.fontSize) {
      _spanCache = null;
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final item in _recognizers) {
      item.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextSpan _span() {
    _clearRecognizers();
    final base = widget.style;
    final link = base.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
    );
    final children = <InlineSpan>[];
    final text = widget.text;
    var start = 0;
    for (final match in _token.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(text: text.substring(start, match.start)));
      }
      var token = match.group(0) ?? '';
      var extra = '';
      if (token.startsWith('#')) {
        final cleaned = token.replaceFirst(_trailing, '');
        extra = token.substring(cleaned.length);
        token = cleaned;
      }
      if (token.length > 1) {
        final value = token;
        children.add(
          TextSpan(
            text: value,
            style: link,
            mouseCursor: SystemMouseCursors.click,
            recognizer: _tap(() {
              if (!mounted) {
                return;
              }
              if (value.startsWith('@')) {
                XFeedLinks.openMention?.call(context, value);
              } else {
                XFeedLinks.openSearch?.call(context, query: value);
              }
            }),
          ),
        );
      } else {
        extra = '$token$extra';
      }
      if (extra.isNotEmpty) {
        children.add(TextSpan(text: extra));
      }
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    if (_spanCache == null || _cachedText != widget.text) {
      _spanCache = _span();
      _cachedText = widget.text;
    }
    final span = _spanCache!;
    if (widget.selectable) {
      return SelectableText.rich(span, maxLines: widget.maxLines);
    }
    return Text.rich(
      span,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

class _MomentsMediaGrid extends StatelessWidget {
  const _MomentsMediaGrid({required this.media});

  final List<XMedia> media;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = media.length > 9 ? media.take(9).toList() : media;
        final gap = 4.w;
        final maxWidth = constraints.maxWidth;
        final unit = (maxWidth - gap * 2) / 3;
        if (items.length == 1) {
          return _one(context, items.first, unit * 2 + gap, unit * 2 + gap);
        }
        final cell = items.length == 4 ? (maxWidth - gap) / 2 : unit;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: cell,
                height: cell,
                child: _MediaThumb(
                  item: items[i],
                  media: media,
                  index: i,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _one(BuildContext context, XMedia item, double maxW, double maxH) {
    var width = maxW;
    var height = maxW * 0.75;
    if (item.width > 0 && item.height > 0) {
      final ratio = item.width / item.height;
      if (ratio >= 1) {
        width = maxW;
        height = width / ratio;
        if (height > maxH) {
          height = maxH;
          width = height * ratio;
        }
      } else {
        height = maxH;
        width = height * ratio;
        if (width > maxW) {
          width = maxW;
          height = width / ratio;
        }
      }
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: _MediaThumb(item: item, media: media, index: 0),
      ),
    );
  }
}

class _PostMediaGrid extends StatelessWidget {
  const _PostMediaGrid({required this.media, this.dense = false});

  final List<XMedia> media;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (dense) {
      final item = media.first;
      var ratio = 0.85;
      if (item.width > 0 && item.height > 0) {
        ratio = item.width / item.height;
        if (ratio < 0.55) {
          ratio = 0.55;
        } else if (ratio > 1.4) {
          ratio = 1.4;
        }
      }
      return AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MediaThumb(item: item, media: media, index: 0),
            if (media.length > 1)
              Positioned(
                right: 6.w,
                top: 6.h,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(6.w),
                  ),
                  child: Text(
                    '+${media.length - 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 6.w;
        final items = media.take(4).toList();
        final width = items.length == 1 ? constraints.maxWidth : (constraints.maxWidth - gap) / 2;
        final height = items.length == 1 ? 220.h : 128.h;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                height: height,
                child: _MediaThumb(
                  item: items[i],
                  media: media,
                  index: i,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.item,
    required this.media,
    required this.index,
  });

  final XMedia item;
  final List<XMedia> media;
  final int index;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.previewUrl.isNotEmpty ? item.previewUrl : item.url;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showPostMedia(context, media, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.w),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.surface,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                  ),
                ),
              ),
              if (item.isVideo) ...[
                const ColoredBox(color: Color(0x33000000)),
                Center(
                  child: Icon(
                    item.kind == XMediaKind.gif ? Icons.gif_box_outlined : Icons.play_circle_fill,
                    size: 36.w,
                    color: Colors.white,
                  ),
                ),
                if (item.durationLabel.isNotEmpty)
                  Positioned(
                    right: 8.w,
                    bottom: 8.h,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(6.w),
                      ),
                      child: Text(
                        item.durationLabel,
                        style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class XAvatar extends StatelessWidget {
  const XAvatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final side = size.w;
    return ClipOval(
      child: ColoredBox(
        color: AppColors.surfaceAlt,
        child: url.isEmpty
            ? SizedBox(
                width: side,
                height: side,
                child: Icon(Icons.person, size: (size * 0.57).w, color: AppColors.textMuted),
              )
            : Image.network(
                url,
                width: side,
                height: side,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: side,
                  height: side,
                  child: Icon(Icons.person, size: (size * 0.57).w, color: AppColors.textMuted),
                ),
              ),
      ),
    );
  }
}

String formatCount(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}

String formatPostTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
