import 'dart:convert';

import '../services/json_date.dart';

enum PaymentSource {
  companyAccount('公司账户'),
  cash('现金'),
  etc('ETC'),
  tollMixed('现金+ETC');

  const PaymentSource(this.label);
  final String label;

  static PaymentSource fromLabel(String raw) {
    for (final e in PaymentSource.values) {
      if (e.label == raw) return e;
    }
    return PaymentSource.cash;
  }
}

enum ExpenseCategory {
  fuel('油费'),
  toll('高速费'),
  other('其他费用');

  const ExpenseCategory(this.label);
  final String label;

  static ExpenseCategory fromLabel(String raw) {
    for (final e in ExpenseCategory.values) {
      if (e.label == raw) return e;
    }
    return ExpenseCategory.other;
  }
}

class RouteLeg {
  RouteLeg({
    required this.id,
    required this.loadPlace,
    required this.unloadPlace,
    required this.freight,
    required this.infoFee,
    required this.infoFeePaymentSource,
    required this.note,
    required this.attachments,
    required this.createdAt,
  });

  final String id;
  String loadPlace;
  String unloadPlace;
  double freight;
  double infoFee;
  PaymentSource infoFeePaymentSource;
  String note;
  List<String> attachments;
  DateTime createdAt;

  RouteLeg copy() => RouteLeg(
        id: id,
        loadPlace: loadPlace,
        unloadPlace: unloadPlace,
        freight: freight,
        infoFee: infoFee,
        infoFeePaymentSource: infoFeePaymentSource,
        note: note,
        attachments: List<String>.from(attachments),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'loadPlace': loadPlace,
        'unloadPlace': unloadPlace,
        'freight': freight,
        'infoFee': infoFee,
        'infoFeePaymentSource': infoFeePaymentSource.label,
        'note': note,
        'attachments': attachments,
        'createdAt': encodeSwiftJsonDate(createdAt),
      };

  static RouteLeg fromJson(Map<String, dynamic> j) => RouteLeg(
        id: j['id'] as String,
        loadPlace: j['loadPlace'] as String? ?? '',
        unloadPlace: j['unloadPlace'] as String? ?? '',
        freight: (j['freight'] as num?)?.toDouble() ?? 0,
        infoFee: (j['infoFee'] as num?)?.toDouble() ?? 0,
        infoFeePaymentSource:
            PaymentSource.fromLabel(j['infoFeePaymentSource'] as String? ?? ''),
        note: j['note'] as String? ?? '',
        attachments: (j['attachments'] as List?)?.cast<String>() ?? const [],
        createdAt: decodeJsonDate(j['createdAt']),
      );
}

class ExpenseItem {
  ExpenseItem({
    required this.id,
    required this.category,
    required this.title,
    required this.amount,
    required this.paymentSource,
    required this.isReimbursable,
    required this.attachments,
    required this.createdAt,
    this.tollCashAmount = 0,
    this.tollEtcAmount = 0,
    this.fuelKilograms = 0,
    this.fuelUnitPrice = 0,
  });

  final String id;
  ExpenseCategory category;
  String title;
  double amount;
  PaymentSource paymentSource;
  bool isReimbursable;
  List<String> attachments;
  DateTime createdAt;
  double tollCashAmount;
  double tollEtcAmount;
  /// 油费公斤数（仅油费有意义）。
  double fuelKilograms;
  /// 油费单价（元/公斤，仅油费有意义）。
  double fuelUnitPrice;

  ExpenseItem copy() => ExpenseItem(
        id: id,
        category: category,
        title: title,
        amount: amount,
        paymentSource: paymentSource,
        isReimbursable: isReimbursable,
        attachments: List<String>.from(attachments),
        createdAt: createdAt,
        tollCashAmount: tollCashAmount,
        tollEtcAmount: tollEtcAmount,
        fuelKilograms: fuelKilograms,
        fuelUnitPrice: fuelUnitPrice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.label,
        'title': title,
        'amount': amount,
        'paymentSource': paymentSource.label,
        'isReimbursable': isReimbursable,
        'attachments': attachments,
        'createdAt': encodeSwiftJsonDate(createdAt),
        'tollCashAmount': tollCashAmount,
        'tollEtcAmount': tollEtcAmount,
        'fuelKilograms': fuelKilograms,
        'fuelUnitPrice': fuelUnitPrice,
      };

  static ExpenseItem fromJson(Map<String, dynamic> j) {
    var category = ExpenseCategory.fromLabel(j['category'] as String? ?? '');
    var title = j['title'] as String? ?? '';
    final amount = (j['amount'] as num?)?.toDouble() ?? 0;
    var paymentSource = PaymentSource.fromLabel(j['paymentSource'] as String? ?? '');
    var isReimbursable = j['isReimbursable'] as bool? ?? false;
    final attachments = (j['attachments'] as List?)?.cast<String>() ?? <String>[];
    final createdAt = decodeJsonDate(j['createdAt']);
    var tollCashAmount = (j['tollCashAmount'] as num?)?.toDouble() ?? 0;
    var tollEtcAmount = (j['tollEtcAmount'] as num?)?.toDouble() ?? 0;
    var fuelKilograms = (j['fuelKilograms'] as num?)?.toDouble() ?? 0;
    var fuelUnitPrice = (j['fuelUnitPrice'] as num?)?.toDouble() ?? 0;

    if (j['category'] == null) {
      if (title.contains('油')) {
        category = ExpenseCategory.fuel;
      } else if (title.contains('高速')) {
        category = ExpenseCategory.toll;
      } else {
        category = ExpenseCategory.other;
      }
    }

    if (category != ExpenseCategory.toll) {
      tollCashAmount = 0;
      tollEtcAmount = 0;
    } else if (tollCashAmount == 0 && tollEtcAmount == 0 && amount > 0) {
      switch (paymentSource) {
        case PaymentSource.etc:
          tollEtcAmount = amount;
          break;
        case PaymentSource.cash:
        case PaymentSource.companyAccount:
        case PaymentSource.tollMixed:
          tollCashAmount = amount;
          break;
      }
    }

    if (category == ExpenseCategory.toll) {
      if (tollCashAmount > 0 && tollEtcAmount > 0) {
        paymentSource = PaymentSource.tollMixed;
      } else if (tollEtcAmount > 0) {
        paymentSource = PaymentSource.etc;
      } else if (tollCashAmount > 0) {
        paymentSource = PaymentSource.cash;
      }
    }

    if (category != ExpenseCategory.fuel) {
      fuelKilograms = 0;
      fuelUnitPrice = 0;
    }

    return ExpenseItem(
      id: j['id'] as String,
      category: category,
      title: title,
      amount: amount,
      paymentSource: paymentSource,
      isReimbursable: isReimbursable,
      attachments: attachments,
      createdAt: createdAt,
      tollCashAmount: tollCashAmount,
      tollEtcAmount: tollEtcAmount,
      fuelKilograms: fuelKilograms,
      fuelUnitPrice: fuelUnitPrice,
    );
  }
}

class CashAdvance {
  CashAdvance({
    required this.id,
    required this.title,
    required this.amount,
    required this.attachments,
    required this.createdAt,
  });

  final String id;
  String title;
  double amount;
  List<String> attachments;
  DateTime createdAt;

  CashAdvance copy() => CashAdvance(
        id: id,
        title: title,
        amount: amount,
        attachments: List<String>.from(attachments),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'attachments': attachments,
        'createdAt': encodeSwiftJsonDate(createdAt),
      };

  static CashAdvance fromJson(Map<String, dynamic> j) => CashAdvance(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        attachments: (j['attachments'] as List?)?.cast<String>() ?? const [],
        createdAt: decodeJsonDate(j['createdAt']),
      );
}

class TripLedger {
  TripLedger({
    required this.id,
    required this.title,
    required this.startPlace,
    required this.endPlace,
    required this.createdAt,
    required this.isReconciled,
    required this.isSalarySettled,
    required this.routeLegs,
    required this.expenses,
    required this.cashAdvances,
  });

  final String id;
  String title;
  String startPlace;
  String endPlace;
  DateTime createdAt;
  bool isReconciled;
  bool isSalarySettled;
  List<RouteLeg> routeLegs;
  List<ExpenseItem> expenses;
  List<CashAdvance> cashAdvances;

  TripLedger copy() => TripLedger(
        id: id,
        title: title,
        startPlace: startPlace,
        endPlace: endPlace,
        createdAt: createdAt,
        isReconciled: isReconciled,
        isSalarySettled: isSalarySettled,
        routeLegs: routeLegs.map((e) => e.copy()).toList(),
        expenses: expenses.map((e) => e.copy()).toList(),
        cashAdvances: cashAdvances.map((e) => e.copy()).toList(),
      );

  static TripLedger empty(String newId) => TripLedger(
        id: newId,
        title: '新建圈次',
        startPlace: '',
        endPlace: '',
        createdAt: DateTime.now(),
        isReconciled: false,
        isSalarySettled: false,
        routeLegs: [],
        expenses: [],
        cashAdvances: [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startPlace': startPlace,
        'endPlace': endPlace,
        'createdAt': encodeSwiftJsonDate(createdAt),
        'isReconciled': isReconciled,
        'isSalarySettled': isSalarySettled,
        'routeLegs': routeLegs.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'cashAdvances': cashAdvances.map((e) => e.toJson()).toList(),
      };

  static TripLedger fromJson(Map<String, dynamic> j) => TripLedger(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        startPlace: j['startPlace'] as String? ?? '',
        endPlace: j['endPlace'] as String? ?? '',
        createdAt: decodeJsonDate(j['createdAt']),
        isReconciled: j['isReconciled'] as bool? ?? false,
        isSalarySettled: j['isSalarySettled'] as bool? ?? false,
        routeLegs: (j['routeLegs'] as List?)
                ?.map((e) => RouteLeg.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        expenses: (j['expenses'] as List?)
                ?.map((e) => ExpenseItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        cashAdvances: (j['cashAdvances'] as List?)
                ?.map((e) => CashAdvance.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );
}

class LedgerBook {
  LedgerBook({required this.rounds});

  List<TripLedger> rounds;

  LedgerBook copy() => LedgerBook(
        rounds: rounds.map((e) => e.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'rounds': rounds.map((e) => e.toJson()).toList(),
      };

  static LedgerBook fromJson(Map<String, dynamic> j) => LedgerBook(
        rounds: (j['rounds'] as List?)
                ?.map((e) => TripLedger.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );

  static LedgerBook empty() => LedgerBook(rounds: []);

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static LedgerBook parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('rounds')) {
        return LedgerBook.fromJson(decoded);
      }
      return LedgerBook(rounds: [TripLedger.fromJson(decoded)]);
    }
    return LedgerBook.empty();
  }

  /// 用于「导入」：格式合法则返回账本，否则 `null`（不抛异常）。
  /// 支持 `{"rounds":[...]}` 或与 [parse] 相同的单圈次对象。
  static LedgerBook? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      if (m.containsKey('rounds')) {
        if (m['rounds'] is! List) return null;
        return LedgerBook.fromJson(m);
      }
      if (m['id'] is! String) return null;
      if (!m.containsKey('routeLegs') &&
          !m.containsKey('expenses') &&
          !m.containsKey('title')) {
        return null;
      }
      return LedgerBook(rounds: [TripLedger.fromJson(m)]);
    } catch (_) {
      return null;
    }
  }
}

String makeTripTitle(String start, String end) {
  final s = start.trim();
  final e = end.trim();
  if (s.isNotEmpty && e.isNotEmpty) return '$s ~ $e';
  if (s.isNotEmpty) return s;
  if (e.isNotEmpty) return e;
  return '未设置时间';
}
