/// 与 Swift `JSONEncoder` 默认 `Date` 编码（timeIntervalSinceReferenceDate）对齐，便于读写原 iOS 端 `ledger_book.json`。
const double _swiftReferenceToUnix = 978307200;

double encodeSwiftJsonDate(DateTime d) {
  final utc = d.toUtc();
  return utc.millisecondsSinceEpoch / 1000.0 - _swiftReferenceToUnix;
}

DateTime decodeJsonDate(dynamic v) {
  if (v == null) return DateTime.now();
  if (v is String) {
    return DateTime.tryParse(v) ?? DateTime.now();
  }
  if (v is int) {
    return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
  }
  if (v is double) {
    final ms = ((v + _swiftReferenceToUnix) * 1000).round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  if (v is num) {
    return decodeJsonDate(v.toDouble());
  }
  return DateTime.now();
}
