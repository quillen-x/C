import 'package:flutter/material.dart';

import '../models.dart';

class XFeedLinks {
  static Future<void> Function(BuildContext, String)? openMention;
  static void Function(BuildContext, {String query})? openSearch;
  static Future<bool> Function(BuildContext, XAccount)? openHome;
}
