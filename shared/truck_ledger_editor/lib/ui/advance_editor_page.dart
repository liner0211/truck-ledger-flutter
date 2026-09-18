import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
import '../services/photo_picker_helper.dart';
import 'formatters.dart';
import 'widgets/attachment_thumb_strip.dart';

class AdvanceEditorPage extends StatefulWidget {
  const AdvanceEditorPage({super.key, required this.trip, this.advanceIndex});

  final TripLedger trip;
  final int? advanceIndex;

  @override
  State<AdvanceEditorPage> createState() => _AdvanceEditorPageState();
}

class _AdvanceEditorPageState extends State<AdvanceEditorPage> {
  final _uuid = const Uuid();
  late TripLedger _trip;
  late TextEditingController _title;
  late TextEditingController _amount;
  List<String> _attachments = [];

  @override
  void initState() {
    super.initState();
    _trip = widget.trip.copy();
    final idx = widget.advanceIndex;
    if (idx != null && idx >= 0 && idx < _trip.cashAdvances.length) {
      final a = _trip.cashAdvances[idx];
      _title = TextEditingController(text: a.title);
      _amount = TextEditingController(text: a.amount.toString());
      _attachments = List<String>.from(a.attachments);
    } else {
      _title = TextEditingController(text: '出车费');
      _amount = TextEditingController();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final names = await pickAndSaveAttachmentPhotos(context);
    if (names.isEmpty) return;
    setState(() => _attachments.addAll(names));
  }

  void _err(String m) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(title: const Text('输入有误'), content: Text(m), actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定')),
      ]),
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _err('标题不能为空');
      return;
    }
    final amount = parseAmount(_amount.text);
    if (amount == null) {
      _err('金额请输入数字');
      return;
    }
    final idx = widget.advanceIndex;
    final CashAdvance? existing =
        (idx != null && idx < _trip.cashAdvances.length) ? _trip.cashAdvances[idx] : null;
    final item = CashAdvance(
      id: existing?.id ?? _uuid.v4(),
      title: title,
      amount: amount,
      attachments: _attachments,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    if (idx != null && idx < _trip.cashAdvances.length) {
      _trip.cashAdvances[idx] = item;
    } else {
      _trip.cashAdvances.add(item);
    }
    Navigator.pop(context, _trip);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('现金支取'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: '金额'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          const Text('凭证图片', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AttachmentThumbStrip(
            names: _attachments,
            onAdd: _addPhotos,
            onRemove: (name) async {
              await AttachmentStore.deleteFile(name);
              setState(() => _attachments.remove(name));
            },
          ),
        ],
      ),
    );
  }
}
