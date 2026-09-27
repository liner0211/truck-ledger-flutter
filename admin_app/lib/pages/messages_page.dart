import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../ui/admin_widgets.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  int? _selectedUserId; // null = 广播
  bool _loadingUsers = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final list = await context.read<AdminSession>().api.users();
      if (mounted) {
        setState(() {
          _users = list;
          _loadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const PageHeader(
          title: '消息',
          subtitle: '向指定用户或全体发送站内信（可选推送）',
        ),
        AdminSection(
          title: '撰写并发送',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingUsers)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<int?>(
                  initialValue: _selectedUserId,
                  decoration: const InputDecoration(labelText: '收件人'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('全体广播'),
                    ),
                    for (final u in _users)
                      DropdownMenuItem<int?>(
                        value: (u['id'] as num).toInt(),
                        child: Text('${u['username']}（#${u['id']}）'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedUserId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 5,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题和内容')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AdminSession>().api.push(
            title: title,
            body: body,
            userId: _selectedUserId ?? 0,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送')));
      _title.clear();
      _body.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
