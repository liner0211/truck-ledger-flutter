import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../realtime_socket.dart';
import '../ui/admin_labels.dart';
import '../ui/admin_widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _audits = [];
  String? _err;
  bool _loading = true;

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
      final api = context.read<AdminSession>().api;
      final d = await api.dashboard();
      List<Map<String, dynamic>> audits = const [];
      try {
        audits = await api.audits(limit: 30);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _data = d;
          _audits = audits;
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

  String _fmtMs(dynamic ms) {
    final n = (ms is num) ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (n <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(n);
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null && _data == null) {
      return ErrorBanner(message: _err!, onRetry: _load);
    }
    final data = _data!;
    final stats = (data['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final health = (data['health'] as Map?)?.cast<String, dynamic>() ?? {};
    final settings = (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final checks = (health['checks'] as Map?)?.cast<String, dynamic>() ?? {};
    final ws = (data['websocket'] as Map?)?.cast<String, dynamic>() ??
        (health['websocket'] as Map?)?.cast<String, dynamic>() ??
        {};
    final canControl = context.watch<AdminSession>().admin?.can('control.write') == true;
    final rtState = context.watch<AdminSession>().realtime.connectionState.value;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PageHeader(
            title: '总览',
            subtitle: '系统健康与近期运维动态',
            trailing: IconButton(
              tooltip: '刷新',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cols = w >= 900 ? 4 : (w >= 560 ? 2 : 2);
              final itemW = (w - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: itemW,
                    child: StatCard(
                      label: '用户',
                      value: '${stats['user_count'] ?? '—'}',
                      icon: Icons.people_outline,
                    ),
                  ),
                  SizedBox(
                    width: itemW,
                    child: StatCard(
                      label: '圈次',
                      value: '${stats['round_count'] ?? '—'}',
                      icon: Icons.route_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemW,
                    child: StatCard(
                      label: '设备',
                      value: '${stats['device_count'] ?? '—'}',
                      icon: Icons.phone_android_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemW,
                    child: StatCard(
                      label: '站内信',
                      value: '${stats['message_count'] ?? '—'}',
                      icon: Icons.mail_outline,
                    ),
                  ),
                  if (stats['attachment_count'] != null)
                    SizedBox(
                      width: itemW,
                      child: StatCard(
                        label: '附件',
                        value: '${stats['attachment_count']}',
                        icon: Icons.attach_file,
                      ),
                    ),
                  if (stats['data_size_mb'] != null)
                    SizedBox(
                      width: itemW,
                      child: StatCard(
                        label: '数据 (MB)',
                        value: '${stats['data_size_mb']}',
                        icon: Icons.storage_outlined,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          AdminSection(
            title: '实时通道 (WebSocket)',
            subtitle: ws['ok'] == true ? '枢纽运行中' : '枢纽未运行（消息仍可用，无实时推送）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('枢纽', ws['ok'] == true
                    ? '在线 · 连接 ${ws['clients'] ?? 0}（管理 ${ws['admins'] ?? 0} / 用户 ${ws['users'] ?? 0}）'
                    : '离线 · ${ws['error'] ?? 'unreachable'}'),
                _kv(
                  '本端 App',
                  rtState == RealtimeConnState.online
                      ? '已连接'
                      : (rtState == RealtimeConnState.connecting ? '连接中' : '未连接'),
                ),
                _kv('端口', '${ws['port'] ?? 8765}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AdminSection(
            title: '系统健康',
            subtitle: '状态：${AdminLabels.status(health['status'])}',
            child: checks.isEmpty
                ? const Text('暂无检查项')
                : Column(
                    children: [
                      for (final e in checks.entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(AdminLabels.healthKey(e.key)),
                          trailing: Text(AdminLabels.healthValue(e.value)),
                        ),
                    ],
                  ),
          ),
          if (canControl) ...[
            const SizedBox(height: 20),
            AdminSection(
              title: '控制面快照',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('应用状态', AdminLabels.appStatus(settings['app_status'])),
                  _kv(
                    '开放注册',
                    AdminLabels.yesNoFlag(settings['registration_enabled']),
                  ),
                  _kv('最低版本', '${settings['min_version'] ?? '—'}'),
                  _kv('最新版本', '${settings['latest_version'] ?? '—'}'),
                  _kv('强制升级', AdminLabels.yesNoFlag(settings['force_update'])),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          AdminSection(
            title: '最近审计',
            padding: EdgeInsets.zero,
            child: _audits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyState(
                      icon: Icons.history,
                      title: '暂无审计记录',
                      detail: '运维操作后会显示在这里',
                    ),
                  )
                : Column(
                    children: [
                      for (final a in _audits.take(20))
                        ListTile(
                          dense: true,
                          title: Text(
                            '${a['action'] ?? ''} · ${a['target_type'] ?? ''} ${a['target_id'] ?? ''}',
                          ),
                          subtitle: Text(_fmtMs(a['created_at'])),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
