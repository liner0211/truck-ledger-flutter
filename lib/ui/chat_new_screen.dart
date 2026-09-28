import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_api.dart';
import '../state/auth_controller.dart';
import 'chat_room_screen.dart';

class ChatNewScreen extends StatefulWidget {
  const ChatNewScreen({super.key});

  @override
  State<ChatNewScreen> createState() => _ChatNewScreenState();
}

class _ChatNewScreenState extends State<ChatNewScreen> {
  bool _loading = true;
  String? _error;
  List<ChatPeer> _peers = [];
  final _selected = <int>{};
  final _title = TextEditingController();
  bool _groupMode = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().chatApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    try {
      final list = await api.peers();
      if (!mounted) return;
      setState(() {
        _peers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _startDm(ChatPeer p) async {
    final api = context.read<AuthController>().chatApi;
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      final c = await api.openDm(p.id);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(conversationId: c.id, title: c.title),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createGroup() async {
    final api = context.read<AuthController>().chatApi;
    if (api == null || _busy) return;
    final title = _title.text.trim();
    if (title.isEmpty || _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写群名并选择成员')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await api.createGroup(title, _selected.toList());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(conversationId: c.id, title: c.title),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupMode ? '新建群聊' : '发起私聊'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _groupMode = !_groupMode;
              _selected.clear();
            }),
            child: Text(_groupMode ? '改私聊' : '建群'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    if (_groupMode)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _title,
                          decoration: const InputDecoration(
                            labelText: '群名称',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _peers.length,
                        itemBuilder: (ctx, i) {
                          final p = _peers[i];
                          if (_groupMode) {
                            final on = _selected.contains(p.id);
                            return CheckboxListTile(
                              value: on,
                              title: Text(p.username),
                              subtitle: p.licensePlate.isEmpty
                                  ? null
                                  : Text(p.licensePlate),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(p.id);
                                  } else {
                                    _selected.remove(p.id);
                                  }
                                });
                              },
                            );
                          }
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(p.username),
                            subtitle: p.licensePlate.isEmpty
                                ? null
                                : Text(p.licensePlate),
                            onTap: () => _startDm(p),
                          );
                        },
                      ),
                    ),
                    if (_groupMode)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: FilledButton(
                            onPressed: _busy ? null : _createGroup,
                            child: Text(_busy ? '创建中…' : '创建群聊'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
