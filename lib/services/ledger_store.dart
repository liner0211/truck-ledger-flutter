import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/trip_models.dart';

/// 与 Swift `LedgerStore` 一致：`Documents/ledger_book.json`。
class LedgerStore {
  LedgerStore({this.filename = 'ledger_book.json'});

  final String filename;

  Future<File> _file() async {
    final documents = await getApplicationDocumentsDirectory();
    return File(p.join(documents.path, filename));
  }

  Future<LedgerBook> load() async {
    final f = await _file();
    if (!f.existsSync()) return LedgerBook.empty();
    try {
      final raw = await f.readAsString();
      return LedgerBook.parse(raw);
    } catch (_) {
      return LedgerBook.empty();
    }
  }

  Future<void> save(LedgerBook book) async {
    final f = await _file();
    await f.writeAsString(book.toJsonString(), flush: true);
  }
}
