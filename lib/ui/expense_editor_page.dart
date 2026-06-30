import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
import '../services/photo_picker_helper.dart';
import 'formatters.dart';
import 'image_viewer_page.dart';

class ExpenseEditorPage extends StatefulWidget {
  const ExpenseEditorPage({
    super.key,
    required this.trip,
    required this.category,
    this.indexInCategory,
  });

  final TripLedger trip;
  final ExpenseCategory category;
  final int? indexInCategory;

  @override
  State<ExpenseEditorPage> createState() => _ExpenseEditorPageState();
}

class _ExpenseEditorPageState extends State<ExpenseEditorPage> {
  final _uuid = const Uuid();
  late TripLedger _trip;
  late TextEditingController _title;
  late TextEditingController _amount;
  PaymentSource _pay = PaymentSource.cash;
  bool _reimbursable = false;
  List<String> _attachments = [];

  List<int> _indicesForCategory() {
    final out = <int>[];
    for (var i = 0; i < _trip.expenses.length; i++) {
      if (_trip.expenses[i].category == widget.category) out.add(i);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _trip = widget.trip.copy();
    final indices = _indicesForCategory();
    final idxInCat = widget.indexInCategory;
    if (idxInCat != null && idxInCat < indices.length) {
      final e = _trip.expenses[indices[idxInCat]];
      _title = TextEditingController(text: e.title);
      _amount = TextEditingController(text: e.amount.toString());
      if (widget.category == ExpenseCategory.toll) {
        _pay = e.paymentSource == PaymentSource.etc ? PaymentSource.etc : PaymentSource.cash;
      } else {
        _pay = e.paymentSource;
      }
      _reimbursable = e.isReimbursable;
      _attachments = List<String>.from(e.attachments);
    } else {
      switch (widget.category) {
        case ExpenseCategory.fuel:
          _title = TextEditingController(text: '油费');
          _pay = PaymentSource.cash;
          break;
        case ExpenseCategory.toll:
          _title = TextEditingController(text: '高速费');
          _pay = PaymentSource.etc;
          break;
        case ExpenseCategory.other:
          _title = TextEditingController(text: '其他费用');
          _pay = PaymentSource.cash;
          break;
      }
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

  Future<void> _openImage(String name) async {
    final f = await AttachmentStore.fileFor(name);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => ImageViewerPage(path: f.path)),
    );
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

    final cat = widget.category;
    var reimb = _reimbursable;
    if (cat != ExpenseCategory.other) reimb = false;
    if (_pay != PaymentSource.cash) reimb = false;

    final PaymentSource payForItem;
    double tollCash;
    double tollEtc;
    if (cat == ExpenseCategory.toll) {
      final tollPay = _pay == PaymentSource.etc ? PaymentSource.etc : PaymentSource.cash;
      payForItem = tollPay;
      tollCash = tollPay == PaymentSource.cash ? amount : 0;
      tollEtc = tollPay == PaymentSource.etc ? amount : 0;
    } else {
      payForItem = _pay;
      tollCash = 0;
      tollEtc = 0;
    }

    final indices = _indicesForCategory();
    final idxInCat = widget.indexInCategory;
    final ExpenseItem? existing =
        (idxInCat != null && idxInCat < indices.length) ? _trip.expenses[indices[idxInCat]] : null;

    final item = ExpenseItem(
      id: existing?.id ?? _uuid.v4(),
      category: cat,
      title: title,
      amount: amount,
      paymentSource: payForItem,
      isReimbursable: reimb,
      attachments: _attachments,
      createdAt: existing?.createdAt ?? DateTime.now(),
      tollCashAmount: tollCash,
      tollEtcAmount: tollEtc,
    );

    if (idxInCat != null && idxInCat < indices.length) {
      _trip.expenses[indices[idxInCat]] = item;
    } else {
      _trip.expenses.add(item);
    }
    Navigator.pop(context, _trip);
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    return Scaffold(
      appBar: AppBar(
        title: Text(cat.label),
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
          const SizedBox(height: 12),
          Text('${cat.label}支付方式', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cat == ExpenseCategory.toll)
            SegmentedButton<PaymentSource>(
              segments: const [
                ButtonSegment(value: PaymentSource.cash, label: Text('现金')),
                ButtonSegment(value: PaymentSource.etc, label: Text('ETC')),
              ],
              selected: {_pay},
              onSelectionChanged: (s) => setState(() => _pay = s.first),
            )
          else
            SegmentedButton<PaymentSource>(
              segments: const [
                ButtonSegment(value: PaymentSource.cash, label: Text('现金')),
                ButtonSegment(value: PaymentSource.companyAccount, label: Text('公司账户')),
              ],
              selected: {_pay},
              onSelectionChanged: (s) {
                setState(() {
                  _pay = s.first;
                  if (cat == ExpenseCategory.other && _pay != PaymentSource.cash) {
                    _reimbursable = false;
                  }
                });
              },
            ),
          if (cat == ExpenseCategory.toll) ...[
            const SizedBox(height: 8),
            Text(
              '请选择现金或 ETC。若同一笔同时含现金与 ETC，请新增两条高速费分别记录。选择 ETC 时，将按 ETC 金额的 0.35% 加计对账手续费（计入利润与公司侧支出）。',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
          if (cat == ExpenseCategory.other) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('老板报销承担（仅现金）'),
              subtitle: const Text(
                '开启后：计入本圈费用与五五分成（你承担一半）；'
                '发工资时老板还你其应承担的一半',
              ),
              value: _reimbursable,
              onChanged: _pay == PaymentSource.cash
                  ? (v) {
                      setState(() {
                        _reimbursable = v;
                        if (v) _pay = PaymentSource.cash;
                      });
                    }
                  : null,
            ),
          ],
          const SizedBox(height: 16),
          const Text('凭证图片', style: TextStyle(fontWeight: FontWeight.w600)),
          ListTile(
            leading: const Icon(Icons.add_photo_alternate),
            title: const Text('从相册添加'),
            onTap: _addPhotos,
          ),
          for (var i = 0; i < _attachments.length; i++)
            ListTile(
              title: Text('图片 ${i + 1}'),
              subtitle: Text(_attachments[i], maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final name = _attachments[i];
                  await AttachmentStore.deleteFile(name);
                  setState(() => _attachments.remove(name));
                },
              ),
              onTap: () => _openImage(_attachments[i]),
            ),
        ],
      ),
    );
  }
}
