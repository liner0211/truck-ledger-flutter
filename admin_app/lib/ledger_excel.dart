import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// 从管理端拉取的账本 JSON 生成简易 Excel（圈次总览 + 各圈费用明细）。
class AdminLedgerExcel {
  AdminLedgerExcel._();

  static List<int> buildBytes(Map<String, dynamic> ledger, {String title = '账本'}) {
    final excel = Excel.createExcel();
    final overview = excel['圈次总览'];
    // remove default Sheet1 if present
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    overview.appendRow([
      TextCellValue('序号'),
      TextCellValue('起点'),
      TextCellValue('终点'),
      TextCellValue('开始'),
      TextCellValue('结束'),
      TextCellValue('运费'),
      TextCellValue('费用合计'),
      TextCellValue('垫付合计'),
      TextCellValue('已交账'),
      TextCellValue('已结工资'),
      TextCellValue('备注'),
    ]);

    final rounds = (ledger['rounds'] as List?) ?? const [];
    for (var i = 0; i < rounds.length; i++) {
      final r = (rounds[i] as Map).cast<String, dynamic>();
      final expenses = (r['expenses'] as List?) ?? const [];
      final advances = (r['advances'] as List?) ?? const [];
      double expSum = 0;
      double advSum = 0;
      for (final e in expenses) {
        if (e is Map) expSum += _num(e['amount']);
      }
      for (final a in advances) {
        if (a is Map) advSum += _num(a['amount']);
      }
      overview.appendRow([
        IntCellValue(i + 1),
        TextCellValue('${r['startPlace'] ?? r['start_place'] ?? ''}'),
        TextCellValue('${r['endPlace'] ?? r['end_place'] ?? ''}'),
        TextCellValue(_fmtTime(r['startTime'] ?? r['start_time'])),
        TextCellValue(_fmtTime(r['endTime'] ?? r['end_time'])),
        DoubleCellValue(_num(r['freight'] ?? r['freightAmount'] ?? r['freight_amount'])),
        DoubleCellValue(expSum),
        DoubleCellValue(advSum),
        TextCellValue(_bool(r['settled'] ?? r['accountSettled'] ?? r['account_settled']) ? '是' : '否'),
        TextCellValue(_bool(r['wageSettled'] ?? r['wage_settled']) ? '是' : '否'),
        TextCellValue('${r['note'] ?? r['remark'] ?? ''}'),
      ]);

      final sheetName = '圈${i + 1}'.length > 31 ? '圈${i + 1}'.substring(0, 31) : '圈${i + 1}';
      final detail = excel[sheetName];
      detail.appendRow([
        TextCellValue('类型'),
        TextCellValue('分类/说明'),
        TextCellValue('金额'),
        TextCellValue('备注'),
      ]);
      for (final e in expenses) {
        if (e is! Map) continue;
        detail.appendRow([
          TextCellValue('费用'),
          TextCellValue('${e['category'] ?? e['title'] ?? e['name'] ?? ''}'),
          DoubleCellValue(_num(e['amount'])),
          TextCellValue('${e['note'] ?? e['remark'] ?? ''}'),
        ]);
      }
      for (final a in advances) {
        if (a is! Map) continue;
        detail.appendRow([
          TextCellValue('垫付'),
          TextCellValue('${a['title'] ?? a['name'] ?? ''}'),
          DoubleCellValue(_num(a['amount'])),
          TextCellValue('${a['note'] ?? a['remark'] ?? ''}'),
        ]);
      }
      final legs = (r['routeLegs'] as List?) ?? (r['legs'] as List?) ?? const [];
      for (final leg in legs) {
        if (leg is! Map) continue;
        detail.appendRow([
          TextCellValue('路线'),
          TextCellValue('${leg['from'] ?? leg['start'] ?? ''} → ${leg['to'] ?? leg['end'] ?? ''}'),
          DoubleCellValue(0),
          TextCellValue('${leg['note'] ?? ''}'),
        ]);
      }
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('生成 Excel 失败');
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('excel bytes ${encoded.length} for $title');
    }
    return encoded;
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static String _fmtTime(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final ms = v.toInt();
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return dt.toIso8601String().replaceFirst('T', ' ').substring(0, 16);
    }
    return '$v';
  }
}
