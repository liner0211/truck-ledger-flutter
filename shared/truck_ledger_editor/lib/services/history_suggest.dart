import '../models/trip_models.dart';

/// 地点与高速费历史联想（常走路线）。
class HistorySuggest {
  HistorySuggest._();

  static String normalizePlace(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '');

  static List<String> placeSuggestions(
    Iterable<TripLedger> rounds, {
    required bool loadPlaces,
    int limit = 12,
  }) {
    final counts = <String, int>{};
    for (final trip in rounds) {
      for (final leg in trip.routeLegs) {
        final p = loadPlaces ? leg.loadPlace : leg.unloadPlace;
        final key = normalizePlace(p);
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// 本圈路线装卸地对集合（规范化）。
  static Set<String> routePairKeys(TripLedger trip) {
    final out = <String>{};
    for (final leg in trip.routeLegs) {
      final a = normalizePlace(leg.loadPlace);
      final b = normalizePlace(leg.unloadPlace);
      if (a.isEmpty || b.isEmpty) continue;
      out.add('$a>$b');
    }
    return out;
  }

  static List<TollHistoryHint> tollHintsForTrip(
    TripLedger current,
    Iterable<TripLedger> allRounds, {
    int limit = 5,
  }) {
    final keys = routePairKeys(current);
    if (keys.isEmpty) return const [];

    // amountKey -> aggregate
    final map = <String, _TollAgg>{};
    for (final trip in allRounds) {
      if (trip.id == current.id) continue;
      final tripKeys = routePairKeys(trip);
      if (tripKeys.isEmpty) continue;
      final fullMatch = keys.length == tripKeys.length && keys.containsAll(tripKeys);
      final partial = keys.any(tripKeys.contains);
      if (!fullMatch && !partial) continue;
      final score = fullMatch ? 2 : 1;
      for (final e in trip.expenses) {
        if (e.category != ExpenseCategory.toll) continue;
        if (e.amount <= 0.000001) continue;
        final k =
            '${e.amount.toStringAsFixed(2)}|${e.tollCashAmount.toStringAsFixed(2)}|${e.tollEtcAmount.toStringAsFixed(2)}|${e.paymentSource.name}';
        final agg = map.putIfAbsent(
          k,
          () => _TollAgg(
            amount: e.amount,
            tollCash: e.tollCashAmount,
            tollEtc: e.tollEtcAmount,
            pay: e.paymentSource,
            createdAt: e.createdAt,
            score: score,
          ),
        );
        agg.count += 1;
        if (score > agg.score) agg.score = score;
        if (e.createdAt.isAfter(agg.createdAt)) agg.createdAt = e.createdAt;
      }
    }

    final list = map.values.toList()
      ..sort((a, b) {
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        final t = b.createdAt.compareTo(a.createdAt);
        if (t != 0) return t;
        return b.count.compareTo(a.count);
      });

    return list
        .take(limit)
        .map(
          (a) => TollHistoryHint(
            amount: a.amount,
            tollCashAmount: a.tollCash,
            tollEtcAmount: a.tollEtc,
            paymentSource: a.pay,
            count: a.count,
            fullRouteMatch: a.score >= 2,
          ),
        )
        .toList();
  }
}

class TollHistoryHint {
  const TollHistoryHint({
    required this.amount,
    required this.tollCashAmount,
    required this.tollEtcAmount,
    required this.paymentSource,
    required this.count,
    required this.fullRouteMatch,
  });

  final double amount;
  final double tollCashAmount;
  final double tollEtcAmount;
  final PaymentSource paymentSource;
  final int count;
  final bool fullRouteMatch;

  String chipLabel(String Function(double) money) {
    final parts = <String>[money(amount)];
    if (tollCashAmount > 0.000001 && tollEtcAmount > 0.000001) {
      parts.add('现${money(tollCashAmount)}+ETC${money(tollEtcAmount)}');
    } else {
      parts.add(paymentSource.label);
    }
    if (count > 1) parts.add('×$count');
    if (fullRouteMatch) parts.add('同线');
    return parts.join(' · ');
  }
}

class _TollAgg {
  _TollAgg({
    required this.amount,
    required this.tollCash,
    required this.tollEtc,
    required this.pay,
    required this.createdAt,
    required this.score,
  });

  final double amount;
  final double tollCash;
  final double tollEtc;
  final PaymentSource pay;
  DateTime createdAt;
  int score;
  int count = 1;
}
