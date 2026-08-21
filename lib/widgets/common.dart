import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/io_helpers.dart';
import '../theme.dart';
import 'app_layout.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ??
          EdgeInsets.all(AppLayout.isCompact(context) ? 10.w : 16.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.w),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.isDense = false,
    this.contentPadding,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(color: AppColors.text, fontSize: 14.sp),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14.sp),
        isDense: isDense,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: AppColors.textMuted, size: isDense ? 18.w : 20.w),
        prefixIconConstraints: prefixIcon == null
            ? null
            : BoxConstraints(
                minWidth: isDense ? 36.w : 48.w,
                minHeight: isDense ? 32.h : 48.h,
              ),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: EdgeInsets.only(right: 6.w),
                child: suffix,
              ),
        suffixIconConstraints: suffix == null
            ? null
            : const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: contentPadding ??
            EdgeInsets.symmetric(horizontal: 14.w, vertical: isDense ? 8.h : 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.w),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.w),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.w),
          borderSide: BorderSide(color: AppColors.accent, width: 1.4.w),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.busy = false,
    this.compact = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool busy;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final background = color ?? AppColors.accent;
    final style = ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: Colors.black,
      disabledBackgroundColor: background.withValues(alpha: 0.4),
      minimumSize: expand
          ? const Size(0, 0)
          : (compact ? Size(0, 32.h) : null),
      tapTargetSize: (compact || expand)
          ? MaterialTapTargetSize.shrinkWrap
          : null,
      visualDensity: expand
          ? VisualDensity.standard
          : (compact ? VisualDensity.compact : VisualDensity.standard),
      padding: EdgeInsets.symmetric(
        horizontal: compact || expand ? 12.w : 16.w,
        vertical: expand ? 0 : (compact ? 6.h : 12.h),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      textStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: compact || expand ? 12.sp : 13.sp,
      ),
    );
    if (icon == null && !busy) {
      return ElevatedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return ElevatedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? SizedBox(
              width: 14.w,
              height: 14.h,
              child: CircularProgressIndicator(strokeWidth: 2.w, color: Colors.black),
            )
          : Icon(icon ?? Icons.download_rounded, size: 18.w),
      label: Text(label),
      style: style,
    );
  }
}

class InlineActionField extends StatelessWidget {
  const InlineActionField({
    super.key,
    required this.controller,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
    this.actionColor,
  });

  final TextEditingController controller;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        AppTextField(
          controller: controller,
          hint: hint,
          isDense: true,
          contentPadding: EdgeInsets.fromLTRB(14.w, 10.h, 72.w, 20.h),
          onSubmitted: (_) => onAction(),
        ),
        Positioned(
          right: 6.w,
          top: 6.h,
          bottom: 6.h,
          child: PrimaryButton(
            label: actionLabel,
            color: actionColor ?? AppColors.x,
            compact: true,
            expand: true,
            busy: busy,
            onPressed: onAction,
          ),
        ),
      ],
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      side: const BorderSide(color: AppColors.border),
      padding: EdgeInsets.symmetric(
        horizontal: 14.w,
        vertical: height == null ? 12.h : 0,
      ),
      minimumSize: height == null ? null : Size(0, height!),
      maximumSize: height == null ? null : Size(double.infinity, height!),
      fixedSize: height == null ? null : Size.fromHeight(height!),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      alignment: Alignment.center,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
    );
    if (icon == null) {
      return OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16.w),
      label: Text(label),
      style: style,
    );
  }
}

void showAppSnack(
  BuildContext context,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: actionLabel == null
          ? const Duration(seconds: 4)
          : const Duration(seconds: 6),
      backgroundColor: error ? const Color(0xFF3A1D24) : AppColors.surfaceAlt,
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: AppColors.accent,
              onPressed: onAction,
            ),
    ),
  );
}

void showDownloadDoneSnack(BuildContext context, String path) {
  showAppSnack(
    context,
    IoHelpers.savedMessage(path),
    actionLabel: '立即观看',
    onAction: () async {
      try {
        await IoHelpers.openPreview(path);
      } catch (error) {
        showAppSnack(context, error.toString(), error: true);
      }
    },
  );
}

Future<void> copyText(String value) async {
  await Clipboard.setData(ClipboardData(text: value));
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.isCompact(context) ? 16.w : 24.w,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42.w, color: AppColors.textMuted),
              SizedBox(height: 14.h),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8.h),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.5, fontSize: 13.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.filterQuality = FilterQuality.medium,
    this.placeholder,
    this.error,
  });

  static const headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://x.com/',
  };

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final FilterQuality filterQuality;
  final Widget? placeholder;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return error ?? placeholder ?? const SizedBox.shrink();
    }
    final fallback = placeholder ?? ColoredBox(color: AppColors.surface);
    if (memCacheWidth != null) {
      return _image(memCacheWidth, fallback);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final logical = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (width ?? 0);
        final cacheWidth = logical > 0
            ? (logical * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 2048)
            : null;
        return _image(cacheWidth, fallback);
      },
    );
  }

  Widget _image(int? cacheWidth, Widget fallback) {
    return CachedNetworkImage(
      imageUrl: url.trim(),
      httpHeaders: headers,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: cacheWidth,
      filterQuality: filterQuality,
      fadeInDuration: const Duration(milliseconds: 80),
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => error ?? fallback,
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
            : AppNetworkImage(
                url: url,
                width: side,
                height: side,
                fit: BoxFit.cover,
                memCacheWidth: (side * 2).round().clamp(48, 256),
                error: SizedBox(
                  width: side,
                  height: side,
                  child: Icon(Icons.person, size: (size * 0.57).w, color: AppColors.textMuted),
                ),
              ),
      ),
    );
  }
}

class PhoneRefreshHost extends StatelessWidget {
  const PhoneRefreshHost({
    super.key,
    required this.onRefresh,
    required this.child,
    this.onLoadMore,
    this.hasMore = false,
    this.loadingMore = false,
    this.empty = false,
  });

  final Future<void> Function() onRefresh;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool loadingMore;
  final bool empty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.isCompact(context)) {
      return child;
    }
    final body = empty
        ? CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(hasScrollBody: false, child: child),
            ],
          )
        : child;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (empty || onLoadMore == null || !hasMore || loadingMore) {
            return false;
          }
          if (notification.metrics.maxScrollExtent <= 0) {
            return false;
          }
          if (notification.metrics.extentAfter < 280) {
            onLoadMore!();
          }
          return false;
        },
        child: body,
      ),
    );
  }
}

class RefreshFab extends StatelessWidget {
  const RefreshFab({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16.w,
      bottom: 16.h,
      child: Material(
        color: AppColors.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            width: 48.w,
            height: 48.w,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.w,
                        color: AppColors.accent,
                      ),
                    )
                  : SvgPicture.asset(
                      'assets/images/refrsh.svg',
                      width: 22.w,
                      height: 22.w,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textMuted,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class PhoneNavBar extends StatelessWidget {
  const PhoneNavBar({
    super.key,
    this.title = '',
    this.titleWidget,
    this.onBack,
    this.trailing,
    this.centerTitle = false,
    this.height = 48,
  });

  final String title;
  final Widget? titleWidget;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool centerTitle;
  final double height;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centerTitle ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
    );
    final titleChild = titleWidget ?? titleText;
    final barHeight = height.h;
    final bar = centerTitle && titleWidget == null
        ? SizedBox(
            height: barHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 72.w),
                  child: titleText,
                ),
                Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        onPressed: onBack,
                        icon: Icon(Icons.arrow_back_ios_new, size: 18.w, color: AppColors.text),
                      )
                    else
                      SizedBox(width: 12.w),
                    const Spacer(),
                    if (trailing != null) trailing!,
                  ],
                ),
              ],
            ),
          )
        : SizedBox(
            height: barHeight,
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    icon: Icon(Icons.arrow_back_ios_new, size: 18.w, color: AppColors.text),
                  )
                else
                  SizedBox(width: 12.w),
                Expanded(child: titleChild),
                if (trailing != null)
                  trailing!
                else if (onBack != null)
                  SizedBox(width: 48.w),
              ],
            ),
          );
    return ColoredBox(color: AppColors.navBar, child: bar);
  }
}
