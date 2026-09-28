import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../services/messages_api.dart';
import '../services/realtime_socket.dart';
import '../state/auth_controller.dart';

/// 用户 ↔ 管理员客服会话。
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  String? _error;
  List<SupportMessage> _messages = [];
  StreamSubscription? _rtSub;
  Timer? _debounce;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AuthController>().realtimeEvents.listen((e) {
      if (e['type'] == 'support' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted && !_sending) _load(silent: true);
        });
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _sending) return;
      final st = context.read<AuthController>().realtime.connectionState.value;
      if (st != RealtimeConnState.online) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _rtSub?.cancel();
    _input.dispose();
    _scroll.dispose();
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
      final r = await api.supportThread();
      if (!mounted) return;
      setState(() {
        _messages = r.messages;
        _loading = false;
        _error = null;
      });
      _jumpBottom();
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

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final api = context.read<AuthController>().messagesApi;
    if (api == null) return;
    setState(() => _sending = true);
    try {
      final msg = await api.sendSupport(text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
      _jumpBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    final cs = Theme.of(context).colorScheme;
    final content = Column(
      children: [
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (ctx, i) {
              final m = _messages[i];
              final mine = m.isMine;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.body),
                      const SizedBox(height: 4),
                      Text(
                        '${fmt.format(DateTime.fromMillisecondsSinceEpoch(m.createdAt))}'
                        '${m.peerRead ? ' · 已读' : ''}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: '输入消息…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('联系管理员'),
        actions: [
          IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: content,
    );
  }
}
