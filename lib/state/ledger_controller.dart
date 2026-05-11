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

  /// 用导入文件**完全替换**当前账本（需由 UI 二次确认）。
  Future<void> importReplace(LedgerBook incoming) async {
    _book = LedgerBook(
      rounds: incoming.rounds.map((e) => e.copy()).toList(),
    );
    _sortRounds();
    await _persist();
  }

  /// 将导入的圈次**追加**到当前账本；圈次 `id` 与本地冲突时整圈复制并换新 id（含子项 id）。
  Future<void> importMerge(LedgerBook incoming) async {
    final existingIds = _book.rounds.map((r) => r.id).toSet();
    for (final trip in incoming.rounds) {
      final TripLedger toAdd;
      if (existingIds.contains(trip.id)) {
        toAdd = _cloneTripWithFreshIds(trip, _uuid.v4());
        existingIds.add(toAdd.id);
      } else {
        toAdd = trip.copy();
        existingIds.add(toAdd.id);
      }
      _book.rounds.add(toAdd);
    }
    _sortRounds();
    await _persist();
  }

  TripLedger _cloneTripWithFreshIds(TripLedger src, String newTripId) {
    return TripLedger(
      id: newTripId,
      title: src.title,
      startPlace: src.startPlace,
      endPlace: src.endPlace,
      createdAt: src.createdAt,
      isReconciled: src.isReconciled,
      isSalarySettled: src.isSalarySettled,
      routeLegs: src.routeLegs
          .map(
            (l) => RouteLeg(
              id: _uuid.v4(),
              loadPlace: l.loadPlace,
              unloadPlace: l.unloadPlace,
              freight: l.freight,
              infoFee: l.infoFee,
              infoFeePaymentSource: l.infoFeePaymentSource,
              note: l.note,
              attachments: List<String>.from(l.attachments),
              createdAt: l.createdAt,
            ),
          )
          .toList(),
      expenses: src.expenses
          .map(
            (e) => ExpenseItem(
              id: _uuid.v4(),
              category: e.category,
              title: e.title,
              amount: e.amount,
              paymentSource: e.paymentSource,
              isReimbursable: e.isReimbursable,
              attachments: List<String>.from(e.attachments),
              createdAt: e.createdAt,
              tollCashAmount: e.tollCashAmount,
              tollEtcAmount: e.tollEtcAmount,
            ),
          )
          .toList(),
      cashAdvances: src.cashAdvances
          .map(
            (a) => CashAdvance(
              id: _uuid.v4(),
              title: a.title,
              amount: a.amount,
              attachments: List<String>.from(a.attachments),
              createdAt: a.createdAt,
            ),
          )
          .toList(),
    );
  }

  String money(double v) => '¥${v.toStringAsFixed(2)}';
}
