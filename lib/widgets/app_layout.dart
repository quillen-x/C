import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppLayout {
  static const compactWidth = 700.0;

  static bool isCompact(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (Platform.isIOS && size.shortestSide < 600) {
      return true;
    }
    return size.width < compactWidth;
  }

  static bool get isIOS => Platform.isIOS;

  static EdgeInsets headerPadding(BuildContext context) {
    return isCompact(context)
        ? EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h)
        : EdgeInsets.fromLTRB(28.w, 8.h, 28.w, 12.h);
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 0,
    double bottom = 16,
  }) {
    final horizontal = (isCompact(context) ? 16.0 : 28.0).w;
    return EdgeInsets.fromLTRB(horizontal, top.h, horizontal, bottom.h);
  }

  static double get mediaHubBarClearance => 88;
}
