import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/ledger_store.dart';

/// 与 `RootViewController` 行为对齐：总览列表、排序、持久化。
class LedgerController extends ChangeNotifier {
  LedgerController({LedgerStore? store}) : _store = store ?? LedgerStore();

  static const sortKey = 'TruckLedger.roundSortAscending';

  final LedgerStore _store;
  final _uuid = const Uuid();
  final _startFmt = DateFormat('yyyy-MM-dd HH:mm');

  LedgerBook _book = LedgerBook.empty();
  bool _sortAscending = true;
  bool _loaded = false;

  LedgerBook get book => _book;
  bool get sortAscending => _sortAscending;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _sortAscending = prefs.getBool(sortKey) ?? true;
    _book = await _store.load();
    _sortRounds();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store.save(_book);
    notifyListeners();
  }

  Future<void> toggleSortOrder() async {
    _sortAscending = !_sortAscending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sortKey, _sortAscending);
    _sortRounds();
    await _persist();
  }

  DateTime _sortDate(TripLedger trip) {
    final s = trip.startPlace.trim();
    try {
      return _startFmt.parse(s);
    } catch (_) {
      return trip.createdAt;
    }
  }

  void _sortRounds() {
    _book.rounds.sort((a, b) {
      final da = _sortDate(a);
      final db = _sortDate(b);
      final cmp = da.compareTo(db);
      if (cmp != 0) {
        return _sortAscending ? cmp : -cmp;
      }
      final c2 = a.createdAt.compareTo(b.createdAt);
      return _sortAscending ? c2 : -c2;
    });
  }

  Future<void> addRound(String startPlace, String endPlace) async {
    var round = TripLedger.empty(_uuid.v4());
    round.startPlace = startPlace;
    round.endPlace = endPlace;
    round.title = makeTripTitle(startPlace, endPlace);
    _book.rounds.add(round);
    _sortRounds();
    await _persist();
  }

  Future<void> replaceTrip(TripLedger updated) async {
    final idx = _book.rounds.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    _book.rounds[idx] = updated;
    _sortRounds();
    await _persist();
  }

  Future<void> deleteTripAt(int index) async {
    if (index < 0 || index >= _book.rounds.length) return;
    _book.rounds.removeAt(index);
    await _persist();
  }

  String money(double v) => '¥${v.toStringAsFixed(2)}';
}
