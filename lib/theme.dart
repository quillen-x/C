import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppColors {
  static const bg = Color(0xFF0B0D12);
  static const navBar = Color(0xFF000000);
  static const sidebar = Color(0xFF10131A);
  static const surface = Color(0xFF171B24);
  static const surfaceAlt = Color(0xFF1E2430);
  static const border = Color(0xFF2A3140);
  static const text = Color(0xFFF4F6FB);
  static const textMuted = Color(0xFF9AA3B5);
  static const accent = Color(0xFF7C9CFF);
  static const x = Color(0xFFE7E9EA);
  static const success = Color(0xFF5BD4A4);
  static const warning = Color(0xFFF5C15A);
  static const danger = Color(0xFFFF6B7A);
}

class AppFonts {
  static const family = 'AlibabaPuHuiTi';
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark();
  final textTheme = base.textTheme.apply(
    fontFamily: AppFonts.family,
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );
  return ThemeData(
    brightness: Brightness.dark,
    fontFamily: AppFonts.family,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.success,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    textTheme: textTheme,
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: AppFonts.family,
    ),
    dividerColor: AppColors.border,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(
        fontFamily: AppFonts.family,
        color: AppColors.text,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.w)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8.w),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: TextStyle(
        fontFamily: AppFonts.family,
        color: AppColors.text,
        fontSize: 12.sp,
      ),
    ),
  );
}
