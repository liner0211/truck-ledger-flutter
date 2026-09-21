import '../models/trip_models.dart';

/// 高速费历史联想（按出入口名称匹配，同线路优先）。
class HistorySuggest {
  HistorySuggest._();

  static String normalizePlace(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '');

  static String normalizeTitle(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

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

  /// 汇总历史高速费；同线路加分，按最近/频次排序。
  static List<TollHistoryHint> tollHintsForTrip(
    TripLedger current,
    Iterable<TripLedger> allRounds, {
    int limit = 40,
  }) {
    final keys = routePairKeys(current);
    final map = <String, _TollAgg>{};
    final rounds = allRounds.isEmpty ? <TripLedger>[current] : allRounds;

    for (final trip in rounds) {
      final tripKeys = routePairKeys(trip);
      final fullMatch =
          keys.isNotEmpty && keys.length == tripKeys.length && keys.containsAll(tripKeys);
      final partial = keys.isNotEmpty && keys.any(tripKeys.contains);
      final score = fullMatch ? 2 : (partial ? 1 : 0);

      for (final e in trip.expenses) {
        if (e.category != ExpenseCategory.toll) continue;
        if (e.amount <= 0.000001) continue;
        final title = normalizeTitle(e.title);
        if (title.isEmpty) continue;
        // 跳过默认占位标题
        if (title == ExpenseCategory.toll.label) continue;

        final k =
            '$title|${e.amount.toStringAsFixed(2)}|${e.tollCashAmount.toStringAsFixed(2)}|${e.tollEtcAmount.toStringAsFixed(2)}|${e.paymentSource.name}';
        final isNew = !map.containsKey(k);
        final agg = map.putIfAbsent(
          k,
          () => _TollAgg(
            title: title,
            amount: e.amount,
            tollCash: e.tollCashAmount,
            tollEtc: e.tollEtcAmount,
            pay: e.paymentSource,
            createdAt: e.createdAt,
            score: score,
          ),
        );
        if (!isNew) agg.count += 1;
        if (score > agg.score) agg.score = score;
        if (e.createdAt.isAfter(agg.createdAt)) {
          agg.createdAt = e.createdAt;
          agg.title = title;
        }
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
            title: a.title,
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

  /// 按出入口名称过滤；空输入不展示。
  static List<TollHistoryHint> filterTollHintsByName(
    List<TollHistoryHint> hints, {
    required String titleQuery,
    int limit = 8,
  }) {
    final tq = normalizeTitle(titleQuery);
    if (tq.isEmpty) return const [];
    final matched = hints.where((h) => normalizeTitle(h.title).contains(tq)).toList();
    // 前缀匹配优先
    matched.sort((a, b) {
      final at = normalizeTitle(a.title);
      final bt = normalizeTitle(b.title);
      final ap = at.startsWith(tq) ? 0 : 1;
      final bp = bt.startsWith(tq) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      final s = (b.fullRouteMatch ? 1 : 0).compareTo(a.fullRouteMatch ? 1 : 0);
      if (s != 0) return s;
      return b.count.compareTo(a.count);
    });
    return matched.take(limit).toList();
  }
}

class TollHistoryHint {
  const TollHistoryHint({
    required this.title,
    required this.amount,
    required this.tollCashAmount,
    required this.tollEtcAmount,
    required this.paymentSource,
    required this.count,
    required this.fullRouteMatch,
  });

  /// 高速出入口等标题（费用条目 title）。
  final String title;
  final double amount;
  final double tollCashAmount;
  final double tollEtcAmount;
  final PaymentSource paymentSource;
  final int count;
  final bool fullRouteMatch;

  String dropdownLabel(String Function(double) money) {
    final pay = (tollCashAmount > 0.000001 && tollEtcAmount > 0.000001)
        ? '现${money(tollCashAmount)}+ETC${money(tollEtcAmount)}'
        : paymentSource.label;
    final bits = <String>[title, money(amount), pay];
    if (count > 1) bits.add('×$count');
    if (fullRouteMatch) bits.add('同线');
    return bits.join(' · ');
  }
}

class _TollAgg {
  _TollAgg({
    required this.title,
    required this.amount,
    required this.tollCash,
    required this.tollEtc,
    required this.pay,
    required this.createdAt,
    required this.score,
  });

  String title;
  final double amount;
  final double tollCash;
  final double tollEtc;
  final PaymentSource pay;
  DateTime createdAt;
  int score;
  int count = 1;
}
