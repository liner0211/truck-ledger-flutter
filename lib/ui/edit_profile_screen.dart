import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../state/auth_controller.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _plate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _plate = TextEditingController(text: auth.licensePlate ?? '');
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final plate = _plate.text.trim();
    if (plate.isEmpty) {
      setState(() => _error = '请填写车牌号');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().updateLicensePlate(plate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已保存')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(title: const Text('修改资料')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
            child: Text(auth.username ?? '—'),
          ),
          const SizedBox(height: 8),
          Text(
            '用户名注册后不可修改。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '车牌号',
              hintText: '如 京A12345',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
