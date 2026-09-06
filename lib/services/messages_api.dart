import 'dart:convert';

import 'api_http_client.dart';
import 'auth_api.dart';

class MessageMeta {
  MessageMeta({
    this.tripId = '',
    this.tripTitle = '',
    this.images = const [],
  });

  final String tripId;
  final String tripTitle;
  final List<String> images;

  factory MessageMeta.fromJson(Map<String, dynamic>? m) {
    if (m == null) return MessageMeta();
    return MessageMeta(
      tripId: '${m['trip_id'] ?? ''}',
      tripTitle: '${m['trip_title'] ?? ''}',
      images: (m['images'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

class InboxMessage {
  InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.meta,
  });

  final int id;
  final String title;
  final String body;
  final String type;
  final int createdAt;
  final bool isRead;
  final MessageMeta? meta;

  factory InboxMessage.fromJson(Map<String, dynamic> m) => InboxMessage(
        id: (m['id'] as num).toInt(),
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        type: (m['type'] as String?) ?? '',
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        isRead: m['is_read'] == true,
        meta: m['meta'] is Map
            ? MessageMeta.fromJson((m['meta'] as Map).cast<String, dynamic>())
            : null,
      );
}

class MessagesApi {
  MessagesApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  String _url(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$root$path';
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, String> get _authOnly => {
        'Authorization': 'Bearer $token',
      };

  Future<({List<InboxMessage> messages, int unread})> list() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/messages')), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('获取消息失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (m['messages'] as List? ?? [])
        .whereType<Map>()
        .map((e) => InboxMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
    return (messages: list, unread: (m['unread'] as num?)?.toInt() ?? 0);
  }

  Future<List<int>> downloadAttachment(int messageId, String filename) async {
    final enc = Uri.encodeComponent(filename);
    final res = await apiHttpClient
        .get(
          Uri.parse(_url('/api/messages/$messageId/attachments/$enc')),
          headers: _authOnly,
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('下载消息附件失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Future<void> markRead(int id) async {
    await apiHttpClient
        .post(Uri.parse(_url('/api/messages/$id/read')), headers: _headers)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> markAllRead() async {
    await apiHttpClient
        .post(Uri.parse(_url('/api/messages/read-all')), headers: _headers)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    required String platform,
  }) async {
    await apiHttpClient
        .post(
          Uri.parse(_url('/api/devices/push-token')),
          headers: _headers,
          body: jsonEncode({
            'device_id': deviceId,
            'token': token,
            'platform': platform,
          }),
        )
        .timeout(const Duration(seconds: 15));
  }
}
