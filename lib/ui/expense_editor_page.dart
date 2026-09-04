import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 用户亲手改过的字段：自动推算时不得覆盖；清空后解除锁定。
  final Set<_FuelField> _fuelManual = {};

  static final _decimalFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]*'));

  List<int> _indicesForCategory() {
    final out = <int>[];
    for (var i = 0; i < _trip.expenses.length; i++) {
      if (_trip.expenses[i].category == widget.category) out.add(i);
    }
    return out;
  }

  String _fmtNum(double v, {int maxFrac = 4}) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(maxFrac);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  double _roundMoney(double v) => (v * 100).roundToDouble() / 100;
  double _roundKg(double v) => (v * 10000).roundToDouble() / 10000;

  void _setAutoController(TextEditingController c, double v, {int maxFrac = 4}) {
    final next = _fmtNum(v, maxFrac: maxFrac);
    if (c.text == next) return;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// 只给「非手动」且当前为空/可推算的字段填值；手动填过的数字一律不动。
  void _syncFuelFrom(_FuelField changed, String raw) {
    if (_fuelSyncing || widget.category != ExpenseCategory.fuel) return;

    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _fuelManual.remove(changed);
    } else {
      _fuelManual.add(changed);
    }

    final a = parseAmount(_amount.text);
    final k = parseAmount(_fuelKg.text);
    final p = parseAmount(_fuelPrice.text);

    double? autoA;
    double? autoK;
    double? autoP;

    // 恰好两项有值时，只填「非手动」的第三项
    if (k != null && p != null && a == null && !_fuelManual.contains(_FuelField.amount)) {
      autoA = _roundMoney(k * p);
    } else if (a != null && p != null && k == null && !_fuelManual.contains(_FuelField.kg) && p != 0) {
      autoK = _roundKg(a / p);
    } else if (a != null && k != null && p == null && !_fuelManual.contains(_FuelField.price) && k != 0) {
      autoP = _roundMoney(a / k);
    } else if (a != null && k != null && p != null) {
      // 三项都有值：改动某一项时，只更新仍非手动的关联项
      switch (changed) {
        case _FuelField.amount:
          if (!_fuelManual.contains(_FuelField.price) && k != 0) {
            autoP = _roundMoney(a / k);
          } else if (!_fuelManual.contains(_FuelField.kg) && p != 0) {
            autoK = _roundKg(a / p);
          }
          break;
        case _FuelField.kg:
          if (!_fuelManual.contains(_FuelField.amount)) {
            autoA = _roundMoney(k * (p));
          } else if (!_fuelManual.contains(_FuelField.price) && k != 0) {
            autoP = _roundMoney(a / k);
          }
          break;
        case _FuelField.price:
          if (!_fuelManual.contains(_FuelField.amount)) {
            autoA = _roundMoney(k * p);
          } else if (!_fuelManual.contains(_FuelField.kg) && p != 0) {
            autoK = _roundKg(a / p);
          }
          break;
      }
    }

    _fuelSyncing = true;
    if (autoA != null && !_fuelManual.contains(_FuelField.amount)) {
      _setAutoController(_amount, autoA, maxFrac: 2);
    }
    if (autoK != null && !_fuelManual.contains(_FuelField.kg)) {
      _setAutoController(_fuelKg, autoK, maxFrac: 4);
    }
    if (autoP != null && !_fuelManual.contains(_FuelField.price)) {
      _setAutoController(_fuelPrice, autoP, maxFrac: 4);
    }
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
      // 编辑已有记录：标题原样；油费已有数字视为用户确认过的手动值
      _title = TextEditingController(text: e.title);
      _amount = TextEditingController(
        text: e.amount != 0 ? _fmtNum(e.amount, maxFrac: 2) : '',
      );
      _fuelKg = TextEditingController(
        text: e.fuelKilograms > 0 ? _fmtNum(e.fuelKilograms) : '',
      );
      _fuelPrice = TextEditingController(
        text: e.fuelUnitPrice > 0 ? _fmtNum(e.fuelUnitPrice) : '',
      );
      if (_amount.text.isNotEmpty) _fuelManual.add(_FuelField.amount);
      if (_fuelKg.text.isNotEmpty) _fuelManual.add(_FuelField.kg);
      if (_fuelPrice.text.isNotEmpty) _fuelManual.add(_FuelField.price);
      if (widget.category == ExpenseCategory.toll) {
        _pay = e.paymentSource == PaymentSource.etc ? PaymentSource.etc : PaymentSource.cash;
      } else {
        _pay = e.paymentSource;
      }
      _reimbursable = e.isReimbursable;
      _attachments = List<String>.from(e.attachments);
    } else {
      // 新建：标题留空，仅用 hint 提示类别名
      _title = TextEditingController();
      switch (widget.category) {
        case ExpenseCategory.fuel:
          _pay = PaymentSource.cash;
          break;
        case ExpenseCategory.toll:
          _pay = PaymentSource.etc;
          break;
        case ExpenseCategory.other:
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
    final cat = widget.category;
    var title = _title.text.trim();
    if (title.isEmpty) title = cat.label;

    final amount = parseAmount(_amount.text);
    if (amount == null) {
      _err('金额请输入数字（或填公斤数与单价自动算出）');
      return;
    }

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
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: '标题',
              hintText: cat.label,
            ),
          ),
          TextField(
            controller: _amount,
            decoration: InputDecoration(
              labelText: '金额',
              hintText: cat == ExpenseCategory.fuel ? '可自动算出' : null,
              helperText: cat == ExpenseCategory.fuel
                  ? '手动填过的数字不会被覆盖；清空后可再自动生成'
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: cat == ExpenseCategory.fuel ? [_decimalFilter] : null,
            onChanged: cat == ExpenseCategory.fuel
                ? (v) => _syncFuelFrom(_FuelField.amount, v)
                : null,
          ),
          if (cat == ExpenseCategory.fuel) ...[
            TextField(
              controller: _fuelKg,
              decoration: const InputDecoration(
                labelText: '公斤数',
                hintText: '支持小数，如 12.5',
                suffixText: 'kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_decimalFilter],
              onChanged: (v) => _syncFuelFrom(_FuelField.kg, v),
            ),
            TextField(
              controller: _fuelPrice,
              decoration: const InputDecoration(
                labelText: '单价',
                hintText: '可自动算出',
                suffixText: '元/kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_decimalFilter],
              onChanged: (v) => _syncFuelFrom(_FuelField.price, v),
            ),
            const SizedBox(height: 4),
            Text(
              '任意填写其中两项，仅自动填充未手动填写的那一项（金额 = 公斤数 × 单价）。',
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
