import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 当 Android 系统 DNS 无法解析子域名时，通过 DoH（与 Chrome 安全 DNS 类似）查询 A 记录。
class DnsOverHttps {
  DnsOverHttps._();

  static final _cache = <String, List<InternetAddress>>{};

  static Future<List<InternetAddress>> resolve(String host) async {
    if (_cache.containsKey(host)) return _cache[host]!;

    try {
      final sys = await InternetAddress.lookup(host);
      if (sys.isNotEmpty) {
        _cache[host] = sys;
        return sys;
      }
    } catch (_) {}

    final addrs = await _queryCloudflare(host);
    _cache[host] = addrs;
    return addrs;
  }

  static Future<List<InternetAddress>> _queryCloudflare(String host) async {
    final uri = Uri.https('cloudflare-dns.com', '/dns-query', {
      'name': host,
      'type': 'A',
    });
    final res = await http.get(uri, headers: {'accept': 'application/dns-json'});
    if (res.statusCode != 200) {
      throw SocketException('DoH 查询失败（${res.statusCode}）: $host');
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw SocketException('DoH 响应无效: $host');
    }
    final answers = body['Answer'];
    if (answers is! List) {
      throw SocketException('DoH 无 A 记录: $host');
    }
    final ips = <InternetAddress>[];
    for (final a in answers) {
      if (a is Map && a['type'] == 1 && a['data'] is String) {
        ips.add(InternetAddress(a['data'] as String));
      }
    }
    if (ips.isEmpty) {
      throw SocketException('DoH 未找到 IP: $host');
    }
    return ips;
  }
}
