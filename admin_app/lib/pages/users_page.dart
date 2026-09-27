import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../ui/admin_labels.dart';
import '../ui/admin_widgets.dart';
import '../user_ledger_page.dart';
import '../user_ops_page.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> _users = [];
  String? _err;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final list = await context.read<AdminSession>().api.users();
      if (mounted) {
        setState(() {
          _users = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _act(int id, String action, {Map<String, dynamic>? body}) async {
    final api = context.read<AdminSession>().api;
    try {
      final msg = await api.userAction(id, action, body: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final hay = '${u['id']} ${u['username']} ${u['license_plate'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = context.watch<AdminSession>().admin?.can('users.delete') == true;
    final cs = Theme.of(context).colorScheme;

    if (_loading && _users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 200, child: LinearProgressIndicator()),
            SizedBox(height: 12),
            Text('加载用户列表…'),
          ],
        ),
      );
    }
    if (_err != null && _users.isEmpty) {
      return ErrorBanner(message: _err!, onRetry: _load);
    }

    final list = _filtered;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PageHeader(
            title: '用户',
            subtitle: '查看账本、延期试用与账号运维',
            trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索用户名、车牌或 ID',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            EmptyState(
              icon: Icons.people_outline,
              title: _users.isEmpty ? '暂无用户' : '无匹配用户',
              detail: _users.isEmpty ? '新注册用户会出现在这里' : '试试其他关键词',
            )
          else
            ...list.map((u) {
              final id = (u['id'] as num).toInt();
              final plate = '${u['license_plate'] ?? ''}'.trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              plate.isEmpty ? '${u['username']}' : '${u['username']} · $plate',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${AdminLabels.status(u['status'])} · ${AdminLabels.plan(u['plan'])}'
                              ' · 圈次 ${u['round_count']} · rev ${u['revision']}',
                            ),
                            onTap: () => _openLedger(u),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _openLedger(u),
                          child: const Text('账本'),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          onSelected: (v) => _onMenu(v, u, id, canDelete),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'ops', child: Text('快照与设备')),
                            const PopupMenuItem(value: 'extend', child: Text('延期试用 14 天')),
                            const PopupMenuItem(value: 'convert', child: Text('转正式')),
                            const PopupMenuItem(value: 'kick', child: Text('踢下线')),
                            const PopupMenuItem(value: 'enable', child: Text('启用')),
                            const PopupMenuItem(value: 'disable', child: Text('禁用')),
                            const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                            if (canDelete)
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除用户', style: TextStyle(color: cs.error)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _openLedger(Map<String, dynamic> u) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => UserLedgerPage(user: u)),
    );
  }

  Future<void> _onMenu(String v, Map<String, dynamic> u, int id, bool canDelete) async {
    if (v == 'ops') {
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => UserOpsPage(user: u)),
      );
      return;
    }
    if (v == 'extend') {
      await _act(id, 'extend', body: {'days': 14});
    } else if (v == 'convert') {
      await _act(id, 'convert');
    } else if (v == 'kick') {
      await _act(id, 'kick');
    } else if (v == 'disable') {
      await _act(id, 'disable');
    } else if (v == 'enable') {
      await _act(id, 'enable');
    } else if (v == 'delete' && canDelete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('删除用户'),
          content: Text('确定永久删除「${u['username']}」及其云端账本数据？此操作不可撤销。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          final msg = await context.read<AdminSession>().api.deleteUser(id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            _load();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      }
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
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('确定')),
          ],
        ),
      );
      if (pass != null && pass.length >= 6) {
        await _act(id, 'reset-password', body: {'password': pass});
      }
    }
  }
}
