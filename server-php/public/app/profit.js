/** 与 Flutter profit_calculator.dart 对齐 */
const ETC_TOLL_RECONCILE_RATE = 0.0035;

function expenseCashPortion(e) {
  if (e.category === '高速费') return Number(e.tollCashAmount) || 0;
  return e.paymentSource === '现金' ? Number(e.amount) || 0 : 0;
}

function expenseCompanyPortion(e) {
  if (e.category === '高速费') return 0;
  return e.paymentSource === '公司账户' ? Number(e.amount) || 0 : 0;
}

function expenseEtcPortion(e) {
  if (e.category === '高速费') return Number(e.tollEtcAmount) || 0;
  return e.paymentSource === 'ETC' ? Number(e.amount) || 0 : 0;
}

function calculateProfit(ledger) {
  const legs = ledger.routeLegs || [];
  const expenses = ledger.expenses || [];
  const advances = ledger.cashAdvances || [];

  const freight = legs.reduce((a, r) => a + (Number(r.freight) || 0), 0);
  const infoFee = legs.reduce((a, r) => a + (Number(r.infoFee) || 0), 0);

  const routeCashInfoFee = legs
    .filter((r) => r.infoFeePaymentSource === '现金')
    .reduce((a, r) => a + (Number(r.infoFee) || 0), 0);
  const routeCompanyInfoFee = legs
    .filter((r) => r.infoFeePaymentSource === '公司账户')
    .reduce((a, r) => a + (Number(r.infoFee) || 0), 0);

  const fuelExpense = expenses
    .filter((e) => e.category === '油费')
    .reduce((a, e) => a + (Number(e.amount) || 0), 0);
  const fuelKilogramsTotal = expenses
    .filter((e) => e.category === '油费')
    .reduce((a, e) => a + (Number(e.fuelKilograms) || 0), 0);
  const tollExpense = expenses
    .filter((e) => e.category === '高速费')
    .reduce((a, e) => a + (Number(e.amount) || 0), 0);
  const tollEtcBase = expenses
    .filter((e) => e.category === '高速费')
    .reduce((a, e) => a + (Number(e.tollEtcAmount) || 0), 0);
  const etcTollReconcileFee = tollEtcBase * ETC_TOLL_RECONCILE_RATE;
  const otherExpense = expenses
    .filter((e) => e.category === '其他费用')
    .reduce((a, e) => a + (Number(e.amount) || 0), 0);
  const reimbursableCashExpense = expenses
    .filter(
      (e) =>
        e.category === '其他费用' &&
        e.paymentSource === '现金' &&
        e.isReimbursable
    )
    .reduce((a, e) => a + (Number(e.amount) || 0), 0);

  const extraExpense = expenses.reduce((a, e) => a + (Number(e.amount) || 0), 0);
  const cashExtraExpense = expenses.reduce((a, e) => a + expenseCashPortion(e), 0);
  const companyExtraExpense = expenses.reduce((a, e) => a + expenseCompanyPortion(e), 0);
  const etcExtraExpense =
    expenses.reduce((a, e) => a + expenseEtcPortion(e), 0) + etcTollReconcileFee;

  const profitExpense = infoFee + extraExpense + etcTollReconcileFee;
  const cashExpense = routeCashInfoFee + cashExtraExpense;
  const companyExpense = routeCompanyInfoFee + companyExtraExpense + etcExtraExpense;
  const cashAdvancesTotal = advances.reduce((a, c) => a + (Number(c.amount) || 0), 0);
  const net = freight - profitExpense;
  const driverShare = net * 0.5;
  const reimbursableOwnerShare = reimbursableCashExpense * 0.5;
  const driverWagePayable = driverShare + reimbursableOwnerShare;
  const ownerShare = net * 0.5;
  const travelCashReconcile = cashExpense - cashAdvancesTotal;

  return {
    totalFreight: freight,
    totalInfoFee: infoFee,
    fuelExpense,
    fuelKilogramsTotal,
    tollExpense,
    tollEtcAmount: tollEtcBase,
    etcTollReconcileFee,
    otherExpense,
    reimbursableCashExpense,
    reimbursableOwnerShare,
    cashTotalExpense: cashExpense,
    totalExpense: profitExpense,
    expenseByCash: cashExpense,
    expenseByCompany: companyExpense,
    netProfit: net,
    driverShare,
    driverWagePayable,
    ownerShare,
    cashAdvances: cashAdvancesTotal,
    travelCashReconcile,
    cashNetSettlement: travelCashReconcile,
  };
}
