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

class MessageReply {
  MessageReply({
    required this.id,
    required this.messageId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int messageId;
  final String senderRole; // user | admin
  final String body;
  final int createdAt;

  bool get isAdmin => senderRole == 'admin';

  factory MessageReply.fromJson(Map<String, dynamic> m) => MessageReply(
        id: (m['id'] as num).toInt(),
        messageId: (m['message_id'] as num?)?.toInt() ?? 0,
        senderRole: (m['sender_role'] as String?) ?? 'user',
        body: (m['body'] as String?) ?? '',
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
      );
}

class InboxMessage {
  InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.replyCount = 0,
    this.meta,
    this.replies = const [],
  });

  final int id;
  final String title;
  final String body;
  final String type;
  final int createdAt;
  final bool isRead;
  final int replyCount;
  final MessageMeta? meta;
  final List<MessageReply> replies;

  factory InboxMessage.fromJson(Map<String, dynamic> m) => InboxMessage(
        id: (m['id'] as num).toInt(),
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        type: (m['type'] as String?) ?? '',
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        isRead: m['is_read'] == true,
        replyCount: (m['reply_count'] as num?)?.toInt() ?? 0,
        meta: m['meta'] is Map
            ? MessageMeta.fromJson((m['meta'] as Map).cast<String, dynamic>())
            : null,
        replies: (m['replies'] as List? ?? [])
            .whereType<Map>()
            .map((e) => MessageReply.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class SupportMessage {
  SupportMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.readByPeerAt,
  });

  final int id;
  final String senderRole;
  final String body;
  final int createdAt;
  final int? readByPeerAt;

  bool get isMine => senderRole == 'user';
  bool get peerRead => readByPeerAt != null;

  factory SupportMessage.fromJson(Map<String, dynamic> m) => SupportMessage(
        id: (m['id'] as num).toInt(),
        senderRole: (m['sender_role'] as String?) ?? 'user',
        body: (m['body'] as String?) ?? '',
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        readByPeerAt: (m['read_by_peer_at'] as num?)?.toInt(),
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

  Future<({List<InboxMessage> messages, int unread, int supportUnread})> list() async {
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
    return (
      messages: list,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
      supportUnread: (m['support_unread'] as num?)?.toInt() ?? 0,
    );
  }

  Future<InboxMessage> detail(int id) async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/messages/$id')), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('获取消息失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return InboxMessage.fromJson((m['message'] as Map).cast<String, dynamic>());
  }

  Future<MessageReply> reply(int messageId, String body) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/messages/$messageId/replies')),
          headers: _headers,
          body: jsonEncode({'body': body}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('回复失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return MessageReply.fromJson((m['reply'] as Map).cast<String, dynamic>());
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

  Future<({Map<String, dynamic> thread, List<SupportMessage> messages, int unread})>
      supportThread() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/support/thread')), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('打开客服会话失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final msgs = (m['messages'] as List? ?? [])
        .whereType<Map>()
        .map((e) => SupportMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
    return (
      thread: (m['thread'] as Map).cast<String, dynamic>(),
      messages: msgs,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SupportMessage> sendSupport(String body) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/support/messages')),
          headers: _headers,
          body: jsonEncode({'body': body}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('发送失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return SupportMessage.fromJson((m['message'] as Map).cast<String, dynamic>());
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
