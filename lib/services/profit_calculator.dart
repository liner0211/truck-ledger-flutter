import '../models/trip_models.dart';

class ProfitSummary {
  const ProfitSummary({
    required this.totalFreight,
    required this.totalInfoFee,
    required this.fuelExpense,
    required this.tollExpense,
    required this.tollEtcAmount,
    required this.etcTollReconcileFee,
    required this.otherExpense,
    required this.reimbursableCashExpense,
    required this.cashTotalExpense,
    required this.totalExpense,
    required this.expenseByCash,
    required this.expenseByCompany,
    required this.netProfit,
    required this.driverShare,
    required this.ownerShare,
    required this.cashAdvances,
    required this.travelCashReconcile,
    required this.cashNetSettlement,
  });

  final double totalFreight;
  final double totalInfoFee;
  final double fuelExpense;
  final double tollExpense;
  final double tollEtcAmount;
  final double etcTollReconcileFee;
  final double otherExpense;
  final double reimbursableCashExpense;
  final double cashTotalExpense;
  final double totalExpense;
  final double expenseByCash;
  final double expenseByCompany;
  final double netProfit;
  final double driverShare;
  final double ownerShare;
  final double cashAdvances;
  final double travelCashReconcile;
  final double cashNetSettlement;
}

class ProfitCalculator {
  ProfitCalculator._();

  static const double etcTollReconcileRate = 0.0035;

  static ProfitSummary calculate(TripLedger ledger) {
    final freight = ledger.routeLegs.fold<double>(0, (a, r) => a + r.freight);
    final infoFee = ledger.routeLegs.fold<double>(0, (a, r) => a + r.infoFee);

    final routeCashInfoFee = ledger.routeLegs
        .where((r) => r.infoFeePaymentSource == PaymentSource.cash)
        .fold<double>(0, (a, r) => a + r.infoFee);
    final routeCompanyInfoFee = ledger.routeLegs
        .where((r) => r.infoFeePaymentSource == PaymentSource.companyAccount)
        .fold<double>(0, (a, r) => a + r.infoFee);

    final fuelExpense = ledger.expenses
        .where((e) => e.category == ExpenseCategory.fuel)
        .fold<double>(0, (a, e) => a + e.amount);
    final tollExpense = ledger.expenses
        .where((e) => e.category == ExpenseCategory.toll)
        .fold<double>(0, (a, e) => a + e.amount);
    final tollEtcBase = ledger.expenses
        .where((e) => e.category == ExpenseCategory.toll)
        .fold<double>(0, (a, e) => a + e.tollEtcAmount);
    final etcTollReconcileFee = tollEtcBase * etcTollReconcileRate;
    final otherExpense = ledger.expenses
        .where((e) => e.category == ExpenseCategory.other)
        .fold<double>(0, (a, e) => a + e.amount);
    final reimbursableCashExpense = ledger.expenses
        .where((e) =>
            e.category == ExpenseCategory.other &&
            e.paymentSource == PaymentSource.cash &&
            e.isReimbursable)
        .fold<double>(0, (a, e) => a + e.amount);

    final extraExpense =
        ledger.expenses.fold<double>(0, (a, e) => a + e.amount);
    final cashExtraExpense =
        ledger.expenses.fold<double>(0, (a, e) => a + expenseCashPortion(e));
    final companyExtraExpense =
        ledger.expenses.fold<double>(0, (a, e) => a + expenseCompanyPortion(e));
    final etcExtraExpense =
        ledger.expenses.fold<double>(0, (a, e) => a + expenseEtcPortion(e)) +
            etcTollReconcileFee;

    final profitExpense =
        (infoFee + extraExpense + etcTollReconcileFee) - reimbursableCashExpense;
    final cashExpense = routeCashInfoFee + cashExtraExpense;
    final companyExpense =
        routeCompanyInfoFee + companyExtraExpense + etcExtraExpense;
    final cashAdvancesTotal =
        ledger.cashAdvances.fold<double>(0, (a, c) => a + c.amount);
    final net = freight - profitExpense;
    final driverShare = net * 0.5;
    final ownerShare = net * 0.5;
    final cashTotalExpense = cashExpense;
    final travelCashReconcile = cashTotalExpense - cashAdvancesTotal;
    final cashNetSettlement = travelCashReconcile + reimbursableCashExpense;

    return ProfitSummary(
      totalFreight: freight,
      totalInfoFee: infoFee,
      fuelExpense: fuelExpense,
      tollExpense: tollExpense,
      tollEtcAmount: tollEtcBase,
      etcTollReconcileFee: etcTollReconcileFee,
      otherExpense: otherExpense,
      reimbursableCashExpense: reimbursableCashExpense,
      cashTotalExpense: cashTotalExpense,
      totalExpense: profitExpense,
      expenseByCash: cashExpense,
      expenseByCompany: companyExpense,
      netProfit: net,
      driverShare: driverShare,
      ownerShare: ownerShare,
      cashAdvances: cashAdvancesTotal,
      travelCashReconcile: travelCashReconcile,
      cashNetSettlement: cashNetSettlement,
    );
  }

  static double expenseCashPortion(ExpenseItem e) {
    if (e.category == ExpenseCategory.toll) return e.tollCashAmount;
    return e.paymentSource == PaymentSource.cash ? e.amount : 0;
  }

  static double expenseCompanyPortion(ExpenseItem e) {
    if (e.category == ExpenseCategory.toll) return 0;
    return e.paymentSource == PaymentSource.companyAccount ? e.amount : 0;
  }

  static double expenseEtcPortion(ExpenseItem e) {
    if (e.category == ExpenseCategory.toll) return e.tollEtcAmount;
    return e.paymentSource == PaymentSource.etc ? e.amount : 0;
  }
}
