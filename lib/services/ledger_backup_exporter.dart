import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/trip_models.dart';
import 'attachment_store.dart';
import 'zip_writer.dart';

class LedgerBackupExportResult {
  LedgerBackupExportResult({
    required this.file,
    required this.filename,
    required this.roundCount,
    required this.attachmentCount,
  });

  final File file;
  final String filename;
  final int roundCount;
  final int attachmentCount;
}

/// 导出账本备份 ZIP：`ledger_book.json` + `attachments/` 下引用的图片（与导入 JSON 格式一致）。
class LedgerBackupExporter {
  LedgerBackupExporter._();

  static final _ts = DateFormat('yyyyMMdd_HHmmss');

  static Set<String> _collectAttachmentNames(LedgerBook book) {
    final names = <String>{};
    for (final round in book.rounds) {
      for (final leg in round.routeLegs) {
        for (final a in leg.attachments) {
          if (a.trim().isNotEmpty) names.add(a.trim());
        }
      }
      for (final e in round.expenses) {
        for (final a in e.attachments) {
          if (a.trim().isNotEmpty) names.add(a.trim());
        }
      }
      for (final c in round.cashAdvances) {
        for (final a in c.attachments) {
          if (a.trim().isNotEmpty) names.add(a.trim());
        }
      }
    }
    return names;
  }

  static Future<LedgerBackupExportResult> exportBook(LedgerBook book) async {
    final documents = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(documents.path, 'exports'));
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }

    final filename = '卡车记账备份_${_ts.format(DateTime.now())}.zip';
    final file = File(p.join(exportDir.path, filename));
    if (file.existsSync()) {
      await file.delete();
    }

    final zip = ZipWriter(file);
    final jsonBytes = Uint8List.fromList(utf8.encode(book.toJsonString()));
    zip.addFile('ledger_book.json', jsonBytes);

    final attDir = await AttachmentStore.attachmentsDirectory();
    var attached = 0;
    for (final name in _collectAttachmentNames(book)) {
      final src = File(p.join(attDir.path, name));
      if (!src.existsSync()) continue;
      zip.addFile('attachments/$name', await src.readAsBytes());
      attached++;
    }
    zip.closeSync();

    return LedgerBackupExportResult(
      file: file,
      filename: filename,
      roundCount: book.rounds.length,
      attachmentCount: attached,
    );
  }
}
