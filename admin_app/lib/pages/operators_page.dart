import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../ui/admin_widgets.dart';

class OperatorsPage extends StatefulWidget {
  const OperatorsPage({super.key});

  @override
  State<OperatorsPage> createState() => _OperatorsPageState();
}

class _OperatorsPageState extends State<OperatorsPage> {
  List<Map<String, dynamic>> _list = [];
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<AdminSession>().api.operators();
      if (mounted) {
        setState(() {
          _list = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        PageHeader(
          title: '会计账号',
          subtitle: '会计可管理用户与账本；控制面与删用户等仅开发者可用',
          trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ),
        AdminSection(
          title: '创建会计管理员',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _user,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: '初始密码'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  try {
                    await api.createOperator(_user.text.trim(), _pass.text);
                    _user.clear();
                    _pass.clear();
                    _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已创建')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                child: const Text('创建'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('账号列表', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_list.isEmpty)
          const EmptyState(
            icon: Icons.admin_panel_settings_outlined,
            title: '暂无会计账号',
            detail: '上方可创建会计管理员',
          )
        else
          ..._list.map((a) {
            final id = (a['id'] as num).toInt();
            final role = '${a['role']}';
            final enabled = a['is_enabled'] == true;
            final label = a['role_label'] ?? (role == 'super' ? '开发者' : '会计管理员');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text('${a['username']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$label · ${enabled ? '启用' : '禁用'}'),
                  trailing: role == 'super'
                      ? Text('不可删', style: TextStyle(color: cs.outline))
                      : PopupMenuButton<String>(
                          onSelected: (v) async {
                            try {
                              if (v == 'enable') {
                                await api.setOperatorEnabled(id, true);
                              } else if (v == 'disable') {
                                await api.setOperatorEnabled(id, false);
                              } else if (v == 'reset') {
                                final ctrl = TextEditingController();
                                final pass = await showDialog<String>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('重置密码'),
                                    content: TextField(
                                      controller: ctrl,
                                      obscureText: true,
                                      decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, ctrl.text),
                                        child: const Text('确定'),
                                      ),
                                    ],
                                  ),
                                );
                                if (pass == null || pass.length < 6) return;
                                await api.resetOperatorPassword(id, pass);
                              } else if (v == 'delete') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('删除会计管理员'),
                                    content: Text('确定删除「${a['username']}」？'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: cs.error),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  final msg = await api.deleteOperator(id);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                  }
                                }
                              }
                              _load();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            if (!enabled) const PopupMenuItem(value: 'enable', child: Text('启用')),
                            if (enabled) const PopupMenuItem(value: 'disable', child: Text('禁用')),
                            const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除', style: TextStyle(color: cs.error)),
                            ),
                          ],
                        ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
