import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 管理端连接站点 `/ws`（与司机端同一枢纽，无 FCM）。
class RealtimeSocket {
  RealtimeSocket();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Timer? _ping;
  String? _baseUrl;
  String? _token;
  bool _wanted = false;
  int _attempt = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  static Uri wsUri(String baseUrl, String token) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse(root);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/ws',
      queryParameters: {'token': token},
    );
  }

  void connect({required String baseUrl, required String token}) {
    _wanted = true;
    _baseUrl = baseUrl;
    _token = token;
    _open();
  }

  void disconnect() {
    _wanted = false;
    _reconnect?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _attempt = 0;
  }

  void _open() {
    if (!_wanted) return;
    final base = _baseUrl;
    final token = _token;
    if (base == null || token == null || token.isEmpty) return;

    _sub?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}

    final uri = wsUri(base, token);
    if (kDebugMode) {
      debugPrint('[AdminRealtime] connect $uri');
    }
    try {
      final ch = WebSocketChannel.connect(uri);
      _ch = ch;
      _sub = ch.stream.listen(
        (raw) {
          _attempt = 0;
          try {
            final m = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
            if (m is Map) {
              final map = m.cast<String, dynamic>();
              if (map['type'] == 'ping') {
                ch.sink.add(jsonEncode({'type': 'ping'}));
                return;
              }
              _events.add(map);
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          _ch?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _ch = null;
    _sub?.cancel();
    _sub = null;
    _ping?.cancel();
    if (!_wanted) return;
    _attempt += 1;
    final sec = (_attempt * 2).clamp(2, 30);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: sec), _open);
  }

  void dispose() {
    disconnect();
    _events.close();
  }
}
