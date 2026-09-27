import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
import '../services/editor_draft_store.dart';
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

class _AdvanceEditorPageState extends State<AdvanceEditorPage>
    with WidgetsBindingObserver, EditorDraftMixin {
  final _uuid = const Uuid();
  late TripLedger _trip;
  late TextEditingController _title;
  late TextEditingController _amount;
  List<String> _attachments = [];
  bool _saved = false;

  @override
  String get draftKey => EditorDraftStore.key(
        tripId: widget.trip.id,
        kind: 'advance',
        slot: widget.advanceIndex?.toString(),
      );

  @override
  Map<String, dynamic> captureDraft() => {
        'title': _title.text,
        'amount': _amount.text,
        'attachments': _attachments,
      };

  @override
  void applyDraft(Map<String, dynamic> data) {
    _title.text = '${data['title'] ?? ''}';
    _amount.text = '${data['amount'] ?? ''}';
    final att = data['attachments'];
    if (att is List) {
      _attachments = att.map((e) => '$e').toList();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    for (final c in [_title, _amount]) {
      c.addListener(scheduleDraftSave);
    }
    initDraftBanner();
  }

  @override
  void dispose() {
    if (!_saved) {
      flushDraft();
    }
    disposeDraft();
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final names = await pickAndSaveAttachmentPhotos(context);
    if (names.isEmpty) return;
    setState(() => _attachments.addAll(names));
    scheduleDraftSave();
  }

  void _err(String m) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(title: const Text('输入有误'), content: Text(m), actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定')),
      ]),
    );
  }

  Future<void> _save() async {
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
    _saved = true;
    await clearDraft();
    if (!mounted) return;
    Navigator.pop(context, _trip);
  }

  @override
  Widget build(BuildContext context) {
    final banner = buildDraftBanner();
    return Scaffold(
      appBar: AppBar(
        title: const Text('现金支取'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: Column(
        children: [
          ?banner,
          Expanded(
            child: ListView(
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
                    scheduleDraftSave();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
