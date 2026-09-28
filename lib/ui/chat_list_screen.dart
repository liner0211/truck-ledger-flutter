import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/chat_api.dart';
import '../state/auth_controller.dart';
import 'chat_new_screen.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _loading = true;
  String? _error;
  List<ChatConversation> _items = [];
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AuthController>().realtimeEvents.listen((e) {
      if (e['type'] == 'chat' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted) _load(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final api = context.read<AuthController>().chatApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await api.conversations();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      await context.read<AuthController>().refreshInbox();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = '$e';
      });
    }
  }

  Future<void> _open(ChatConversation c) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomScreen(conversationId: c.id, title: c.title),
      ),
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '私聊与群聊',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ChatNewScreen(),
                    ),
                  );
                  await _load(silent: true);
                },
                icon: const Icon(Icons.add),
                label: const Text('发起'),
              ),
              IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? const Center(child: Text('暂无会话\n点「发起」开始私聊或建群'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final c = _items[i];
                            final time = c.updatedAt > 0
                                ? fmt.format(
                                    DateTime.fromMillisecondsSinceEpoch(c.updatedAt),
                                  )
                                : '';
                            return ListTile(
                              leading: CircleAvatar(
                                child: Icon(c.isGroup ? Icons.groups : Icons.person),
                              ),
                              title: Text(
                                c.title,
                                style: TextStyle(
                                  fontWeight: c.unread > 0
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (c.lastBody != null && c.lastBody!.isNotEmpty)
                                    c.lastBody!,
                                  time,
                                ].where((e) => e.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: c.unread > 0
                                  ? Badge(
                                      label: Text(
                                        c.unread > 99 ? '99+' : '${c.unread}',
                                      ),
                                    )
                                  : null,
                              onTap: () => _open(c),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
