import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
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

class _RouteEditorPageState extends State<RouteEditorPage> {
  final _uuid = const Uuid();
  late TripLedger _trip;
  late TextEditingController _load;
  late TextEditingController _unload;
  late TextEditingController _freight;
  late TextEditingController _infoFee;
  late TextEditingController _note;
  PaymentSource _infoPay = PaymentSource.cash;
  List<String> _attachments = [];

  @override
  void initState() {
    super.initState();
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
  }

  String _fmtFreight(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
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
  }

  void _save() {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('路线'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
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
            onSelectionChanged: (s) => setState(() => _infoPay = s.first),
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
            },
          ),
        ],
      ),
    );
  }
}
