// 生成与 Swift 结构一致的最小 xlsx，用于 unzip -t 校验 ZIP。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:truck_ledger_flutter/services/zip_writer.dart';

Uint8List utf8b(String s) => Uint8List.fromList(utf8.encode(s));

String inline(String ref, String text) {
  final t = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  return '<c r="$ref" t="inlineStr"><is><t>$t</t></is></c>';
}

void main() {
  final out = File('/tmp/truck_ledger_test.xlsx');
  if (out.existsSync()) out.deleteSync();

  final sheet = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetFormatPr defaultRowHeight="18"/>
<sheetData>
<row r="1" ht="22" customHeight="1">
${inline('A1', '时间')}
${inline('B1', '测试中文')}
</row>
</sheetData>
</worksheet>
''';

  final zip = ZipWriter(out);
  zip.addFile('[Content_Types].xml', utf8b('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
'''));
  zip.addFile('_rels/.rels', utf8b('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'''));
  zip.addFile('xl/workbook.xml', utf8b('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="明细" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
'''));
  zip.addFile('xl/_rels/workbook.xml.rels', utf8b('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
'''));
  zip.addFile('xl/styles.xml', utf8b('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>
'''));
  zip.addFile('xl/worksheets/sheet1.xml', utf8b(sheet));
  zip.closeSync();
  print('Wrote ${out.path} (${out.lengthSync()} bytes)');
}
