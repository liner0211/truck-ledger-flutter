import 'dart:convert';

import 'api_http_client.dart';
import 'auth_api.dart';

class ChatPeer {
  ChatPeer({required this.id, required this.username, this.licensePlate = ''});
  final int id;
  final String username;
  final String licensePlate;

  factory ChatPeer.fromJson(Map<String, dynamic> m) => ChatPeer(
        id: (m['id'] as num).toInt(),
        username: '${m['username'] ?? ''}',
        licensePlate: '${m['license_plate'] ?? ''}',
      );
}

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.type,
    required this.title,
    required this.updatedAt,
    this.unread = 0,
    this.lastBody,
    this.members = const [],
  });

  final int id;
  final String type; // dm | group
  final String title;
  final int updatedAt;
  final int unread;
  final String? lastBody;
  final List<Map<String, dynamic>> members;

  bool get isGroup => type == 'group';

  factory ChatConversation.fromJson(Map<String, dynamic> m) {
    final last = m['last_message'];
    return ChatConversation(
      id: (m['id'] as num).toInt(),
      type: '${m['type'] ?? 'dm'}',
      title: '${m['title'] ?? ''}',
      updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
      lastBody: last is Map ? '${last['body'] ?? ''}' : null,
      members: (m['members'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
    this.msgType = 'text',
  });

  final int id;
  final int conversationId;
  final int senderUserId;
  final String body;
  final int createdAt;
  final String msgType;

  factory ChatMessage.fromJson(Map<String, dynamic> m) => ChatMessage(
        id: (m['id'] as num).toInt(),
        conversationId: (m['conversation_id'] as num?)?.toInt() ?? 0,
        senderUserId: (m['sender_user_id'] as num?)?.toInt() ?? 0,
        body: '${m['body'] ?? ''}',
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        msgType: '${m['msg_type'] ?? 'text'}',
      );
}

class ChatApi {
  ChatApi({required this.baseUrl, required this.token});
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

  Future<List<ChatPeer>> peers() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/chat/peers')), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('获取联系人失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['peers'] as List? ?? [])
        .whereType<Map>()
        .map((e) => ChatPeer.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<ChatConversation>> conversations() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/chat/conversations')), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('获取会话失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['conversations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => ChatConversation.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ChatConversation> openDm(int peerUserId) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/chat/dm')),
          headers: _headers,
          body: jsonEncode({'peer_user_id': peerUserId}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('打开私聊失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return ChatConversation.fromJson((m['conversation'] as Map).cast<String, dynamic>());
  }

  Future<ChatConversation> createGroup(String title, List<int> memberIds) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/chat/groups')),
          headers: _headers,
          body: jsonEncode({'title': title, 'member_ids': memberIds}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('建群失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return ChatConversation.fromJson((m['conversation'] as Map).cast<String, dynamic>());
  }

  Future<List<ChatMessage>> messages(int conversationId) async {
    final res = await apiHttpClient
        .get(
          Uri.parse(_url('/api/chat/conversations/$conversationId/messages')),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('加载消息失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['messages'] as List? ?? [])
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ChatMessage> send(int conversationId, String body) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/chat/conversations/$conversationId/messages')),
          headers: _headers,
          body: jsonEncode({'body': body, 'msg_type': 'text'}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('发送失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return ChatMessage.fromJson((m['message'] as Map).cast<String, dynamic>());
  }

  Future<void> markRead(int conversationId) async {
    await apiHttpClient
        .post(
          Uri.parse(_url('/api/chat/conversations/$conversationId/read')),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
  }
}
