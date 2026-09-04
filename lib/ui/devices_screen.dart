import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../services/device_id_service.dart';
import '../services/devices_api.dart';
import '../state/auth_controller.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = true;
  String? _error;
  List<DeviceInfo> _devices = [];
  String? _thisDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().devicesApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final thisId = await DeviceIdService.getOrCreate();
      final list = await api.list();
      if (!mounted) return;
      setState(() {
        _thisDeviceId = thisId;
        _devices = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _revoke(DeviceInfo d) async {
    final api = context.read<AuthController>().devicesApi;
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('吊销设备'),
        content: Text(
          d.deviceId == _thisDeviceId
              ? '这是当前设备。吊销后本机下次打开可能被拦截，需重新登录注册设备。确定？'
              : '确定吊销该设备？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('吊销')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.revoke(d.deviceId);
      if (d.deviceId == _thisDeviceId && mounted) {
        await context.read<AuthController>().logout();
        return;
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录设备'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _devices.isEmpty
                  ? const Center(child: Text('暂无设备记录（下次控制检查后会出现）'))
                  : ListView.separated(
                      itemCount: _devices.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final d = _devices[i];
                        final isThis = d.deviceId == _thisDeviceId;
                        final seen = d.lastSeenAt > 0
                            ? fmt.format(DateTime.fromMillisecondsSinceEpoch(d.lastSeenAt))
                            : '—';
                        return ListTile(
                          leading: Icon(
                            isThis ? Icons.smartphone : Icons.devices_other,
                            color: d.status == 'ACTIVE'
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            isThis ? '本机 · ${d.platform}' : d.platform,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '版本 ${d.appVersion.isEmpty ? "—" : d.appVersion}\n'
                            '状态 ${d.status} · 最近 $seen\n'
                            '${d.deviceId}',
                          ),
                          isThreeLine: true,
                          trailing: d.status == 'ACTIVE'
                              ? TextButton(
                                  onPressed: () => _revoke(d),
                                  child: const Text('吊销'),
                                )
                              : null,
                        );
                      },
                    ),
    );
  }
}
