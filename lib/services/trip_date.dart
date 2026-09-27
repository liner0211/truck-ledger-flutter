import 'package:intl/intl.dart';

import '../models/trip_models.dart';

/// 圈次排序/按月归属用的时间：优先解析 `startPlace`（yyyy-MM-dd HH:mm），否则 `createdAt`。
class TripDate {
  TripDate._();

  static final DateFormat startFmt = DateFormat('yyyy-MM-dd HH:mm');

  static DateTime sortDate(TripLedger trip) {
    final s = trip.startPlace.trim();
    try {
      return startFmt.parse(s);
    } catch (_) {
      return trip.createdAt;
    }
  }

  /// `yyyy-MM`
  static String monthKey(TripLedger trip) {
    final d = sortDate(trip);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static String monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    return '${parts[0]}年${int.tryParse(parts[1]) ?? parts[1]}月';
  }
}
