import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../ui/admin_widgets.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final _min = TextEditingController();
  final _latest = TextEditingController();
  final _apk = TextEditingController();
  final _ios = TextEditingController();
  final _notes = TextEditingController();
  final _maintenance = TextEditingController();
  final _announcement = TextEditingController();
  final _offlineGrace = TextEditingController();
  final _trialDays = TextEditingController();
  final _trialRounds = TextEditingController();
  final _trialAttach = TextEditingController();
  final _adminMin = TextEditingController();
  final _adminLatest = TextEditingController();
  final _adminApk = TextEditingController();
  final _adminIos = TextEditingController();
  final _adminLinux = TextEditingController();
  final _adminWin = TextEditingController();
  final _adminNotes = TextEditingController();
  String _force = '0';
  String _adminForce = '0';
  String _status = 'ACTIVE';
  String _expiry = 'readonly';
  bool _registration = true;
  bool _ffExcel = true;
  bool _ffBackup = true;
  bool _ffMessages = true;
  bool _ffWeb = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _min, _latest, _apk, _ios, _notes, _maintenance, _announcement,
      _offlineGrace, _trialDays, _trialRounds, _trialAttach,
      _adminMin, _adminLatest, _adminApk, _adminIos, _adminLinux, _adminWin, _adminNotes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AdminSession>().api.allSettings();
      _min.text = '${s['min_version'] ?? ''}';
      _latest.text = '${s['latest_version'] ?? ''}';
      _apk.text = '${s['apk_download_url'] ?? ''}';
      _ios.text = '${s['ios_download_url'] ?? ''}';
      _notes.text = '${s['update_release_notes'] ?? ''}';
      _force = '${s['force_update'] ?? '0'}';
      _status = '${s['app_status'] ?? 'ACTIVE'}';
      _maintenance.text = '${s['maintenance_message'] ?? ''}';
      _announcement.text = '${s['announcement'] ?? ''}';
      _offlineGrace.text = '${s['offline_grace_sec'] ?? ''}';
      _trialDays.text = '${s['trial_days'] ?? ''}';
      _trialRounds.text = '${s['trial_max_rounds'] ?? ''}';
      _trialAttach.text = '${s['trial_max_attachments'] ?? ''}';
      _expiry = '${s['expiry_policy'] ?? 'readonly'}';
      _registration = '${s['registration_enabled'] ?? '1'}' == '1';
      _adminMin.text = '${s['admin_min_version'] ?? ''}';
      _adminLatest.text = '${s['admin_latest_version'] ?? ''}';
      _adminApk.text = '${s['admin_apk_download_url'] ?? ''}';
      _adminIos.text = '${s['admin_ios_download_url'] ?? ''}';
      _adminLinux.text = '${s['admin_linux_download_url'] ?? ''}';
      _adminWin.text = '${s['admin_windows_download_url'] ?? ''}';
      _adminNotes.text = '${s['admin_update_release_notes'] ?? ''}';
      _adminForce = '${s['admin_force_update'] ?? '0'}';
      try {
        final ff = jsonDecode('${s['feature_flags'] ?? '{}'}');
        if (ff is Map) {
          _ffExcel = ff['excel_export'] != false;
          _ffBackup = ff['backup_import'] != false;
          _ffMessages = ff['messages'] != false;
          _ffWeb = ff['web_ledger'] != false;
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    final api = context.read<AdminSession>().api;
    try {
      final pairs = <String, String>{
        'registration_enabled': _registration ? '1' : '0',
        'app_status': _status,
        'maintenance_message': _maintenance.text.trim(),
        'announcement': _announcement.text.trim(),
        'offline_grace_sec': _offlineGrace.text.trim(),
        'trial_days': _trialDays.text.trim(),
        'trial_max_rounds': _trialRounds.text.trim(),
        'trial_max_attachments': _trialAttach.text.trim(),
        'expiry_policy': _expiry,
        'feature_flags': jsonEncode({
          'excel_export': _ffExcel,
          'backup_import': _ffBackup,
          'messages': _ffMessages,
          'web_ledger': _ffWeb,
        }),
        'min_version': _min.text.trim(),
        'latest_version': _latest.text.trim(),
        'force_update': _force,
        'apk_download_url': _apk.text.trim(),
        'ios_download_url': _ios.text.trim(),
        'update_release_notes': _notes.text.trim(),
        'admin_min_version': _adminMin.text.trim(),
        'admin_latest_version': _adminLatest.text.trim(),
        'admin_force_update': _adminForce,
        'admin_apk_download_url': _adminApk.text.trim(),
        'admin_ios_download_url': _adminIos.text.trim(),
        'admin_linux_download_url': _adminLinux.text.trim(),
        'admin_windows_download_url': _adminWin.text.trim(),
        'admin_update_release_notes': _adminNotes.text.trim(),
      };
      for (final e in pairs.entries) {
        await api.setSetting(e.key, e.value);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存全部控制面设置')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 13);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        PageHeader(
          title: '控制面',
          subtitle: '修改后点底部「保存全部」。下载地址仅供更新包，勿写入司机可见文案。',
          trailing: FilledButton.icon(
            onPressed: _saving ? null : _saveAll,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存全部'),
          ),
        ),
        _panel(
          title: '注册与试用',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开放用户注册'),
              value: _registration,
              onChanged: (v) => setState(() => _registration = v),
            ),
            TextField(controller: _trialDays, decoration: const InputDecoration(labelText: '试用天数')),
            const SizedBox(height: 10),
            TextField(controller: _trialRounds, decoration: const InputDecoration(labelText: '试用圈次上限（0 不限）')),
            const SizedBox(height: 10),
            TextField(controller: _trialAttach, decoration: const InputDecoration(labelText: '试用附件上限（0 不限）')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _expiry,
              decoration: const InputDecoration(labelText: '到期策略'),
              items: const [
                DropdownMenuItem(value: 'readonly', child: Text('只读')),
                DropdownMenuItem(value: 'block', child: Text('禁止登录')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _expiry = v);
              },
            ),
          ],
        ),
        _panel(
          title: '公告与状态',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: '应用状态'),
              items: const [
                DropdownMenuItem(value: 'ACTIVE', child: Text('运行')),
                DropdownMenuItem(value: 'MAINTENANCE', child: Text('维护')),
                DropdownMenuItem(value: 'DISABLED', child: Text('停用')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _status = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: _maintenance, decoration: const InputDecoration(labelText: '维护文案')),
            const SizedBox(height: 10),
            TextField(
              controller: _announcement,
              decoration: const InputDecoration(labelText: '全局公告'),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            TextField(controller: _offlineGrace, decoration: const InputDecoration(labelText: '离线宽限秒数')),
          ],
        ),
        _panel(
          title: '功能开关',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Excel / 报表导出'),
              value: _ffExcel,
              onChanged: (v) => setState(() => _ffExcel = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('备份导入导出'),
              value: _ffBackup,
              onChanged: (v) => setState(() => _ffBackup = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('消息中心'),
              value: _ffMessages,
              onChanged: (v) => setState(() => _ffMessages = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Web 账本入口提示'),
              value: _ffWeb,
              onChanged: (v) => setState(() => _ffWeb = v),
            ),
          ],
        ),
        _panel(
          title: '司机端版本与下载',
          children: [
            TextField(controller: _min, decoration: const InputDecoration(labelText: '最低版本'), style: mono),
            const SizedBox(height: 10),
            TextField(
              controller: _latest,
              decoration: const InputDecoration(labelText: '最新版本（如 1.2.0+45）'),
              style: mono,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _force,
              decoration: const InputDecoration(labelText: '强制升级'),
              items: const [
                DropdownMenuItem(value: '0', child: Text('否')),
                DropdownMenuItem(value: '1', child: Text('是')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _force = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apk,
              decoration: const InputDecoration(
                labelText: 'APK 下载地址',
                helperText: '发行版 App 不会向司机展示域名',
              ),
              style: mono,
            ),
            const SizedBox(height: 10),
            TextField(controller: _ios, decoration: const InputDecoration(labelText: 'IPA 下载地址'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: '更新说明'), maxLines: 3),
          ],
        ),
        _panel(
          title: '管理端版本与下载',
          children: [
            TextField(controller: _adminMin, decoration: const InputDecoration(labelText: '最低版本'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _adminLatest, decoration: const InputDecoration(labelText: '最新版本'), style: mono),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _adminForce,
              decoration: const InputDecoration(labelText: '强制升级'),
              items: const [
                DropdownMenuItem(value: '0', child: Text('否')),
                DropdownMenuItem(value: '1', child: Text('是')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _adminForce = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: _adminApk, decoration: const InputDecoration(labelText: 'APK'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _adminIos, decoration: const InputDecoration(labelText: 'IPA'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _adminLinux, decoration: const InputDecoration(labelText: 'Linux'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _adminWin, decoration: const InputDecoration(labelText: 'Windows'), style: mono),
            const SizedBox(height: 10),
            TextField(controller: _adminNotes, decoration: const InputDecoration(labelText: '更新说明'), maxLines: 2),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _saveAll,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? '保存中…' : '保存全部设置'),
        ),
      ],
    );
  }

  Widget _panel({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: title.contains('注册') || title.contains('公告'),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );
  }
}
