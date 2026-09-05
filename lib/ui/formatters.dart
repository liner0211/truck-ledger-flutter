import '../services/expression_eval.dart';

double? parseAmount(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return double.tryParse(raw.trim().replaceAll(',', '.'));
}

/// 解析金额或算术表达式（见 [ExpressionEval]）。
double? parseAmountOrExpression(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final plain = parseAmount(raw);
  if (plain != null) return plain;
  return ExpressionEval.tryEval(raw);
}
