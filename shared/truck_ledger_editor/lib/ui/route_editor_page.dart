import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
import '../services/editor_draft_store.dart';
import '../services/photo_picker_helper.dart';
import 'formatters.dart';
import 'widgets/attachment_thumb_strip.dart';

class RouteEditorPage extends StatefulWidget {
  const RouteEditorPage({
    super.key,
    required this.trip,
    this.legIndex,
  });

  final TripLedger trip;
  final int? legIndex;

  @override
  State<RouteEditorPage> createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage>
    with WidgetsBindingObserver, EditorDraftMixin {
  final _uuid = const Uuid();
  late TripLedger _trip;
  late TextEditingController _load;
  late TextEditingController _unload;
  late TextEditingController _freight;
  late TextEditingController _infoFee;
  late TextEditingController _note;
  PaymentSource _infoPay = PaymentSource.cash;
  List<String> _attachments = [];
  bool _saved = false;

  @override
  String get draftKey => EditorDraftStore.key(
        tripId: widget.trip.id,
        kind: 'route',
        slot: widget.legIndex?.toString(),
      );

  @override
  Map<String, dynamic> captureDraft() => {
        'load': _load.text,
        'unload': _unload.text,
        'freight': _freight.text,
        'infoFee': _infoFee.text,
        'note': _note.text,
        'infoPay': _infoPay.name,
        'attachments': _attachments,
      };

  @override
  void applyDraft(Map<String, dynamic> data) {
    _load.text = '${data['load'] ?? ''}';
    _unload.text = '${data['unload'] ?? ''}';
    _freight.text = '${data['freight'] ?? ''}';
    _infoFee.text = '${data['infoFee'] ?? ''}';
    _note.text = '${data['note'] ?? ''}';
    final payName = '${data['infoPay'] ?? ''}';
    _infoPay = PaymentSource.values.firstWhere(
      (e) => e.name == payName,
      orElse: () => PaymentSource.cash,
    );
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
    final idx = widget.legIndex;
    if (idx != null && idx >= 0 && idx < _trip.routeLegs.length) {
      final r = _trip.routeLegs[idx];
      _load = TextEditingController(text: r.loadPlace);
      _unload = TextEditingController(text: r.unloadPlace);
      _freight = TextEditingController(
        text: r.freightExpression.isNotEmpty
            ? r.freightExpression
            : (r.freight == 0 ? '' : _fmtFreight(r.freight)),
      );
      _infoFee = TextEditingController(text: r.infoFee.toString());
      _note = TextEditingController(text: r.note);
      _infoPay = r.infoFeePaymentSource;
      _attachments = List<String>.from(r.attachments);
    } else {
      _load = TextEditingController();
      _unload = TextEditingController();
      _freight = TextEditingController();
      _infoFee = TextEditingController();
      _note = TextEditingController();
    }
    _freight.addListener(() => setState(() {}));
    for (final c in [_load, _unload, _freight, _infoFee, _note]) {
      c.addListener(scheduleDraftSave);
    }
    initDraftBanner();
  }

  String _fmtFreight(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    if (!_saved) {
      flushDraft();
    }
    disposeDraft();
    _load.dispose();
    _unload.dispose();
    _freight.dispose();
    _infoFee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final names = await pickAndSaveAttachmentPhotos(context);
    if (names.isEmpty) return;
    setState(() => _attachments.addAll(names));
    scheduleDraftSave();
  }

  Future<void> _save() async {
    final load = _load.text.trim();
    final unload = _unload.text.trim();
    if (load.isEmpty || unload.isEmpty) {
      _err('装货地/卸货地不能为空');
      return;
    }
    final rawFreight = _freight.text.trim();
    final freight = parseAmountOrExpression(rawFreight);
    if (freight == null) {
      _err('运费请输入数字或运算式（如 32*280、8000*3%）');
      return;
    }
    final infoFee = parseAmount(_infoFee.text) ?? 0;
    final plain = parseAmount(rawFreight);
    final freightExpression = plain == null ? rawFreight : '';

    final idx = widget.legIndex;
    final RouteLeg item;
    if (idx != null && idx < _trip.routeLegs.length) {
      final old = _trip.routeLegs[idx];
      item = RouteLeg(
        id: old.id,
        loadPlace: load,
        unloadPlace: unload,
        freight: freight,
        freightExpression: freightExpression,
        infoFee: infoFee,
        infoFeePaymentSource: _infoPay,
        note: _note.text.trim(),
        attachments: _attachments,
        createdAt: old.createdAt,
      );
      _trip.routeLegs[idx] = item;
    } else {
      item = RouteLeg(
        id: _uuid.v4(),
        loadPlace: load,
        unloadPlace: unload,
        freight: freight,
        freightExpression: freightExpression,
        infoFee: infoFee,
        infoFeePaymentSource: _infoPay,
        note: _note.text.trim(),
        attachments: _attachments,
        createdAt: DateTime.now(),
      );
      _trip.routeLegs.add(item);
    }
    _saved = true;
    await clearDraft();
    if (!mounted) return;
    Navigator.pop(context, _trip);
  }

  void _err(String m) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('输入有误'),
        content: Text(m),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final freightPreview = parseAmountOrExpression(_freight.text);
    final showPreview = _freight.text.trim().isNotEmpty &&
        parseAmount(_freight.text) == null &&
        freightPreview != null;
    final banner = buildDraftBanner();

    return Scaffold(
      appBar: AppBar(
        title: const Text('路线'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: Column(
        children: [
          ?banner,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _load,
                  decoration: const InputDecoration(labelText: '装货地'),
                ),
                TextField(
                  controller: _unload,
                  decoration: const InputDecoration(labelText: '卸货地'),
                ),
                TextField(
                  controller: _freight,
                  decoration: InputDecoration(
                    labelText: '运费',
                    hintText: '数字，或 吨位*单价、金额*百分点%',
                    helperText: showPreview
                        ? '计算结果：${freightPreview.toStringAsFixed(2)}'
                        : '支持 + - * / ( ) 与 %，例：32*280、8000*3%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                TextField(
                  controller: _infoFee,
                  decoration: const InputDecoration(labelText: '信息费（可不填，默认 0）'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                const SizedBox(height: 16),
                const Text('信息费支付方式', style: TextStyle(fontWeight: FontWeight.w600)),
                SegmentedButton<PaymentSource>(
                  segments: const [
                    ButtonSegment(value: PaymentSource.cash, label: Text('现金')),
                    ButtonSegment(
                      value: PaymentSource.companyAccount,
                      label: Text('公司账户'),
                    ),
                  ],
                  selected: {_infoPay},
                  onSelectionChanged: (s) {
                    setState(() => _infoPay = s.first);
                    scheduleDraftSave();
                  },
                ),
                const SizedBox(height: 24),
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
