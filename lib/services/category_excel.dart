import 'dart:io';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import 'io_helpers.dart';

class CategoryExcel {
  static Future<File> export({
    required List<XAccount> accounts,
    required String categoryLabel,
  }) async {
    final bytes = encode(accounts, sheetName: categoryLabel);
    final stamp = _dateStamp();
    final fileName = IoHelpers.sanitizeFileName(
      '关注-$categoryLabel-$stamp.xlsx',
    );
    return _saveAndOpen(bytes, fileName);
  }

  static Future<File> exportAll({
    required Map<String, List<XAccount>> byCategory,
  }) async {
    final bytes = encodeAll(byCategory);
    final stamp = _dateStamp();
    final fileName = IoHelpers.sanitizeFileName('关注-全部分类-$stamp.xlsx');
    return _saveAndOpen(bytes, fileName);
  }

  static Future<File> _saveAndOpen(List<int> bytes, String fileName) async {
    final dir = Platform.isIOS
        ? Directory('${IoHelpers.defaultDownloadDir()}/MediaDownloader')
        : Directory(IoHelpers.defaultDownloadDir());
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    if (Platform.isIOS) {
      await Share.shareXFiles(
        <XFile>[
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            name: fileName,
          ),
        ],
      );
    } else {
      await Process.run('open', <String>[file.path]);
    }
    return file;
  }

  static List<int> encode(
    List<XAccount> accounts, {
    required String sheetName,
  }) {
    final book = Excel.createExcel();
    final name = _uniqueSheetName(<String>{}, sheetName);
    _writeSheet(
      book,
      name,
      accounts,
      includeCategory: false,
    );
    final defaultName = book.getDefaultSheet();
    if (defaultName != null && defaultName != name) {
      book.delete(defaultName);
    }
    book.setDefaultSheet(name);
    return _encodeBook(book);
  }

  static List<int> encodeAll(Map<String, List<XAccount>> byCategory) {
    final book = Excel.createExcel();
    final usedNames = <String>{};
    final entries = byCategory.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final all = <XAccount>[];
    for (final entry in entries) {
      all.addAll(entry.value);
    }
    all.sort((a, b) {
      final category = a.categoryKey.compareTo(b.categoryKey);
      if (category != 0) {
        return category;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final allSheet = _uniqueSheetName(usedNames, '全部');
    _writeSheet(
      book,
      allSheet,
      all,
      includeCategory: true,
    );
    book.setDefaultSheet(allSheet);

    for (final entry in entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final sheetName = _uniqueSheetName(usedNames, entry.key);
      _writeSheet(
        book,
        sheetName,
        entry.value,
        includeCategory: false,
      );
    }

    final defaultName = book.getDefaultSheet();
    if (defaultName != null &&
        defaultName != allSheet &&
        book.tables.containsKey(defaultName) &&
        (book.tables[defaultName]?.maxRows ?? 0) <= 0) {
      book.delete(defaultName);
    }

    return _encodeBook(book);
  }

  static void _writeSheet(
    Excel book,
    String sheetName,
    List<XAccount> accounts, {
    required bool includeCategory,
  }) {
    final sheet = book[sheetName];
    final headers = <CellValue>[
      TextCellValue('#'),
      if (includeCategory) TextCellValue('分类'),
      TextCellValue('显示名'),
      TextCellValue('用户名'),
      TextCellValue('简介'),
      TextCellValue('特别关注'),
      TextCellValue('粉丝'),
      TextCellValue('关注'),
      TextCellValue('推文'),
      TextCellValue('受保护'),
      TextCellValue('头像'),
      TextCellValue('主页'),
      TextCellValue('资料更新'),
      TextCellValue('最近发帖'),
    ];
    sheet.appendRow(headers);

    for (var i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      final row = <CellValue>[
        IntCellValue(i + 1),
        if (includeCategory)
          TextCellValue(XAccount.categoryLabel(account.category)),
        TextCellValue(
          account.name.trim().isEmpty ? account.username : account.name,
        ),
        TextCellValue(account.username),
        TextCellValue(account.description),
        TextCellValue(account.special ? '是' : '否'),
        IntCellValue(account.followers),
        IntCellValue(account.following),
        IntCellValue(account.tweets),
        TextCellValue(account.protected ? '是' : '否'),
        TextCellValue(account.avatarUrl),
        TextCellValue(
          account.profileUrl.trim().isEmpty
              ? 'https://x.com/${account.username}'
              : account.profileUrl,
        ),
        TextCellValue(_formatUpdatedAt(account.updatedAt)),
        TextCellValue(_formatUpdatedAt(account.lastPostAt)),
      ];
      sheet.appendRow(row);
    }
  }

  static List<int> _encodeBook(Excel book) {
    final bytes = book.encode();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('生成 Excel 失败');
    }
    return bytes;
  }

  static String _uniqueSheetName(Set<String> used, String label) {
    final base = _sheetName(label);
    if (used.add(base)) {
      return base;
    }
    var index = 2;
    while (true) {
      final suffix = '_$index';
      final trimmed = base.length + suffix.length > 31
          ? base.substring(0, 31 - suffix.length)
          : base;
      final candidate = '$trimmed$suffix';
      if (used.add(candidate)) {
        return candidate;
      }
      index += 1;
    }
  }

  static String _sheetName(String label) {
    var name = label.replaceAll(RegExp(r'[:\\/\?\*\[\]]'), '_').trim();
    if (name.isEmpty) {
      name = 'accounts';
    }
    if (name.length > 31) {
      name = name.substring(0, 31);
    }
    return name;
  }

  static String _dateStamp() {
    final time = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}';
  }

  static String _formatUpdatedAt(int millis) {
    if (millis <= 0) {
      return '';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
