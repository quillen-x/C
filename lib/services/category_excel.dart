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
    final name = _sheetName(sheetName);
    final sheet = book[name];
    final defaultName = book.getDefaultSheet();
    if (defaultName != null && defaultName != name) {
      book.delete(defaultName);
    }
    book.setDefaultSheet(name);

    sheet.appendRow(<CellValue>[
      TextCellValue('#'),
      TextCellValue('name'),
      TextCellValue('username'),
      TextCellValue('description'),
      TextCellValue('followers'),
      TextCellValue('following'),
      TextCellValue('tweets'),
      TextCellValue('protected'),
      TextCellValue('avatar_url'),
      TextCellValue('profile_url'),
      TextCellValue('updated_at'),
    ]);

    for (var i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      sheet.appendRow(<CellValue>[
        IntCellValue(i + 1),
        TextCellValue(
          account.name.trim().isEmpty ? account.username : account.name,
        ),
        TextCellValue(account.username),
        TextCellValue(account.description),
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
      ]);
    }

    final bytes = book.encode();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('生成 Excel 失败');
    }
    return bytes;
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
