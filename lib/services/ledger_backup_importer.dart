import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/trip_models.dart';
import 'attachment_store.dart';

/// 从导出的 ZIP 或纯 JSON 解析备份。
class LedgerBackupBundle {
  LedgerBackupBundle({
    required this.book,
    this.attachmentFiles = const {},
  });

  final LedgerBook book;
  /// 附件文件名 → 文件内容（来自 ZIP 内 `attachments/`）。
  final Map<String, Uint8List> attachmentFiles;
}

class LedgerBackupImporter {
  LedgerBackupImporter._();

  static LedgerBackupBundle? fromJsonString(String raw) {
    final book = LedgerBook.tryParse(raw);
    if (book == null || book.rounds.isEmpty) return null;
    return LedgerBackupBundle(book: book);
  }

  static LedgerBackupBundle? fromZipBytes(List<int> bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }

    String? jsonRaw;
    final attachments = <String, Uint8List>{};

    for (final entry in archive) {
      if (entry.isFile != true) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name == 'ledger_book.json' || name.endsWith('/ledger_book.json')) {
        jsonRaw = utf8.decode(entry.content as List<int>);
        continue;
      }
      const prefix = 'attachments/';
      if (name.startsWith(prefix) && name.length > prefix.length) {
        final base = p.basename(name);
        if (base.isNotEmpty) {
          attachments[base] = Uint8List.fromList(entry.content as List<int>);
        }
      }
    }

    if (jsonRaw == null) return null;
    final book = LedgerBook.tryParse(jsonRaw);
    if (book == null || book.rounds.isEmpty) return null;
    return LedgerBackupBundle(book: book, attachmentFiles: attachments);
  }

  static Future<LedgerBackupBundle?> fromFileBytes(Uint8List bytes, String name) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.zip')) {
      return fromZipBytes(bytes);
    }
    if (lower.endsWith('.json')) {
      return fromJsonString(utf8.decode(bytes));
    }
    return null;
  }

  static Future<LedgerBackupBundle?> fromFilePath(String path) async {
    final f = File(path);
    if (!f.existsSync()) return null;
    final bytes = await f.readAsBytes();
    return fromFileBytes(bytes, path);
  }

  /// 将 ZIP 内附件写入应用沙盒（覆盖同名文件）。
  static Future<int> installAttachments(Map<String, Uint8List> files) async {
    var n = 0;
    for (final e in files.entries) {
      final out = await AttachmentStore.fileFor(e.key);
      await out.writeAsBytes(e.value, flush: true);
      n++;
    }
    return n;
  }
}
