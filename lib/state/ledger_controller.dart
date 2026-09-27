import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/auth_api.dart';
import '../services/ledger_store.dart';
import '../services/sync_service.dart';
import '../state/auth_controller.dart';

/// 与 `RootViewController` 行为对齐：总览列表、排序、持久化。
class LedgerController extends ChangeNotifier {
  LedgerController({LedgerStore? store}) : _store = store ?? LedgerStore();

  static const sortKey = 'TruckLedger.roundSortAscending';

  final LedgerStore _store;
  final _uuid = const Uuid();
  final _startFmt = DateFormat('yyyy-MM-dd HH:mm');

  AuthController? _auth;
  bool _cloudPushPending = false;
  SyncStatus _syncStatus = SyncStatus.idle;
  String? _syncError;
  RemoteLedger? _conflictServer;
  double? _syncProgress;
  String _syncProgressMessage = '';

  LedgerBook _book = LedgerBook.empty();
  bool _sortAscending = true;
  bool _loaded = false;

  LedgerBook get book => _book;
  bool get sortAscending => _sortAscending;
  bool get isLoaded => _loaded;
  SyncStatus get syncStatus => _syncStatus;
  String? get syncError => _syncError;
  RemoteLedger? get conflictServer => _conflictServer;
  bool get writeAllowed => _auth?.writeAllowed ?? true;
  /// 0~1；null 表示不确定进度（仅显示动画条）。
  double? get syncProgress => _syncProgress;
  String get syncProgressMessage => _syncProgressMessage;

  void _setSyncProgress(SyncProgress p) {
    _syncProgress = p.fraction;
    _syncProgressMessage = p.message;
    notifyListeners();
  }

  void _clearSyncProgress() {
    _syncProgress = null;
    _syncProgressMessage = '';
  }

  void attachAuth(AuthController auth) {
    _auth = auth;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _sortAscending = prefs.getBool(sortKey) ?? true;
    _book = await _store.load();
    _sortRounds();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    if (!writeAllowed) {
      _syncStatus = SyncStatus.error;
      _syncError = '账号只读，无法保存到云端';
      notifyListeners();
      return;
    }
    await _store.save(_book);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _auth?.setLocalUpdatedAt(now);
    _syncStatus = SyncStatus.dirty;
    _syncError = null;
    notifyListeners();
    _queueCloudPush();
  }

  void _queueCloudPush() {
    if (_cloudPushPending) return;
    final sync = _auth?.syncService;
    if (sync == null) return;
    if (!writeAllowed) return;
    _cloudPushPending = true;
    _syncStatus = SyncStatus.pending;
    _setSyncProgress(const SyncProgress(fraction: 0, message: '正在同步…'));
    Future<void>(() async {
      try {
        final base = _auth?.localRevision ?? 0;
        final result = await sync.pushFull(
          _book,
          baseRevision: base,
          onProgress: _setSyncProgress,
        );
        await _auth?.setRemoteUpdatedAt(result.updatedAt);
        await _auth?.setLocalUpdatedAt(result.updatedAt);
        await _auth?.setLocalRevision(result.revision);
        _syncStatus = SyncStatus.synced;
        _syncError = null;
        _conflictServer = null;
      } on SyncConflictException catch (e) {
        _syncStatus = SyncStatus.conflict;
        _conflictServer = e.server;
        _syncError = '云端有更新的版本，请处理冲突';
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          await _auth?.logout();
        }
        _syncStatus = SyncStatus.error;
        _syncError = e.message;
      } catch (e) {
        _syncStatus = SyncStatus.error;
        _syncError = '同步失败：$e';
      } finally {
        _cloudPushPending = false;
        _clearSyncProgress();
        notifyListeners();
      }
    });
  }

  Future<String> pushToCloud({bool force = false}) async {
    final sync = _auth?.syncService;
    if (sync == null) return '请先登录';
    if (!writeAllowed && !force) return '账号只读，无法上传';
    try {
      _syncStatus = SyncStatus.pending;
      _setSyncProgress(const SyncProgress(fraction: 0, message: '准备上传…'));
      final base = _auth?.localRevision ?? 0;
      final result = await sync.pushFull(
        _book,
        baseRevision: base,
        force: force,
        onProgress: _setSyncProgress,
      );
      await _auth?.setRemoteUpdatedAt(result.updatedAt);
      await _auth?.setLocalUpdatedAt(result.updatedAt);
      await _auth?.setLocalRevision(result.revision);
      _syncStatus = SyncStatus.synced;
      _conflictServer = null;
      _syncError = null;
      _clearSyncProgress();
      notifyListeners();
      return '已上传到云端（${_book.rounds.length} 个圈次，rev ${result.revision}）';
    } on SyncConflictException catch (e) {
      _syncStatus = SyncStatus.conflict;
      _conflictServer = e.server;
      _syncError = '版本冲突';
      _clearSyncProgress();
      notifyListeners();
      return '云端与本机冲突，请选择保留本机或采用云端';
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _auth?.logout();
      _syncStatus = SyncStatus.error;
      _syncError = e.message;
      _clearSyncProgress();
      notifyListeners();
      return e.message;
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = '$e';
      _clearSyncProgress();
      notifyListeners();
      return '上传失败：$e';
    }
  }

  Future<String> pullFromCloud() async {
    final sync = _auth?.syncService;
    if (sync == null) return '请先登录';
    try {
      _syncStatus = SyncStatus.pending;
      _setSyncProgress(const SyncProgress(fraction: 0, message: '准备拉取…'));
      final remote = await sync.pullFull(onProgress: _setSyncProgress);
      await _applyRemoteBook(remote);
      _syncStatus = SyncStatus.synced;
      _conflictServer = null;
      _clearSyncProgress();
      notifyListeners();
      return '已从云端拉取（${remote.book.rounds.length} 个圈次，rev ${remote.revision}）';
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _auth?.logout();
      _syncStatus = SyncStatus.error;
      _syncError = e.message;
      _clearSyncProgress();
      notifyListeners();
      return e.message;
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = '$e';
      _clearSyncProgress();
      notifyListeners();
      return '拉取失败：$e';
    }
  }

  Future<String> resolveConflictKeepLocal() => pushToCloud(force: true);

  Future<String> resolveConflictTakeRemote() async {
    final remote = _conflictServer;
    if (remote == null) return '无冲突数据';
    final sync = _auth?.syncService;
    if (sync != null) {
      _syncStatus = SyncStatus.pending;
      _setSyncProgress(const SyncProgress(fraction: 0.1, message: '下载云端附件…'));
      await sync.downloadMissingAttachments(remote.book, onProgress: _setSyncProgress);
    }
    await _applyRemoteBook(remote);
    _syncStatus = SyncStatus.synced;
    _conflictServer = null;
    _clearSyncProgress();
    notifyListeners();
    return '已采用云端版本（rev ${remote.revision}）';
  }

  Future<String> syncWithCloud() async {
    final auth = _auth;
    final sync = auth?.syncService;
    if (sync == null) return '请先登录';
    try {
      final wasDirty =
          _syncStatus == SyncStatus.dirty || _syncStatus == SyncStatus.error;
      _syncStatus = SyncStatus.pending;
      _setSyncProgress(const SyncProgress(fraction: 0.05, message: '检查云端版本…'));
      final remote = await sync.pull();
      final localAt = await auth!.readLocalUpdatedAt();
      final remoteAt = remote.updatedAt;
      final localRev = auth.localRevision;

      if (remote.revision != localRev && _book.rounds.isNotEmpty && localAt > 0) {
        // 本地可能有未推送修改
        if (wasDirty) {
          _syncStatus = SyncStatus.conflict;
          _conflictServer = remote;
          _clearSyncProgress();
          notifyListeners();
          return '云端与本机版本不同，请选择「上传」或「拉取」';
        }
      }

      if (remote.revision > localRev ||
          (remoteAt > localAt && (_book.rounds.isEmpty || localAt == 0))) {
        await sync.downloadMissingAttachments(remote.book, onProgress: _setSyncProgress);
        await _applyRemoteBook(remote);
        _syncStatus = SyncStatus.synced;
        _clearSyncProgress();
        notifyListeners();
        return '已用云端较新版本覆盖本机（${remote.book.rounds.length} 个圈次）';
      }

      if (localRev >= remote.revision) {
        return await pushToCloud();
      }

      _syncStatus = SyncStatus.synced;
      _clearSyncProgress();
      notifyListeners();
      return '已是最新';
    } on ApiException catch (e) {
      if (e.statusCode == 401) await auth?.logout();
      _syncStatus = SyncStatus.error;
      _syncError = e.message;
      _clearSyncProgress();
      notifyListeners();
      return e.message;
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = '$e';
      _clearSyncProgress();
      notifyListeners();
      return '同步失败：$e';
    }
  }

  Future<void> _applyRemoteBook(RemoteLedger incoming) async {
    _book = LedgerBook(
      rounds: incoming.book.rounds.map((e) => e.copy()).toList(),
    );
    _sortRounds();
    await _store.save(_book);
    await _auth?.setRemoteUpdatedAt(incoming.updatedAt);
    await _auth?.setLocalUpdatedAt(incoming.updatedAt);
    await _auth?.setLocalRevision(incoming.revision);
    notifyListeners();
  }

  Future<void> toggleSortOrder() async {
    _sortAscending = !_sortAscending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sortKey, _sortAscending);
    _sortRounds();
    await _persist();
  }

  DateTime _sortDate(TripLedger trip) {
    final s = trip.startPlace.trim();
    try {
      return _startFmt.parse(s);
    } catch (_) {
      return trip.createdAt;
    }
  }

  void _sortRounds() {
    _book.rounds.sort((a, b) {
      final da = _sortDate(a);
      final db = _sortDate(b);
      final cmp = da.compareTo(db);
      if (cmp != 0) {
        return _sortAscending ? cmp : -cmp;
      }
      final c2 = a.createdAt.compareTo(b.createdAt);
      return _sortAscending ? c2 : -c2;
    });
  }

  Future<String?> _guardWrite() async {
    if (!writeAllowed) return '账号已到期或被限制，当前为只读';
    return null;
  }

  Future<void> addRound(String startPlace, String endPlace) async {
    final err = await _guardWrite();
    if (err != null) return;
    var round = TripLedger.empty(_uuid.v4());
    round.startPlace = startPlace;
    round.endPlace = endPlace;
    round.title = makeTripTitle(startPlace, endPlace);
    _book.rounds.add(round);
    _sortRounds();
    await _persist();
  }

  /// 复制最近一圈的路线结构（新 ID、清空凭证、重置交账/工资）。
  Future<TripLedger?> copyLatestRoundTemplate() async {
    final err = await _guardWrite();
    if (err != null) return null;
    if (_book.rounds.isEmpty) return null;
    final sorted = List<TripLedger>.from(_book.rounds)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final src = sorted.first;
    final clone = _cloneTripWithFreshIds(src, _uuid.v4());
    clone.isReconciled = false;
    clone.isSalarySettled = false;
    clone.createdAt = DateTime.now();
    for (final leg in clone.routeLegs) {
      leg.attachments = [];
    }
    for (final e in clone.expenses) {
      e.attachments = [];
    }
    for (final a in clone.cashAdvances) {
      a.attachments = [];
    }
    // 只保留路线；费用与支取清空，避免误把上一圈金额带过来（常走线主要复用装卸地）
    clone.expenses = [];
    clone.cashAdvances = [];
    clone.title = makeTripTitle(clone.startPlace, clone.endPlace);
    _book.rounds.add(clone);
    _sortRounds();
    await _persist();
    return clone;
  }

  Future<void> replaceTrip(TripLedger updated) async {
    final err = await _guardWrite();
    if (err != null) return;
    final idx = _book.rounds.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    _book.rounds[idx] = updated;
    _sortRounds();
    await _persist();
  }

  Future<void> deleteTripAt(int index) async {
    final err = await _guardWrite();
    if (err != null) return;
    if (index < 0 || index >= _book.rounds.length) return;
    _book.rounds.removeAt(index);
    await _persist();
  }

  Future<void> importReplace(LedgerBook incoming) async {
    final err = await _guardWrite();
    if (err != null) return;
    _book = LedgerBook(
      rounds: incoming.rounds.map((e) => e.copy()).toList(),
    );
    _sortRounds();
    await _persist();
  }

  Future<void> importMerge(LedgerBook incoming) async {
    final err = await _guardWrite();
    if (err != null) return;
    final existingIds = _book.rounds.map((r) => r.id).toSet();
    for (final trip in incoming.rounds) {
      final TripLedger toAdd;
      if (existingIds.contains(trip.id)) {
        toAdd = _cloneTripWithFreshIds(trip, _uuid.v4());
        existingIds.add(toAdd.id);
      } else {
        toAdd = trip.copy();
        existingIds.add(toAdd.id);
      }
      _book.rounds.add(toAdd);
    }
    _sortRounds();
    await _persist();
  }

  TripLedger _cloneTripWithFreshIds(TripLedger src, String newTripId) {
    return TripLedger(
      id: newTripId,
      title: src.title,
      startPlace: src.startPlace,
      endPlace: src.endPlace,
      createdAt: src.createdAt,
      isReconciled: src.isReconciled,
      isSalarySettled: src.isSalarySettled,
      routeLegs: src.routeLegs
          .map(
            (l) => RouteLeg(
              id: _uuid.v4(),
              loadPlace: l.loadPlace,
              unloadPlace: l.unloadPlace,
              freight: l.freight,
              freightExpression: l.freightExpression,
              infoFee: l.infoFee,
              infoFeePaymentSource: l.infoFeePaymentSource,
              note: l.note,
              attachments: List<String>.from(l.attachments),
              createdAt: l.createdAt,
            ),
          )
          .toList(),
      expenses: src.expenses
          .map(
            (e) => ExpenseItem(
              id: _uuid.v4(),
              category: e.category,
              title: e.title,
              amount: e.amount,
              paymentSource: e.paymentSource,
              isReimbursable: e.isReimbursable,
              attachments: List<String>.from(e.attachments),
              createdAt: e.createdAt,
              tollCashAmount: e.tollCashAmount,
              tollEtcAmount: e.tollEtcAmount,
              fuelKilograms: e.fuelKilograms,
              fuelUnitPrice: e.fuelUnitPrice,
              fuelUnitPriceExpression: e.fuelUnitPriceExpression,
            ),
          )
          .toList(),
      cashAdvances: src.cashAdvances
          .map(
            (a) => CashAdvance(
              id: _uuid.v4(),
              title: a.title,
              amount: a.amount,
              attachments: List<String>.from(a.attachments),
              createdAt: a.createdAt,
            ),
          )
          .toList(),
    );
  }

  String money(double v) => '¥${v.toStringAsFixed(2)}';
}
