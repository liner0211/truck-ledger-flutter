import 'dart:io';
import 'dart:typed_data';

/// 与 Swift `ZipWriter` 一致：Store（无压缩）ZIP，供生成 `.xlsx` 包。
class ZipWriter {
  ZipWriter(File file) : _raf = file.openSync(mode: FileMode.write) {
    _raf.setPositionSync(0);
    _raf.truncateSync(0);
  }

  final RandomAccessFile _raf;
  final List<_ZipEntry> _entries = [];

  void addFile(String path, Uint8List data) {
    final nameBytes = Uint8List.fromList(path.codeUnits);
    final crc = _crc32(data);
    final offset = _raf.positionSync();

    final h = ByteData(30);
    var o = 0;
    void u32(int v) {
      h.setUint32(o, v, Endian.little);
      o += 4;
    }

    void u16(int v) {
      h.setUint16(o, v, Endian.little);
      o += 2;
    }

    u32(0x04034b50);
    u16(20);
    u16(0);
    u16(0);
    u16(0);
    u16(0);
    u32(crc.toUnsigned(32));
    u32(data.length);
    u32(data.length);
    u16(nameBytes.length);
    u16(0);

    _raf.writeFromSync(h.buffer.asUint8List(0, 30));
    _raf.writeFromSync(nameBytes);
    _raf.writeFromSync(data);

    _entries.add(_ZipEntry(
      path: path,
      crc32: crc,
      compressedSize: data.length,
      uncompressedSize: data.length,
      localHeaderOffset: offset,
    ));
  }

  void closeSync() {
    final centralDirectoryOffset = _raf.positionSync();
    final central = BytesBuilder();

    for (final e in _entries) {
      final nameBytes = Uint8List.fromList(e.path.codeUnits);
      final c = ByteData(46);
      var o = 0;
      void u32(int v) {
        c.setUint32(o, v, Endian.little);
        o += 4;
      }

      void u16(int v) {
        c.setUint16(o, v, Endian.little);
        o += 2;
      }

      u32(0x02014b50);
      u16(20);
      u16(20);
      u16(0);
      u16(0);
      u16(0);
      u16(0);
      u32(e.crc32.toUnsigned(32));
      u32(e.compressedSize);
      u32(e.uncompressedSize);
      u16(nameBytes.length);
      u16(0);
      u16(0);
      u16(0);
      u32(0);
      u32(e.localHeaderOffset);
      central.add(c.buffer.asUint8List(0, 46));
      central.add(nameBytes);
    }

    final centralBytes = central.toBytes();
    _raf.writeFromSync(centralBytes);

    final e = ByteData(22);
    var o = 0;
    e.setUint32(o, 0x06054b50, Endian.little);
    o += 4;
    e.setUint16(o, 0, Endian.little);
    o += 2;
    e.setUint16(o, 0, Endian.little);
    o += 2;
    e.setUint16(o, _entries.length, Endian.little);
    o += 2;
    e.setUint16(o, _entries.length, Endian.little);
    o += 2;
    e.setUint32(o, centralBytes.length, Endian.little);
    o += 4;
    e.setUint32(o, centralDirectoryOffset, Endian.little);
    o += 4;
    e.setUint16(o, 0, Endian.little);
    _raf.writeFromSync(e.buffer.asUint8List(0, 22));
    _raf.closeSync();
  }
}

class _ZipEntry {
  _ZipEntry({
    required this.path,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String path;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}

int _crc32(Uint8List data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}

final List<int> _crcTable = _makeCrcTable();

List<int> _makeCrcTable() {
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
