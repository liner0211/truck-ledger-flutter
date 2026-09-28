import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../services/messages_api.dart';
import '../services/realtime_socket.dart';
import '../state/auth_controller.dart';
import 'message_detail_screen.dart';
import 'support_chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<InboxMessage> _messages = [];
  int _unread = 0;
  StreamSubscription? _rtSub;
  Timer? _debounce;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AuthController>().realtimeEvents.listen((e) {
      if (e['type'] == 'inbox' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted) _load(silent: true);
        });
      }
    });
    // WS 离线时兜底轮询，避免必须退出重进
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      final st = context.read<AuthController>().realtime.connectionState.value;
      if (st != RealtimeConnState.online) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await api.list();
      if (!mounted) return;
      setState(() {
        _messages = r.messages;
        _unread = r.unread;
        _loading = false;
        _error = null;
      });
      await context.read<AuthController>().refreshInbox();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = '$e';
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _markAll() async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) return;
    await api.markAllRead();
    await _load();
    if (mounted) {
      await context.read<AuthController>().refreshInbox();
    }
  }

  Future<void> _openMessage(InboxMessage m) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MessageDetailScreen(messageId: m.id),
      ),
    );
    await _load();
    if (mounted) {
      await context.read<AuthController>().refreshInbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final body = _buildBody(fmt);
    if (widget.embedded) {
      return Column(
        children: [
          if (_unread > 0 || true)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_unread > 0)
                      TextButton(onPressed: _markAll, child: const Text('全部已读')),
                    IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
            ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_unread > 0 ? '通知（$_unread）' : '通知'),
        actions: [
          if (_unread > 0)
            TextButton(onPressed: _markAll, child: const Text('全部已读')),
          IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(DateFormat fmt) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_messages.isEmpty) {
      return const Center(child: Text('暂无站内通知'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _messages.length,
      separatorBuilder: (_, i) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final m = _messages[i];
        final time = m.createdAt > 0
            ? fmt.format(DateTime.fromMillisecondsSinceEpoch(m.createdAt))
            : '';
        final ref = m.meta?.tripTitle;
        final isReconcile = m.type == 'ops.reconcile';
        return ListTile(
          leading: Icon(
            m.isRead
                ? Icons.mark_email_read_outlined
                : (isReconcile
                    ? Icons.fact_check_outlined
                    : Icons.mark_email_unread),
            color: m.isRead ? null : Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            m.title,
            style: TextStyle(
              fontWeight: m.isRead ? FontWeight.normal : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            [
              if (ref != null && ref.isNotEmpty) '引用：$ref',
              m.body,
              [
                time,
                if (m.replyCount > 0) '${m.replyCount} 条回复',
                m.isRead ? '已读' : '未读',
              ].where((e) => e.isNotEmpty).join(' · '),
            ].where((e) => e.isNotEmpty).join('\n'),
          ),
          isThreeLine: true,
          onTap: () => _openMessage(m),
        );
      },
    );
  }
}
