import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/attachment_store.dart';
import '../services/photo_picker_helper.dart';
import 'formatters.dart';
import 'image_viewer_page.dart';

enum _FuelField { amount, kg, price }

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
  late TextEditingController _fuelKg;
  late TextEditingController _fuelPrice;
  PaymentSource _pay = PaymentSource.cash;
  bool _reimbursable = false;
  List<String> _attachments = [];
  bool _fuelSyncing = false;

  List<int> _indicesForCategory() {
    final out = <int>[];
    for (var i = 0; i < _trip.expenses.length; i++) {
      if (_trip.expenses[i].category == widget.category) out.add(i);
    }
    return out;
  }

  String _fmtNum(double v, {int maxFrac = 3}) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(maxFrac);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  double _roundMoney(double v) => (v * 100).roundToDouble() / 100;
  double _roundKg(double v) => (v * 1000).roundToDouble() / 1000;

  void _setController(TextEditingController c, double? v, {int maxFrac = 3}) {
    final next = v == null ? '' : _fmtNum(v, maxFrac: maxFrac);
    if (c.text == next) return;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// 任意填两项，自动算出未填项；三项都有时，按刚改的那一项推算关联值。
  void _syncFuelFrom(_FuelField changed) {
    if (_fuelSyncing || widget.category != ExpenseCategory.fuel) return;
    final a = parseAmount(_amount.text);
    final k = parseAmount(_fuelKg.text);
    final p = parseAmount(_fuelPrice.text);
    final filled = [a != null, k != null, p != null].where((x) => x).length;
    if (filled < 2) return;

    double? nextA = a;
    double? nextK = k;
    double? nextP = p;

    if (filled == 2) {
      if (a == null && k != null && p != null) {
        nextA = _roundMoney(k * p);
      } else if (k == null && a != null && p != null && p != 0) {
        nextK = _roundKg(a / p);
      } else if (p == null && a != null && k != null && k != 0) {
        nextP = _roundMoney(a / k);
      }
    } else {
      switch (changed) {
        case _FuelField.amount:
          if (k != null && k != 0) {
            nextP = _roundMoney(a! / k);
          } else if (p != null && p != 0) {
            nextK = _roundKg(a! / p);
          }
          break;
        case _FuelField.kg:
          if (p != null) {
            nextA = _roundMoney(k! * p);
          } else if (a != null && k != null && k != 0) {
            nextP = _roundMoney(a / k);
          }
          break;
        case _FuelField.price:
          if (k != null) {
            nextA = _roundMoney(k * p!);
          } else if (a != null && p != null && p != 0) {
            nextK = _roundKg(a / p);
          }
          break;
      }
    }

    _fuelSyncing = true;
    _setController(_amount, nextA, maxFrac: 2);
    _setController(_fuelKg, nextK, maxFrac: 3);
    _setController(_fuelPrice, nextP, maxFrac: 3);
    _fuelSyncing = false;
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
      _fuelKg = TextEditingController(
        text: e.fuelKilograms > 0 ? _fmtNum(e.fuelKilograms) : '',
      );
      _fuelPrice = TextEditingController(
        text: e.fuelUnitPrice > 0 ? _fmtNum(e.fuelUnitPrice) : '',
      );
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
      _fuelKg = TextEditingController();
      _fuelPrice = TextEditingController();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _fuelKg.dispose();
    _fuelPrice.dispose();
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
      _err('金额请输入数字（或填公斤数与单价自动算出）');
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

    double fuelKg = 0;
    double fuelPrice = 0;
    if (cat == ExpenseCategory.fuel) {
      fuelKg = parseAmount(_fuelKg.text) ?? 0;
      fuelPrice = parseAmount(_fuelPrice.text) ?? 0;
      if (fuelKg < 0 || fuelPrice < 0) {
        _err('公斤数与单价不能为负数');
        return;
      }
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
      fuelKilograms: fuelKg,
      fuelUnitPrice: fuelPrice,
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
            decoration: InputDecoration(
              labelText: '金额',
              helperText: cat == ExpenseCategory.fuel ? '可与公斤数、单价互相推算' : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: cat == ExpenseCategory.fuel
                ? (_) => _syncFuelFrom(_FuelField.amount)
                : null,
          ),
          if (cat == ExpenseCategory.fuel) ...[
            TextField(
              controller: _fuelKg,
              decoration: const InputDecoration(
                labelText: '公斤数',
                suffixText: 'kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _syncFuelFrom(_FuelField.kg),
            ),
            TextField(
              controller: _fuelPrice,
              decoration: const InputDecoration(
                labelText: '单价',
                suffixText: '元/kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _syncFuelFrom(_FuelField.price),
            ),
            const SizedBox(height: 4),
            Text(
              '任意填写其中两项，自动算出第三项（金额 = 公斤数 × 单价）。',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
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
