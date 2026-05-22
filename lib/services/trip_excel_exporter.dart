import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/trip_models.dart';
import 'attachment_store.dart';
import 'profit_calculator.dart';
import 'zip_writer.dart';

/// 与 Swift `escapeXML` 一致。
String _escapeXml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class TripExcelExportResult {
  TripExcelExportResult({required this.file, required this.filename});
  final File file;
  final String filename;
}

class _ExportRow {
  _ExportRow({
    required this.dateText,
    required this.type,
    required this.title,
    this.amount,
    required this.payment,
    required this.reimbursableText,
    required this.images,
  });

  final String dateText;
  final String type;
  final String title;
  final double? amount;
  final String payment;
  final String reimbursableText;
  final List<String> images;
}

class _ImagePart {
  _ImagePart({
    required this.id,
    required this.partName,
    required this.relId,
    required this.data,
    required this.rowIndex1BasedInSheet,
    required this.columnIndex0Based,
  });

  final int id;
  final String partName;
  final String relId;
  final Uint8List data;
  final int rowIndex1BasedInSheet;
  final int columnIndex0Based;
}

/// 与 Swift `TripExcelExporter` 一致：手写 OOXML + `ZipWriter` 生成 `.xlsx`。
class TripExcelExporter {
  TripExcelExporter._();

  static final _df = DateFormat('yyyy-MM-dd HH:mm');

  static Future<TripExcelExportResult> exportTrip(TripLedger trip) async {
    final safeName = _sanitizeFilename(trip.title.trim().isEmpty ? '圈次' : trip.title);
    final filename = '$safeName.xlsx';

    final documents = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(documents.path, 'exports'));
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final file = File(p.join(exportDir.path, filename));
    if (file.existsSync()) {
      await file.delete();
    }

    final rows = _buildRows(trip);
    final images = await _collectImages(rows);

    final zip = ZipWriter(file);
    zip.addFile(
      '[Content_Types].xml',
      _utf8(_contentTypesXml(hasImages: images.isNotEmpty)),
    );
    zip.addFile('_rels/.rels', _utf8(_relsXml));
    zip.addFile('xl/workbook.xml', _utf8(_workbookXml));
    zip.addFile('xl/_rels/workbook.xml.rels', _utf8(_workbookRelsXml));
    zip.addFile('xl/styles.xml', _utf8(_stylesXml));
    zip.addFile(
      'xl/worksheets/sheet1.xml',
      _utf8(_worksheetXml(rows: rows, images: images)),
    );

    if (images.isNotEmpty) {
      zip.addFile('xl/drawings/drawing1.xml', _utf8(_drawingXml(images)));
      zip.addFile(
        'xl/drawings/_rels/drawing1.xml.rels',
        _utf8(_drawingRelsXml(images)),
      );
      zip.addFile('xl/worksheets/_rels/sheet1.xml.rels', _utf8(_sheetRelsXml));
      for (final img in images) {
        zip.addFile('xl/media/${img.partName}', img.data);
      }
    }

    zip.closeSync();
    return TripExcelExportResult(file: file, filename: filename);
  }

  static List<_ExportRow> _buildRows(TripLedger trip) {
    final rows = <_ExportRow>[];

    void section(String title) {
      rows.add(_ExportRow(
        dateText: '',
        type: '分组',
        title: '【$title】',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }

    void blank() {
      rows.add(_ExportRow(
        dateText: '',
        type: '',
        title: '',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }

    String fmt(double v) => v.toStringAsFixed(2);

    section('路线明细（含运费/信息费）');
    if (trip.routeLegs.isEmpty) {
      rows.add(_ExportRow(
        dateText: '',
        type: '路线',
        title: '（无）',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }
    for (final r in trip.routeLegs) {
      rows.add(_ExportRow(
        dateText: _df.format(r.createdAt),
        type: '路线',
        title:
            '${r.loadPlace} -> ${r.unloadPlace}（运费${fmt(r.freight)} 信息费${fmt(r.infoFee)}）',
        amount: r.freight,
        payment: r.infoFeePaymentSource.label,
        reimbursableText: '',
        images: r.attachments,
      ));
    }
    blank();

    section('油费');
    final fuel = trip.expenses.where((e) => e.category == ExpenseCategory.fuel).toList();
    if (fuel.isEmpty) {
      rows.add(_ExportRow(
        dateText: '',
        type: '油费',
        title: '（无）',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }
    for (final e in fuel) {
      rows.add(_ExportRow(
        dateText: _df.format(e.createdAt),
        type: '油费',
        title: e.title,
        amount: e.amount,
        payment: e.paymentSource.label,
        reimbursableText: '',
        images: e.attachments,
      ));
    }
    blank();

    section('高速费');
    final toll = trip.expenses.where((e) => e.category == ExpenseCategory.toll).toList();
    if (toll.isEmpty) {
      rows.add(_ExportRow(
        dateText: '',
        type: '高速费',
        title: '（无）',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }
    for (final e in toll) {
      rows.add(_ExportRow(
        dateText: _df.format(e.createdAt),
        type: '高速费',
        title: e.title,
        amount: e.amount,
        payment: _tollPaymentColumn(e),
        reimbursableText: '',
        images: e.attachments,
      ));
    }
    blank();

    section('其他费用');
    final other = trip.expenses.where((e) => e.category == ExpenseCategory.other).toList();
    if (other.isEmpty) {
      rows.add(_ExportRow(
        dateText: '',
        type: '其他费用',
        title: '（无）',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }
    for (final e in other) {
      final reimb = (e.paymentSource == PaymentSource.cash && e.isReimbursable) ? '是' : '';
      rows.add(_ExportRow(
        dateText: _df.format(e.createdAt),
        type: '其他费用',
        title: e.title,
        amount: e.amount,
        payment: e.paymentSource.label,
        reimbursableText: reimb,
        images: e.attachments,
      ));
    }
    blank();

    section('现金支取');
    if (trip.cashAdvances.isEmpty) {
      rows.add(_ExportRow(
        dateText: '',
        type: '现金支取',
        title: '（无）',
        amount: null,
        payment: '',
        reimbursableText: '',
        images: const [],
      ));
    }
    for (final a in trip.cashAdvances) {
      rows.add(_ExportRow(
        dateText: _df.format(a.createdAt),
        type: '现金支取',
        title: a.title,
        amount: a.amount,
        payment: '现金',
        reimbursableText: '',
        images: a.attachments,
      ));
    }
    blank();

    section('本圈汇总');
    final sum = ProfitCalculator.calculate(trip);
    void summaryLine(String label, String value) {
      rows.add(_ExportRow(
        dateText: '',
        type: '汇总',
        title: label,
        amount: null,
        payment: value,
        reimbursableText: '',
        images: const [],
      ));
    }

    summaryLine('运费(总)', fmt(sum.totalFreight));
    summaryLine('信息费(总)', fmt(sum.totalInfoFee));
    summaryLine('油费', fmt(sum.fuelExpense));
    summaryLine('高速费', fmt(sum.tollExpense));
    summaryLine('高速ETC对账手续费(0.35%)', fmt(sum.etcTollReconcileFee));
    summaryLine('其他费用', fmt(sum.otherExpense));
    summaryLine('其中可报销(现金)', fmt(sum.reimbursableCashExpense));
    summaryLine('费用(总，利润口径)', fmt(sum.totalExpense));
    summaryLine('利润', fmt(sum.netProfit));
    summaryLine('分成-司机应得', fmt(sum.driverShare));
    summaryLine('分成-老板应得', fmt(sum.ownerShare));
    summaryLine('现金费用(对账口径)', fmt(sum.cashTotalExpense));
    summaryLine('已支取现金', fmt(sum.cashAdvances));
    summaryLine('出车费差额(现金花费-已支取)', fmt(sum.travelCashReconcile));
    final reconcileText = sum.cashNetSettlement > 0.000001
        ? '老板补你 ${fmt(sum.cashNetSettlement)}'
        : (sum.cashNetSettlement < -0.000001
            ? '你退老板 ${fmt(-sum.cashNetSettlement)}'
            : '无差额');
    summaryLine('交账净额(出车费差额+可报销)', reconcileText);

    return rows;
  }

  static String _tollPaymentColumn(ExpenseItem e) {
    String f(double v) => v.toStringAsFixed(2);
    if (e.category != ExpenseCategory.toll) return e.paymentSource.label;
    final bits = <String>[];
    if (e.tollCashAmount > 0.000001) bits.add('现金${f(e.tollCashAmount)}');
    if (e.tollEtcAmount > 0.000001) bits.add('ETC${f(e.tollEtcAmount)}');
    if (bits.isEmpty) return e.paymentSource.label;
    return bits.join(' ');
  }

  /// Swift `AttachmentStore` 只存 JPEG；导出时把 PNG/HEIC 等转成 JPEG 再写入 xlsx。
  static Uint8List? _jpegBytesForExport(Uint8List raw) {
    if (raw.length >= 3 &&
        raw[0] == 0xFF &&
        raw[1] == 0xD8 &&
        raw[2] == 0xFF) {
      return raw;
    }
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
  }

  static Future<List<_ImagePart>> _collectImages(List<_ExportRow> rows) async {
    final parts = <_ImagePart>[];
    var nextId = 1;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final sheetRow = i + 2;
      for (var j = 0; j < row.images.length; j++) {
        final name = row.images[j];
        final f = await AttachmentStore.fileFor(name);
        if (!f.existsSync()) continue;
        final raw = await f.readAsBytes();
        final jpeg = _jpegBytesForExport(raw);
        if (jpeg == null || jpeg.isEmpty) continue;
        parts.add(_ImagePart(
          id: nextId,
          partName: 'image$nextId.jpg',
          relId: 'rId$nextId',
          data: jpeg,
          rowIndex1BasedInSheet: sheetRow,
          columnIndex0Based: 6 + j,
        ));
        nextId++;
      }
    }
    return parts;
  }

  static String _worksheetXml({
    required List<_ExportRow> rows,
    required List<_ImagePart> images,
  }) {
    final buf = StringBuffer();
    buf.write('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetFormatPr defaultRowHeight="18"/>
<cols>
  <col min="1" max="1" width="18" customWidth="1"/>
  <col min="2" max="2" width="12" customWidth="1"/>
  <col min="3" max="3" width="48" customWidth="1"/>
  <col min="4" max="4" width="12" customWidth="1"/>
  <col min="5" max="5" width="12" customWidth="1"/>
  <col min="6" max="6" width="10" customWidth="1"/>
  <col min="7" max="20" width="18" customWidth="1"/>
</cols>
<sheetData>
''');
    buf.write(_rowXml(
      rowIndex: 1,
      height: 22,
      cells: [
        _inlineCell('A1', '时间'),
        _inlineCell('B1', '类型'),
        _inlineCell('C1', '内容'),
        _inlineCell('D1', '金额'),
        _inlineCell('E1', '支付'),
        _inlineCell('F1', '可报销'),
        _inlineCell('G1', '图片(从G列开始)'),
      ],
    ));

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final ridx = i + 2;
      final h = r.images.isNotEmpty ? 80.0 : 22.0;
      final cells = <String>[
        _inlineCell('A$ridx', r.dateText),
        _inlineCell('B$ridx', r.type),
        _inlineCell('C$ridx', r.title),
        if (r.amount != null)
          _numberCell('D$ridx', r.amount!)
        else
          _inlineCell('D$ridx', ''),
        _inlineCell('E$ridx', r.payment),
        _inlineCell('F$ridx', r.reimbursableText),
      ];
      buf.write(_rowXml(rowIndex: ridx, height: h, cells: cells));
    }

    buf.write('</sheetData>');
    if (images.isNotEmpty) {
      buf.write('<drawing r:id="rIdDrawing1"/>');
    }
    buf.write('</worksheet>');
    return buf.toString();
  }

  static String _drawingXml(List<_ImagePart> images) {
    const sizeEmu = 64 * 9525;
    const xfrm = '''
<a:xfrm>
  <a:off x="0" y="0"/>
  <a:ext cx="$sizeEmu" cy="$sizeEmu"/>
</a:xfrm>
''';

    final buf = StringBuffer();
    buf.write('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
''');
    for (final img in images) {
      final fromCol = img.columnIndex0Based;
      final fromRow = img.rowIndex1BasedInSheet - 1;
      final toCol = fromCol + 1;
      final toRow = fromRow + 1;
      buf.write('''
<xdr:twoCellAnchor>
  <xdr:from><xdr:col>$fromCol</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>$fromRow</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
  <xdr:to><xdr:col>$toCol</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>$toRow</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
  <xdr:pic>
    <xdr:nvPicPr>
      <xdr:cNvPr id="${img.id}" name="${img.partName}"/>
      <xdr:cNvPicPr/>
    </xdr:nvPicPr>
    <xdr:blipFill>
      <a:blip r:embed="${img.relId}"/>
      <a:stretch><a:fillRect/></a:stretch>
    </xdr:blipFill>
    <xdr:spPr>
      $xfrm
      <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    </xdr:spPr>
  </xdr:pic>
  <xdr:clientData/>
</xdr:twoCellAnchor>
''');
    }
    buf.write('</xdr:wsDr>');
    return buf.toString();
  }

  static String _drawingRelsXml(List<_ImagePart> images) {
    final buf = StringBuffer();
    buf.write('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
''');
    for (final img in images) {
      buf.write(
        '<Relationship Id="${img.relId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/${img.partName}"/>',
      );
    }
    buf.write('</Relationships>');
    return buf.toString();
  }

  static const _sheetRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdDrawing1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
</Relationships>
''';

  static String _contentTypesXml({required bool hasImages}) {
    final buf = StringBuffer();
    buf.write('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
''');
    if (hasImages) {
      buf.write('''
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
''');
    }
    buf.write('</Types>');
    return buf.toString();
  }

  static const _relsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';

  static const _workbookXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="明细" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
''';

  static const _workbookRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''';

  static const _stylesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>
''';

  static String _rowXml({required int rowIndex, required double height, required List<String> cells}) {
    final ht = height.round();
    return '''
<row r="$rowIndex" ht="$ht" customHeight="1">
${cells.join()}
</row>
''';
  }

  static String _inlineCell(String ref, String text) {
    final t = _escapeXml(text);
    return '<c r="$ref" t="inlineStr"><is><t>$t</t></is></c>';
  }

  static String _numberCell(String ref, double value) {
    final v = value.toStringAsFixed(2);
    return '<c r="$ref"><v>$v</v></c>';
  }

  /// OOXML 声明 UTF-8，须用 [utf8.encode]；勿用 [String.codeUnits]（会破坏中文）。
  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  static String _sanitizeFilename(String s) {
    return s.replaceAll(RegExp(r'[/\\?%*|"<>:]'), '_');
  }
}
