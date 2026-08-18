import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../services/io_helpers.dart';
import '../theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(16.w),
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
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = color ?? AppColors.accent;
    final style = ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: Colors.black,
      disabledBackgroundColor: background.withValues(alpha: 0.4),
      minimumSize: compact ? Size(0, 32.h) : null,
      tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12.w : 16.w,
        vertical: compact ? 6.h : 12.h,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 12.sp : 13.sp),
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
          ? SizedBox(width: 14.w,
              height: 14.h,
              child: CircularProgressIndicator(strokeWidth: 2.w, color: Colors.black),
            )
          : Icon(icon ?? Icons.download_rounded, size: 18.w),
      label: Text(label),
      style: style,
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.folder_open, size: 16.w),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
        textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
      ),
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
        padding: EdgeInsets.symmetric(horizontal: 24.w),
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
