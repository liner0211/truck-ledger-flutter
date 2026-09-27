import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'admin_session.dart';

/// 用户快照恢复 + 设备吊销（对齐网页 /admin/users/{id}/ops）。
class UserOpsPage extends StatefulWidget {
  const UserOpsPage({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<UserOpsPage> createState() => _UserOpsPageState();
}

class _UserOpsPageState extends State<UserOpsPage> {
  List<Map<String, dynamic>> _snapshots = [];
  List<Map<String, dynamic>> _devices = [];
  String? _err;
  bool _loading = true;

  int get _userId => (widget.user['id'] as num).toInt();
  String get _username => '${widget.user['username'] ?? ''}';

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
    final api = context.read<AdminSession>().api;
    try {
      final snaps = await api.userSnapshots(_userId);
      final devices = await api.userDevices(_userId);
      if (!mounted) return;
      setState(() {
        _snapshots = snaps;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  String _fmtMs(dynamic ms) {
    final n = (ms is num) ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (n <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(n);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSession>().admin;
    final canRestore = admin?.can('snapshots.restore') == true;
    final canRevoke = admin?.can('devices.write') == true;

    return Scaffold(
      appBar: AppBar(
        title: Text('快照与设备 · $_username'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '状态 ${widget.user['status']} · 套餐 ${widget.user['plan']} · 本页管理快照与登录设备',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text('账本快照', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_snapshots.isEmpty)
                        const Card(child: ListTile(title: Text('暂无快照')))
                      else
                        ..._snapshots.map((s) {
                          final id = (s['id'] as num).toInt();
                          return Card(
                            child: ListTile(
                              title: Text('rev ${s['revision']} · #$id'),
                              subtitle: Text(
                                '${_fmtMs(s['created_at'])}${s['note'] != null && '${s['note']}'.isNotEmpty ? ' · ${s['note']}' : ''}',
                              ),
                              trailing: canRestore
                                  ? FilledButton.tonal(
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('恢复快照'),
                                            content: const Text('确定恢复到该快照？当前账本会再自动存一份快照。'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(c, false),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(c, true),
                                                child: const Text('恢复'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true || !mounted) return;
                                        try {
                                          await context
                                              .read<AdminSession>()
                                              .api
                                              .restoreUserSnapshot(_userId, id);
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('已恢复快照')),
                                          );
                                          _load();
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                        }
                                      },
                                      child: const Text('恢复'),
                                    )
                                  : Text(
                                      '仅开发者',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      Text('登录设备', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_devices.isEmpty)
                        const Card(child: ListTile(title: Text('暂无设备记录')))
                      else
                        ..._devices.map((d) {
                          final deviceId = '${d['device_id'] ?? ''}';
                          final status = '${d['status'] ?? ''}';
                          final active = status == 'ACTIVE';
                          return Card(
                            child: ListTile(
                              title: Text(deviceId, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${d['platform']} · ${d['app_version']} · $status\n最近 ${_fmtMs(d['last_seen_at'])}',
                              ),
                              isThreeLine: true,
                              trailing: active && canRevoke
                                  ? FilledButton.tonal(
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('吊销设备'),
                                            content: const Text('吊销后该设备下次控制检查将被拦截。'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(c, false),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(c, true),
                                                child: const Text('吊销'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true || !mounted) return;
                                        try {
                                          final msg = await context
                                              .read<AdminSession>()
                                              .api
                                              .revokeUserDevice(_userId, deviceId);
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(msg)),
                                          );
                                          _load();
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                        }
                                      },
                                      child: const Text('吊销'),
                                    )
                                  : Text(
                                      active ? '仅开发者' : '—',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
