import 'dart:typed_data';

List<int> makeTable() {
  final out = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1);
    }
    out[i] = c;
  }
  return out;
}

final table = makeTable();

int crcSigned(Uint8List data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc = table[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}

int crcUnsigned(Uint8List data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc = (table[(crc ^ b) & 0xff] ^ (crc >>> 8)) & 0xffffffff;
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void main() {
  // PKZIP CRC32 of "Hello" expected 0xF7D18982 (or check online)
  final hello = Uint8List.fromList('Hello'.codeUnits);
  print('Hello signed=${crcSigned(hello).toRadixString(16)} unsigned=${crcUnsigned(hello).toRadixString(16)}');
  // large xml-like
  final big = Uint8List(100000);
  for (var i = 0; i < big.length; i++) {
    big[i] = i & 0xff;
  }
  print('big signed=${crcSigned(big).toRadixString(16)} unsigned=${crcUnsigned(big).toRadixString(16)}');
}
