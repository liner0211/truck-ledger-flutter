/* 卡车记账 Web 端 — 与 Flutter App 功能对齐 */
(function () {
  'use strict';

  const SWIFT_REF = 978307200;
  const INFO_PAY = ['现金', '公司账户'];
  const FUEL_OTHER_PAY = ['现金', '公司账户'];
  const TOLL_PAY = ['现金', 'ETC'];

  const cfg = Object.assign({ mode: 'user', userId: 0 }, window.LEDGER_APP_CONFIG || {});
  // 管理端：优先配置，否则从 URL /admin/users/{id}/… 解析，避免 user_id/id 字段不一致导致串账
  if (cfg.mode === 'admin') {
    const fromUrl = Number(((location.pathname || '').match(/\/admin\/users\/(\d+)/) || [])[1] || 0);
    cfg.userId = Number(cfg.userId || 0) || fromUrl;
  }
  const isAdmin = cfg.mode === 'admin';

  function encodeSwiftDate(d) {
    const t = d instanceof Date ? d : new Date(d);
    return t.getTime() / 1000 - SWIFT_REF;
  }

  function decodeSwiftDate(v) {
    if (v == null) return new Date();
    if (typeof v === 'string') {
      const p = Date.parse(v);
      return Number.isNaN(p) ? new Date() : new Date(p);
    }
    if (typeof v === 'number') return new Date((v + SWIFT_REF) * 1000);
    return new Date();
  }

  function parseTripDateTime(s) {
    const m = /^(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{2}):(\d{2}))?$/.exec((s || '').trim());
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0));
  }

  function fmtTripDateTime(d) {
    const x = d instanceof Date ? d : new Date(d);
    const pad = (n) => String(n).padStart(2, '0');
    return `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())} ${pad(x.getHours())}:${pad(x.getMinutes())}`;
  }

  function toDatetimeLocalValue(s) {
    const d = parseTripDateTime(s) || new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  function fromDatetimeLocalValue(v) {
    if (!v) return '';
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? '' : fmtTripDateTime(d);
  }

  function fmtDate(d) {
    return fmtTripDateTime(d instanceof Date ? d : new Date(d));
  }

  function money(n) {
    const v = Number(n) || 0;
    return '¥' + v.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  function parseAmount(s) {
    const t = String(s ?? '').trim();
    if (!t) return null;
    const v = Number(t);
    return Number.isFinite(v) && /^-?\d+(\.\d+)?$/.test(t.replace(/,/g, '.'))
      ? Number(t.replace(/,/g, '.'))
      : null;
  }

  function parseAmountOrExpression(s) {
    const plain = parseAmount(s);
    if (plain != null) return plain;
    return typeof tryEvalExpression === 'function' ? tryEvalExpression(s) : null;
  }

  function routePreview(round) {
    const legs = round.routeLegs || [];
    if (!legs.length) return '路线：暂无';
    const parts = legs.map((l) => {
      const a = (l.loadPlace || '').trim();
      const b = (l.unloadPlace || '').trim();
      if (!a && !b) return null;
      if (!a) return b;
      if (!b) return a;
      return `${a} → ${b}`;
    }).filter(Boolean);
    return parts.length ? `路线：${parts.join(' ｜ ')}` : '路线：暂无';
  }

  function fmtKg(kg) {
    const n = Number(kg) || 0;
    if (Math.abs(n - Math.round(n)) < 0.000001) return String(Math.round(n));
    return String(n).replace(/\.?0+$/, '');
  }

  function uuid() {
    if (crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  function makeTripTitle(start, end) {
    const s = (start || '').trim();
    const e = (end || '').trim();
    if (s && e) return `${s} ~ ${e}`;
    return s || e || '新建圈次';
  }

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s == null ? '' : String(s);
    return d.innerHTML;
  }

  function normalizeLicensePlate(raw) {
    const p = String(raw ?? '').trim().toUpperCase().replace(/[\s·.]/g, '');
    if (p.length < 5 || p.length > 10) return null;
    if (!/^[\u4e00-\u9fa5]/.test(p)) return null;
    if (!/^[\u4e00-\u9fa5A-Z0-9]+$/.test(p)) return null;
    return p;
  }

  function reconcileText(v) {
    if (v > 0.000001) return `老板补你 ${money(v)}`;
    if (v < -0.000001) return `你退老板 ${money(-v)}`;
    return '无差额';
  }

  function collectAttachmentNames(book) {
    const names = new Set();
    (book.rounds || []).forEach((trip) => {
      [...(trip.routeLegs || []), ...(trip.expenses || []), ...(trip.cashAdvances || [])].forEach((item) => {
        (item.attachments || []).forEach((n) => names.add(n));
      });
    });
    return names;
  }

  function expenseIndices(trip, category) {
    const out = [];
    (trip.expenses || []).forEach((e, i) => {
      if (e.category === category) out.push(i);
    });
    return out;
  }

  function tollSubtitle(item) {
    const parts = [];
    if ((item.tollCashAmount || 0) > 0.000001) parts.push(`现金 ${money(item.tollCashAmount)}`);
    if ((item.tollEtcAmount || 0) > 0.000001) parts.push(`ETC ${money(item.tollEtcAmount)}`);
    const sum = money(item.amount);
    if (!parts.length) return `${sum} · ${item.paymentSource}`;
    return `${sum}（${parts.join('，')}）· ${item.paymentSource}`;
  }

  function fuelSubtitle(item) {
    const parts = [money(item.amount)];
    if ((item.fuelKilograms || 0) > 0.000001) parts.push(`${item.fuelKilograms} kg`);
    if ((item.fuelUnitPrice || 0) > 0.000001) parts.push(`${money(item.fuelUnitPrice)}/kg`);
    parts.push(item.paymentSource);
    return parts.join(' · ');
  }

  function summaryBody(sum) {
    const etcLine = sum.etcTollReconcileFee > 0.000001
      ? `高速ETC对账手续费(0.35%)：${money(sum.etcTollReconcileFee)}（已计入费用总与分成）\n` : '';
    const reimbLine = sum.reimbursableCashExpense > 0.000001
      ? `其中可报销(现金)：${money(sum.reimbursableCashExpense)}（已计入费用总；你承担一半 ${money(sum.reimbursableCashExpense - sum.reimbursableOwnerShare)}，老板承担一半 ${money(sum.reimbursableOwnerShare)}）\n` : '';
    const travelLine = `出车费差额：${reconcileText(sum.travelCashReconcile)}（现金花费 ${money(sum.cashTotalExpense)} − 已支取 ${money(sum.cashAdvances)}）\n`;
    const wageLine = sum.reimbursableCashExpense > 0.000001
      ? `司机应发工资：${money(sum.driverWagePayable)}（分成 ${money(sum.driverShare)} + 老板还你 ${money(sum.reimbursableOwnerShare)}）\n` : '';
    const fuelDetail = (sum.fuelKilogramsTotal || 0) > 0.000001
      ? `油费 ${money(sum.fuelExpense)}（气耗 ${fmtKg(sum.fuelKilogramsTotal)} kg）`
      : `油费 ${money(sum.fuelExpense)}`;
    return `运费(总): ${money(sum.totalFreight)}    利润: ${money(sum.netProfit)}
费用(总): ${money(sum.totalExpense)}    分成: 司机 ${money(sum.driverShare)} / 老板 ${money(sum.ownerShare)}

费用明细：${fuelDetail}｜高速 ${money(sum.tollExpense)}｜其他 ${money(sum.otherExpense)}｜信息费 ${money(sum.totalInfoFee)}
${etcLine}${reimbLine}${travelLine}交账净额：${reconcileText(sum.cashNetSettlement)}（仅出车费差额）
${wageLine}`;
  }

  async function fileToJpegBlob(file) {
    if (file.type === 'image/jpeg') return file;
    const bmp = await createImageBitmap(file);
    const canvas = document.createElement('canvas');
    const max = 2400;
    let w = bmp.width;
    let h = bmp.height;
    if (w > max || h > max) {
      const scale = max / Math.max(w, h);
      w = Math.round(w * scale);
      h = Math.round(h * scale);
    }
    canvas.width = w;
    canvas.height = h;
    canvas.getContext('2d').drawImage(bmp, 0, 0, w, h);
    bmp.close();
    return new Promise((resolve, reject) => {
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('图片转换失败'))), 'image/jpeg', 0.9);
    });
  }

  class Api {
    constructor() {
      this.token = localStorage.getItem('truck_ledger_token') || '';
      this.username = localStorage.getItem('truck_ledger_username') || '';
      this.licensePlate = localStorage.getItem('truck_ledger_license_plate') || '';
    }

    setAuth(token, username, licensePlate) {
      this.token = token;
      this.username = username;
      if (licensePlate) this.licensePlate = licensePlate;
      localStorage.setItem('truck_ledger_token', token);
      localStorage.setItem('truck_ledger_username', username);
      if (licensePlate) localStorage.setItem('truck_ledger_license_plate', licensePlate);
    }

    saveLoginCredentials(username, password) {
      localStorage.setItem('truck_ledger_saved_username', username || '');
      localStorage.setItem('truck_ledger_saved_password', password || '');
    }

    readLoginCredentials() {
      return {
        username: localStorage.getItem('truck_ledger_saved_username') || '',
        password: localStorage.getItem('truck_ledger_saved_password') || '',
      };
    }

    clearAuth() {
      this.token = '';
      this.username = '';
      this.licensePlate = '';
      localStorage.removeItem('truck_ledger_token');
      localStorage.removeItem('truck_ledger_username');
      localStorage.removeItem('truck_ledger_license_plate');
    }

    authHeaders() {
      const h = {};
      if (!isAdmin && this.token) h.Authorization = 'Bearer ' + this.token;
      return h;
    }

    async request(path, opts = {}) {
      const headers = Object.assign({ 'Content-Type': 'application/json' }, opts.headers || {}, this.authHeaders());
      const res = await fetch(path, Object.assign({}, opts, {
        headers,
        credentials: 'same-origin',
      }));
      if (!res.ok) {
        let msg = `请求失败（${res.status}）`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
          if (res.status === 409) msg = (j.detail || '版本冲突') + '（409）';
        } catch (_) {}
        throw new Error(msg);
      }
      if (res.status === 204) return null;
      const ct = res.headers.get('content-type') || '';
      if (ct.includes('application/json')) return res.json();
      return res;
    }

    async login(username, password) {
      const r = await this.request('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ username, password }),
      });
      this.setAuth(r.token, r.username, r.license_plate || '');
      this.saveLoginCredentials(username, password);
      return r;
    }

    async register(username, password, licensePlate) {
      const r = await this.request('/api/auth/register', {
        method: 'POST',
        body: JSON.stringify({ username, password, license_plate: licensePlate }),
      });
      this.setAuth(r.token, r.username, r.license_plate || licensePlate || '');
      this.saveLoginCredentials(username, password);
      return r;
    }

    async me() {
      return this.request('/api/auth/me');
    }

    async fetchAuthConfig() {
      try {
        const r = await this.request('/api/auth/config');
        return { registration_enabled: !!r.registration_enabled };
      } catch (_) {
        return { registration_enabled: true };
      }
    }

    ledgerPath() {
      return isAdmin ? `/admin/api/users/${cfg.userId}/ledger` : '/api/ledger';
    }

    attachmentPath(name) {
      const enc = encodeURIComponent(name);
      return isAdmin
        ? `/admin/api/users/${cfg.userId}/attachments/${enc}`
        : `/api/attachments/${enc}`;
    }

    async getLedger() {
      return this.request(this.ledgerPath());
    }

    async putLedger(rounds, baseRevision, force) {
      const body = { rounds };
      if (baseRevision != null && baseRevision !== undefined) body.base_revision = baseRevision;
      if (force) body.force = true;
      return this.request(this.ledgerPath(), {
        method: 'PUT',
        body: JSON.stringify(body),
      });
    }

    async listRemoteAttachments() {
      if (isAdmin) {
        const ledger = await this.getLedger();
        const names = collectAttachmentNames({ rounds: ledger.rounds || [] });
        return names;
      }
      const r = await this.request('/api/attachments');
      return new Set(r.files || []);
    }

    async uploadAttachment(filename, blob) {
      const fd = new FormData();
      fd.append('file', blob, filename);
      const res = await fetch(this.attachmentPath(filename), {
        method: 'POST',
        headers: this.authHeaders(),
        credentials: 'same-origin',
        body: fd,
      });
      if (!res.ok) {
        let msg = `上传 ${filename} 失败（${res.status}）`;
        try {
          const j = await res.json();
          if (j.detail) msg = j.detail;
        } catch (_) {}
        throw new Error(msg);
      }
      return res.json();
    }

    async fetchAttachmentBlob(name) {
      const res = await fetch(this.attachmentPath(name), {
        headers: this.authHeaders(),
        credentials: 'same-origin',
      });
      if (!res.ok) throw new Error('附件加载失败');
      return URL.createObjectURL(await res.blob());
    }
  }

  class App {
    constructor(root) {
      this.root = root;
      this.api = new Api();
      this.book = { rounds: [] };
      this.updatedAt = 0;
      this.revision = 0;
      this.view = 'loading';
      this.selectedId = null;
      this.sortAsc = true;
      this.dirty = false;
      this.blobUrls = [];
      this.imageCache = new Map();
      this.pendingUploads = new Map();
      this.saving = false;
      this.syncStatus = '';
      this._registerMode = false;
      this._registrationEnabled = true;
      this._loginError = '';
      this._bootError = '';
    }

    applyLedgerPayload(data) {
      this.book = { rounds: (data && data.rounds) || [] };
      this.updatedAt = (data && data.updated_at) || 0;
      this.revision = (data && data.revision) || 0;
      this.sortRounds();
      this.dirty = false;
      this.pendingUploads.clear();
    }

    async start() {
      try {
        if (!isAdmin) {
          const cfg = await this.api.fetchAuthConfig();
          this._registrationEnabled = !!cfg.registration_enabled;
        }
        if (isAdmin) {
          if (!cfg.userId) {
            throw new Error('缺少用户 ID，无法打开账本');
          }
          // 管理端不使用普通用户 localStorage 登录态，避免串到 /api/ledger
          this.api.token = '';
          this.api.username = cfg.username || '';
          if (cfg.initialLedger && typeof cfg.initialLedger === 'object') {
            this.applyLedgerPayload(cfg.initialLedger);
          } else {
            await this.loadLedger();
          }
          // 再拉一次云端，确保与该 userId 一致
          try {
            await this.loadLedger();
          } catch (e) {
            if (!this.book.rounds.length) throw e;
            this.syncStatus = '已显示页面数据；刷新云端失败：' + (e.message || '');
          }
          this.view = 'home';
        } else if (this.api.token) {
          try {
            const me = await this.api.me();
            if (me && me.license_plate) {
              this.api.setAuth(this.api.token, this.api.username, me.license_plate);
            }
            await this.loadLedger();
            this.view = 'home';
          } catch (e) {
            this.api.clearAuth();
            this._loginError = e.message || '登录已失效或账号已被禁止';
            this.view = 'login';
          }
        } else {
          this.view = 'login';
        }
      } catch (e) {
        if (!isAdmin) this.api.clearAuth();
        this.view = isAdmin ? 'error' : 'login';
        if (isAdmin) this._bootError = e.message || '加载账本失败';
        if (!isAdmin) this._loginError = e.message || '启动失败';
      }
      this.render();
    }

    async loadLedger() {
      const data = await this.api.getLedger();
      this.applyLedgerPayload(data);
    }

    sortRounds() {
      this.book.rounds.sort((a, b) => {
        const da = parseTripDateTime(a.startPlace) || decodeSwiftDate(a.createdAt);
        const db = parseTripDateTime(b.startPlace) || decodeSwiftDate(b.createdAt);
        return this.sortAsc ? da - db : db - da;
      });
    }

    selectedTrip() {
      return this.book.rounds.find((r) => r.id === this.selectedId) || null;
    }

    markDirty() {
      this.dirty = true;
      this.syncStatus = '有未同步修改';
      const btn = document.getElementById('btn-save');
      if (btn) btn.disabled = false;
    }

    /** 与 App 每次编辑后 _commit 一致：自动上传并保存云端 */
    async commit() {
      await this.save({ quiet: true });
    }

    async save(opts = {}) {
      if (this.saving) return;
      this.saving = true;
      const btn = document.getElementById('btn-save');
      if (btn) { btn.disabled = true; btn.textContent = '保存中…'; }
      try {
        for (const [name, blob] of this.pendingUploads) {
          await this.api.uploadAttachment(name, blob);
        }
        const force = !!opts.force;
        const data = await this.api.putLedger(this.book.rounds, this.revision || 0, force);
        this.updatedAt = data.updated_at || Date.now();
        this.revision = data.revision != null ? data.revision : (this.revision || 0) + 1;
        this.pendingUploads.clear();
        this.dirty = false;
        this.syncStatus = `已同步 rev ${this.revision} · ${fmtDate(new Date(this.updatedAt))}`;
        if (!opts.quiet) this.toast('已保存到云端');
        this.render();
      } catch (e) {
        const msg = e.message || '保存失败';
        if (String(msg).includes('冲突') || String(msg).includes('409')) {
          this.toast('版本冲突：请刷新后重试，或强制覆盖');
          if (btn) {
            btn.disabled = false;
            btn.textContent = '强制保存';
            btn.onclick = () => this.save({ force: true });
          }
        } else {
          this.toast(msg);
          if (btn) { btn.disabled = false; btn.textContent = '保存'; }
        }
      } finally {
        this.saving = false;
      }
    }

    toast(msg) {
      let el = document.getElementById('toast');
      if (!el) {
        el = document.createElement('div');
        el.id = 'toast';
        el.className = 'toast';
        document.body.appendChild(el);
      }
      el.textContent = msg;
      el.classList.add('show');
      setTimeout(() => el.classList.remove('show'), 2800);
    }

    revokeBlobs() {
      this.blobUrls.forEach((u) => URL.revokeObjectURL(u));
      this.blobUrls = [];
      this.imageCache.clear();
    }

    getThumbUrl(name) {
      if (this.imageCache.has(name)) return this.imageCache.get(name);
      if (this.pendingUploads.has(name)) {
        const url = this.trackBlob(URL.createObjectURL(this.pendingUploads.get(name)));
        this.imageCache.set(name, url);
        return url;
      }
      return '';
    }

    async preloadAttachments(trip) {
      const names = new Set();
      [...(trip.routeLegs || []), ...(trip.expenses || []), ...(trip.cashAdvances || [])].forEach((item) => {
        (item.attachments || []).forEach((n) => names.add(n));
      });
      for (const name of names) {
        if (this.pendingUploads.has(name) || this.imageCache.has(name)) continue;
        try {
          const url = await this.api.fetchAttachmentBlob(name);
          this.imageCache.set(name, url);
          this.blobUrls.push(url);
        } catch (_) {}
      }
    }

    attSlotsHtml(names) {
      const list = (names || []).filter(Boolean);
      if (!list.length) return '';
      return `<div class="inline-thumbs" data-att-names="${esc(JSON.stringify(list))}"></div>`;
    }

    async hydrateAttachmentSlots(container) {
      const slots = container.querySelectorAll('.inline-thumbs[data-att-names]');
      for (const slot of slots) {
        let names = [];
        try {
          names = JSON.parse(slot.dataset.attNames || '[]');
        } catch (_) {}
        const parts = [];
        for (const name of names) {
          let url = this.getThumbUrl(name);
          if (!url) {
            try {
              url = await this.api.fetchAttachmentBlob(name);
              this.imageCache.set(name, url);
              this.blobUrls.push(url);
            } catch (_) {
              parts.push(`<span class="thumb-miss" title="${esc(name)}">图</span>`);
              continue;
            }
          }
          parts.push(`<img src="${url}" class="inline-thumb" alt="" data-src="${url}">`);
        }
        slot.innerHTML = parts.join('');
      }
      this.bindThumbClicks(container);
    }

    bindThumbClicks(root) {
      root.querySelectorAll('.inline-thumb').forEach((img) => {
        img.addEventListener('click', (e) => {
          e.stopPropagation();
          this.showLightbox(img.dataset.src || img.src);
        });
      });
    }

    trackBlob(url) {
      this.blobUrls.push(url);
      return url;
    }

    render() {
      const v = this.view;
      if (v === 'detail') {
        this.renderDetailAsync();
        return;
      }
      this.revokeBlobs();
      if (v === 'loading') { this.root.innerHTML = '<div class="center-msg">加载中…</div>'; return; }
      if (v === 'error') {
        const msg = esc(this._bootError || '加载失败');
        this.root.innerHTML = `<div class="center-msg">${msg}<br><a href="/admin/dashboard">返回管理后台</a></div>`;
        return;
      }
      if (v === 'login') { this.renderLogin(); return; }
      if (v === 'home') { this.renderHome(); return; }
    }

    async renderLogin() {
      if (this._registrationEnabled === undefined) {
        const cfg = await this.api.fetchAuthConfig();
        this._registrationEnabled = !!cfg.registration_enabled;
      }
      if (!this._registrationEnabled) this._registerMode = false;
      const saved = this.api.readLoginCredentials();
      const registerMode = !!this._registerMode && this._registrationEnabled;
      const errText = this._loginError || '';
      this._loginError = '';
      this.root.innerHTML = `
        <div class="auth-card">
          <h1>🚛 卡车记账</h1>
          <p class="muted">Web 云端账本 · 与手机 App 数据同步</p>
          <form id="login-form">
            <label>用户名<input name="username" required autocomplete="username" value="${esc(saved.username)}"></label>
            <label>密码<input name="password" type="password" required autocomplete="current-password" value="${esc(saved.password)}"></label>
            ${registerMode ? '<label>车牌号<input name="license_plate" required placeholder="如 京A12345" autocomplete="off"></label>' : ''}
            <div class="form-actions">
              <button type="submit" class="btn primary">${registerMode ? '注册并登录' : '登录'}</button>
              ${this._registrationEnabled
                ? `<button type="button" class="btn" id="btn-toggle-mode">${registerMode ? '已有账号？去登录' : '注册'}</button>`
                : ''}
            </div>
            ${!this._registrationEnabled ? '<p class="muted">当前未开放注册，请使用已有账号登录</p>' : ''}
            <p id="login-error" class="error">${esc(errText)}</p>
          </form>
        </div>`;
      const form = document.getElementById('login-form');
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const fd = new FormData(form);
        const errEl = document.getElementById('login-error');
        try {
          if (registerMode) {
            const plate = normalizeLicensePlate(fd.get('license_plate'));
            if (!plate) {
              errEl.textContent = '请填写有效车牌号（5–10 位，含省份汉字，如 京A12345）';
              return;
            }
            await this.api.register(fd.get('username'), fd.get('password'), plate);
          } else {
            await this.api.login(fd.get('username'), fd.get('password'));
          }
          await this.loadLedger();
          this.view = 'home';
          this.render();
        } catch (err) {
          errEl.textContent = err.message;
          if (String(err.message || '').includes('注册')) {
            this._registrationEnabled = false;
            this._registerMode = false;
            this.renderLogin();
          }
        }
      });
      const toggle = document.getElementById('btn-toggle-mode');
      if (toggle) {
        toggle.addEventListener('click', () => {
          this._registerMode = !registerMode;
          this.renderLogin();
        });
      }
    }

    wageSummary() {
      const rounds = this.book.rounds;
      if (!rounds.length) return '工资汇总：暂无圈次';
      let due = 0, paid = 0, unpaid = 0;
      rounds.forEach((r) => {
        const s = calculateProfit(r);
        due += s.driverWagePayable;
        if (r.isSalarySettled) paid += s.driverWagePayable;
        if (r.isReconciled && !r.isSalarySettled) unpaid += s.driverWagePayable;
      });
      return `工资汇总：应得 ${money(due)} ｜ 已发 ${money(paid)} ｜ 未发 ${money(unpaid)}（仅已交账）`;
    }

    renderHome() {
      const title = isAdmin
        ? `管理 · ${esc(cfg.username || '用户')} 的账本（${this.book.rounds.length} 圈 · rev ${this.revision}）`
        : `圈次总览`;
      const rounds = this.book.rounds;
      const rows = rounds.length
        ? rounds.map((r) => {
            const p = calculateProfit(r);
            const reconcileLabel = r.isReconciled ? '已交账' : '未交账';
            const salaryLabel = r.isSalarySettled ? '已工资结算' : '未工资结算';
            return `<div class="round-card-wrap">
              <button type="button" class="round-card" data-id="${esc(r.id)}">
                <div class="round-title-row">
                  <span class="round-title">${esc(r.title || '未命名')}</span>
                  <span class="chevron">›</span>
                </div>
                <div class="route-preview muted">${esc(routePreview(r))}</div>
                <div class="pill-row">
                  <div class="pill"><span class="pill-label">司机应发</span><span class="pill-value">${money(p.driverWagePayable)}</span></div>
                  <div class="pill"><span class="pill-label">老板分成</span><span class="pill-value">${money(p.ownerShare)}</span></div>
                </div>
                <div class="chip-row">
                  <span class="chip ${r.isReconciled ? 'ok' : ''}">${reconcileLabel}</span>
                  <span class="chip ${r.isSalarySettled ? 'ok' : ''}">${salaryLabel}</span>
                </div>
              </button>
              <button type="button" class="round-del" data-del="${esc(r.id)}" title="删除">×</button>
            </div>`;
          }).join('')
        : '<p class="empty">暂无圈次，点击右上角 ＋ 新建</p>';

      const statusLine = this.syncStatus || (this.updatedAt ? `云端更新：${fmtDate(new Date(this.updatedAt))}` : '');

      this.root.innerHTML = `
        <header class="topbar">
          <div>
            <div class="topbar-title">${title}</div>
            <div class="topbar-sub muted">${this.wageSummary()}</div>
          </div>
          <div class="topbar-actions">
            ${isAdmin ? '<a class="btn" href="/admin/dashboard">返回</a>' : ''}
            <button type="button" class="btn" id="btn-more" title="更多">⋯</button>
            <button type="button" class="btn" id="btn-sort" title="排序">${this.sortAsc ? '↑' : '↓'}</button>
            <button type="button" class="btn primary" id="btn-add">＋</button>
          </div>
        </header>
        <main class="content">
          <div class="summary-card">${esc(this.wageSummary())}</div>
          ${statusLine ? `<p class="sync-hint muted">${esc(statusLine)}</p>` : ''}
          <p class="muted list-hint">每圈简写信息（点开查看详情）</p>
          <div class="round-list">${rows}</div>
        </main>`;

      this.root.querySelectorAll('.round-card').forEach((el) => {
        el.addEventListener('click', () => {
          this.selectedId = el.dataset.id;
          this.view = 'detail';
          this.render();
        });
      });
      this.root.querySelectorAll('.round-del').forEach((el) => {
        el.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          const id = el.dataset.del;
          const trip = this.book.rounds.find((r) => r.id === id);
          if (!confirm(`确定删除「${trip?.title || '圈次'}」？删除后不可恢复。`)) return;
          this.book.rounds = this.book.rounds.filter((r) => r.id !== id);
          await this.commit();
        });
      });
      document.getElementById('btn-add').addEventListener('click', () => this.promptNewRound());
      document.getElementById('btn-sort').addEventListener('click', () => {
        this.sortAsc = !this.sortAsc;
        this.sortRounds();
        this.render();
      });
      document.getElementById('btn-more').addEventListener('click', () => this.showHomeMenu());
    }

    showHomeMenu() {
      const sheet = document.createElement('div');
      sheet.className = 'sheet-overlay';
      const items = isAdmin
        ? '<button type="button" data-a="refresh">从云端刷新</button>'
        : `<button type="button" data-a="refresh">从云端刷新</button>
           <button type="button" data-a="export">导出备份…</button>
           <button type="button" data-a="import">导入账本…</button>
           <button type="button" data-a="logout">退出登录</button>`;
      sheet.innerHTML = `<div class="sheet">${items}<button type="button" class="cancel" data-a="cancel">取消</button></div>`;
      document.body.appendChild(sheet);
      const close = () => sheet.remove();
      sheet.addEventListener('click', (ev) => { if (ev.target === sheet) close(); });
      sheet.querySelectorAll('[data-a]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const a = btn.dataset.a;
          close();
          if (a === 'cancel') return;
          if (a === 'refresh') { await this.loadLedger(); this.render(); this.toast('已从云端刷新'); return; }
          if (a === 'logout') { this.api.clearAuth(); this.view = 'login'; this.render(); return; }
          if (a === 'export') await this.exportBackup();
          if (a === 'import') await this.importBackup();
        });
      });
    }

    async exportBackup() {
      if (!this.book.rounds.length) { this.toast('暂无圈次，无需导出'); return; }
      try {
        const fetchBlob = async (name) => {
          if (this.pendingUploads.has(name)) return this.pendingUploads.get(name);
          const res = await fetch(this.api.attachmentPath(name), { headers: this.api.authHeaders() });
          if (!res.ok) throw new Error('missing');
          return res.blob();
        };
        const r = await LedgerBackup.exportZip(this.book, fetchBlob);
        this.toast(`已导出 ${r.roundCount} 圈次、${r.attachmentCount} 张图`);
      } catch (e) {
        this.toast('导出失败：' + (e.message || e));
      }
    }

    async importBackup() {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.json,.zip,application/json,application/zip';
      input.addEventListener('change', async () => {
        const file = input.files?.[0];
        if (!file) return;
        try {
          const { book: incoming, attachmentFiles } = await LedgerBackup.parseImportFile(file);
          const n = (incoming.rounds || []).length;
          const attCount = Object.keys(attachmentFiles).length;
          const mode = await this.importDialog(n, attCount);
          if (!mode) return;
          for (const [name, blob] of Object.entries(attachmentFiles)) {
            this.pendingUploads.set(name, blob);
          }
          if (mode === 'merge') {
            this.book = LedgerBackup.mergeBook(this.book, incoming, uuid);
          } else {
            this.book = LedgerBackup.replaceBook(incoming);
          }
          this.sortRounds();
          await this.commit();
          this.toast(`导入完成：${n} 个圈次${attCount ? `，${attCount} 张附件` : ''}`);
        } catch (e) {
          this.toast('导入失败：' + (e.message || e));
        }
      });
      input.click();
    }

    importDialog(n, attCount) {
      return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `<div class="modal">
          <h3>导入账本</h3>
          <p>已解析 ${n} 个圈次${attCount ? `，含 ${attCount} 张附件` : ''}。</p>
          <p class="hint">「合并」：追加到当前列表；id 冲突时自动换新 id。<br>「覆盖」：清空云端全部圈次并替换（不可恢复）。</p>
          <div class="modal-actions">
            <button type="button" class="btn" data-m="cancel">取消</button>
            <button type="button" class="btn" data-m="merge">合并</button>
            <button type="button" class="btn danger" data-m="replace">覆盖</button>
          </div>
        </div>`;
        document.body.appendChild(overlay);
        overlay.querySelector('[data-m="cancel"]').addEventListener('click', () => { overlay.remove(); resolve(null); });
        overlay.querySelector('[data-m="merge"]').addEventListener('click', () => { overlay.remove(); resolve('merge'); });
        overlay.querySelector('[data-m="replace"]').addEventListener('click', () => {
          if (!confirm('确定覆盖？将删除云端全部圈次数据。')) return;
          overlay.remove();
          resolve('replace');
        });
      });
    }

    promptNewRound() {
      this.modal(`
        <h3>新建圈次</h3>
        <label>开始时间<input id="m-start" type="datetime-local" value="${toDatetimeLocalValue('')}"></label>
        <label>结束时间<input id="m-end" type="datetime-local" value="${toDatetimeLocalValue('')}"></label>
      `, async () => {
        const start = fromDatetimeLocalValue(document.getElementById('m-start').value);
        const end = fromDatetimeLocalValue(document.getElementById('m-end').value);
        const trip = {
          id: uuid(),
          title: makeTripTitle(start, end),
          startPlace: start,
          endPlace: end,
          createdAt: encodeSwiftDate(new Date()),
          isReconciled: false,
          isSalarySettled: false,
          routeLegs: [],
          expenses: [],
          cashAdvances: [],
        };
        this.book.rounds.unshift(trip);
        this.selectedId = trip.id;
        this.view = 'detail';
        await this.commit();
        return true;
      });
    }

    editTripMeta(trip) {
      this.modal(`
        <h3>圈次信息</h3>
        <label>开始时间<input id="m-start" type="datetime-local" value="${toDatetimeLocalValue(trip.startPlace)}"></label>
        <label>结束时间<input id="m-end" type="datetime-local" value="${toDatetimeLocalValue(trip.endPlace)}"></label>
      `, async () => {
        trip.startPlace = fromDatetimeLocalValue(document.getElementById('m-start').value);
        trip.endPlace = fromDatetimeLocalValue(document.getElementById('m-end').value);
        trip.title = makeTripTitle(trip.startPlace, trip.endPlace);
        await this.commit();
        return true;
      });
    }

    splitMixedTollIfNeeded(trip, globalIdx) {
      const e = trip.expenses[globalIdx];
      if (!e || e.category !== '高速费') return;
      const c = e.tollCashAmount || 0;
      const t = e.tollEtcAmount || 0;
      if (c <= 0.000001 || t <= 0.000001) return;
      const base = (e.title || '').trim();
      const att = [...(e.attachments || [])];
      const created = e.createdAt;
      const eCash = {
        id: uuid(), category: '高速费',
        title: base ? `${base}（现金）` : '高速费（现金）',
        amount: c, paymentSource: '现金', isReimbursable: false,
        attachments: att, createdAt: created, tollCashAmount: c, tollEtcAmount: 0,
      };
      const eEtc = {
        id: uuid(), category: '高速费',
        title: base ? `${base}（ETC）` : '高速费（ETC）',
        amount: t, paymentSource: 'ETC', isReimbursable: false,
        attachments: att, createdAt: created, tollCashAmount: 0, tollEtcAmount: t,
      };
      trip.expenses.splice(globalIdx, 1, eEtc, eCash);
    }

    showAddSheet(trip) {
      const sheet = document.createElement('div');
      sheet.className = 'sheet-overlay';
      sheet.innerHTML = `<div class="sheet">
        <button type="button" data-a="route">路线（含运费/信息费）</button>
        <button type="button" data-a="fuel">油费</button>
        <button type="button" data-a="toll">高速费</button>
        <button type="button" data-a="other">其他费用</button>
        <button type="button" data-a="advance">现金支取</button>
        <button type="button" class="cancel" data-a="cancel">取消</button>
      </div>`;
      document.body.appendChild(sheet);
      const close = () => sheet.remove();
      sheet.addEventListener('click', (ev) => {
        if (ev.target === sheet) close();
      });
      sheet.querySelectorAll('[data-a]').forEach((btn) => {
        btn.addEventListener('click', () => {
          const a = btn.dataset.a;
          close();
          if (a === 'cancel') return;
          if (a === 'route') this.editLeg(trip);
          if (a === 'fuel') this.editExpense(trip, null, '油费');
          if (a === 'toll') this.editExpense(trip, null, '高速费');
          if (a === 'other') this.editExpense(trip, null, '其他费用');
          if (a === 'advance') this.editAdvance(trip);
        });
      });
    }

    async renderDetailAsync() {
      const trip = this.selectedTrip();
      if (!trip) { this.view = 'home'; this.render(); return; }

      this.root.innerHTML = '<div class="center-msg">加载中…</div>';
      await this.preloadAttachments(trip);
      const sum = calculateProfit(trip);

      const legList = (trip.routeLegs || []).map((leg, i) => {
        const freightPart = leg.freightExpression
          ? `运费 ${money(leg.freight)}（${leg.freightExpression}）`
          : `运费 ${money(leg.freight)}`;
        const sub = `${freightPart}  信息费 ${money(leg.infoFee)} · ${leg.infoFeePaymentSource}${leg.note ? '  备注：' + leg.note : ''}`;
        return `<div class="list-tile" data-edit-leg="${i}">
          <div class="tile-main">
            <div class="tile-title">${i + 1}. ${esc(leg.loadPlace)} → ${esc(leg.unloadPlace)}</div>
            <div class="tile-sub">${esc(sub)}</div>
          </div>
          ${this.attSlotsHtml(leg.attachments)}
          <button type="button" class="icon-del" data-del-leg="${i}" title="删除">🗑</button>
        </div>`;
      }).join('') || '<p class="empty-sm">暂无路线，点右上角 ＋ 新增</p>';

      const expenseList = (cat) => {
        const indices = expenseIndices(trip, cat);
        if (!indices.length) return `<p class="empty-sm">暂无${cat}</p>`;
        return indices.map((gi) => {
          const item = trip.expenses[gi];
          const sub = cat === '高速费'
            ? tollSubtitle(item)
            : cat === '油费'
              ? fuelSubtitle(item)
              : `${money(item.amount)} · ${item.paymentSource}${item.isReimbursable ? ' · 可报销' : ''}`;
          return `<div class="list-tile" data-edit-exp="${gi}" data-cat="${cat}">
            <div class="tile-main">
              <div class="tile-title">${esc(item.title)}</div>
              <div class="tile-sub">${esc(sub)}</div>
            </div>
            ${this.attSlotsHtml(item.attachments)}
            <button type="button" class="icon-del" data-del-exp="${gi}" title="删除">🗑</button>
          </div>`;
        }).join('');
      };

      const advances = (trip.cashAdvances || []).map((a, i) => `<div class="list-tile" data-edit-adv="${i}">
        <div class="tile-main">
          <div class="tile-title">${esc(a.title)}</div>
          <div class="tile-sub">${money(a.amount)}</div>
        </div>
        ${this.attSlotsHtml(a.attachments)}
        <button type="button" class="icon-del" data-del-adv="${i}" title="删除">🗑</button>
      </div>`).join('') || '<p class="empty-sm">暂无现金支取</p>';

      this.root.innerHTML = `
        <header class="topbar">
          <button type="button" class="btn" id="btn-back">← 返回</button>
          <div class="topbar-title">${esc(trip.title)}</div>
          <div class="topbar-actions">
            <button type="button" class="btn" id="btn-add-item" title="新增">＋</button>
            <button type="button" class="btn" id="btn-meta" title="编辑圈次">圈次</button>
          </div>
        </header>
        <main class="content detail">
          <p class="section-label">本圈结算</p>
          <section class="card"><pre class="summary-pre">${esc(summaryBody(sum))}</pre></section>
          <p class="section-label">交账与工资状态</p>
          <section class="card">
            <label class="switch-row"><div><div>是否已交账</div><div class="muted">${trip.isReconciled ? '已交账' : '未交账'}</div></div><input type="checkbox" id="f-recon" ${trip.isReconciled ? 'checked' : ''}></label>
            <label class="switch-row"><div><div>是否已工资结算</div><div class="muted">${trip.isSalarySettled ? '已结算' : '未结算'}</div></div><input type="checkbox" id="f-salary" ${trip.isSalarySettled ? 'checked' : ''}></label>
          </section>
          <p class="section-label">路线明细（含运费、信息费）</p>
          <section class="card list-card">${legList}</section>
          <p class="section-label">油费</p>
          <section class="card list-card">${expenseList('油费')}</section>
          <p class="section-label">高速费</p>
          <section class="card list-card">${expenseList('高速费')}</section>
          <p class="section-label">其他费用</p>
          <section class="card list-card">${expenseList('其他费用')}</section>
          <p class="section-label">现金支取</p>
          <section class="card list-card">${advances}</section>
          <section class="card danger-zone">
            <button type="button" class="btn danger" id="btn-del-trip">删除本圈次</button>
          </section>
        </main>`;

      await this.hydrateAttachmentSlots(this.root);
      document.getElementById('btn-back').addEventListener('click', () => { this.view = 'home'; this.render(); });
      document.getElementById('btn-add-item').addEventListener('click', () => this.showAddSheet(trip));
      document.getElementById('btn-meta').addEventListener('click', () => this.editTripMeta(trip));
      document.getElementById('f-recon').addEventListener('change', async (e) => {
        trip.isReconciled = e.target.checked;
        await this.commit();
      });
      document.getElementById('f-salary').addEventListener('change', async (e) => {
        trip.isSalarySettled = e.target.checked;
        await this.commit();
      });

      this.root.querySelectorAll('[data-edit-leg]').forEach((el) => {
        el.addEventListener('click', (ev) => {
          if (ev.target.closest('.icon-del') || ev.target.closest('.inline-thumbs')) return;
          this.editLeg(trip, Number(el.dataset.editLeg));
        });
      });
      this.root.querySelectorAll('[data-del-leg]').forEach((b) => {
        b.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          trip.routeLegs.splice(Number(b.dataset.delLeg), 1);
          await this.commit();
        });
      });
      this.root.querySelectorAll('[data-edit-exp]').forEach((el) => {
        el.addEventListener('click', (ev) => {
          if (ev.target.closest('.icon-del') || ev.target.closest('.inline-thumbs')) return;
          const gi = Number(el.dataset.editExp);
          if (el.dataset.cat === '高速费') this.splitMixedTollIfNeeded(trip, gi);
          this.editExpense(trip, gi, el.dataset.cat);
        });
      });
      this.root.querySelectorAll('[data-del-exp]').forEach((b) => {
        b.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          trip.expenses.splice(Number(b.dataset.delExp), 1);
          await this.commit();
        });
      });
      this.root.querySelectorAll('[data-edit-adv]').forEach((el) => {
        el.addEventListener('click', (ev) => {
          if (ev.target.closest('.icon-del') || ev.target.closest('.inline-thumbs')) return;
          this.editAdvance(trip, Number(el.dataset.editAdv));
        });
      });
      this.root.querySelectorAll('[data-del-adv]').forEach((b) => {
        b.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          trip.cashAdvances.splice(Number(b.dataset.delAdv), 1);
          await this.commit();
        });
      });
      document.getElementById('btn-del-trip').addEventListener('click', async () => {
        if (!confirm('确定删除本圈次？')) return;
        this.book.rounds = this.book.rounds.filter((r) => r.id !== trip.id);
        this.view = 'home';
        await this.commit();
      });
    }

    async attachmentThumbHtml(name) {
      if (!this.getThumbUrl(name) && !this.pendingUploads.has(name)) {
        try {
          const url = await this.api.fetchAttachmentBlob(name);
          this.imageCache.set(name, url);
          this.blobUrls.push(url);
        } catch (_) {
          return '<span class="muted">无法预览</span>';
        }
      }
      const url = this.getThumbUrl(name);
      return url ? `<img src="${url}" alt="" class="att-thumb">` : '<span class="muted">无法预览</span>';
    }

    async mountAttachmentEditor(container, attachments) {
      const list = attachments || [];
      const renderList = async () => {
        container.innerHTML = '<div class="att-editor-list"></div><button type="button" class="btn sm att-add">从相册添加</button>';
        const wrap = container.querySelector('.att-editor-list');
        for (let i = 0; i < list.length; i++) {
          const row = document.createElement('div');
          row.className = 'att-editor-row';
          row.innerHTML = `<span>图片 ${i + 1}</span><div class="att-preview-slot"></div><button type="button" class="link danger att-rm" data-i="${i}">删除</button>`;
          const slot = row.querySelector('.att-preview-slot');
          slot.innerHTML = await this.attachmentThumbHtml(list[i]);
          const img = slot.querySelector('img');
          if (img) img.addEventListener('click', () => this.showLightbox(img.src));
          wrap.appendChild(row);
        }
        wrap.querySelectorAll('.att-rm').forEach((btn) => {
          btn.addEventListener('click', () => {
            const idx = Number(btn.dataset.i);
            const removed = list.splice(idx, 1)[0];
            if (removed) this.pendingUploads.delete(removed);
            renderList();
          });
        });
        container.querySelector('.att-add').addEventListener('click', () => this.pickAttachments(list, renderList));
      };
      await renderList();
    }

    pickAttachments(list, callback) {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.multiple = true;
      input.addEventListener('change', async () => {
        try {
          for (const file of input.files || []) {
            const blob = await fileToJpegBlob(file);
            const name = `${uuid()}.jpg`;
            this.pendingUploads.set(name, blob);
            list.push(name);
          }
          this.markDirty();
          await callback();
        } catch (e) {
          this.toast(e.message || '添加图片失败');
        }
      });
      input.click();
    }

    showLightbox(src) {
      const overlay = document.createElement('div');
      overlay.className = 'lightbox';
      overlay.innerHTML = `<img src="${src}" alt=""><button type="button" class="lightbox-close">×</button>`;
      overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target.classList.contains('lightbox-close')) overlay.remove(); });
      document.body.appendChild(overlay);
    }

    modal(html, onOk, opts = {}) {
      const overlay = document.createElement('div');
      overlay.className = 'modal-overlay';
      overlay.innerHTML = `<div class="modal modal-wide">${html}<div class="modal-actions">
        <button type="button" class="btn" data-cancel>取消</button>
        <button type="button" class="btn primary" data-ok>保存</button>
      </div></div>`;
      document.body.appendChild(overlay);
      const errEl = overlay.querySelector('#modal-err');
      const showErr = (msg) => {
        if (errEl) errEl.textContent = msg;
        else this.toast(msg);
      };
      if (opts.onMount) opts.onMount(overlay);
      overlay.querySelector('[data-cancel]').addEventListener('click', () => overlay.remove());
      overlay.querySelector('[data-ok]').addEventListener('click', async () => {
        try {
          const ok = await onOk(overlay, showErr);
          if (ok !== false) overlay.remove();
        } catch (e) {
          showErr(e.message || '保存失败');
        }
      });
    }

    editLeg(trip, index) {
      const leg = index == null
        ? { id: uuid(), loadPlace: '', unloadPlace: '', freight: 0, freightExpression: '', infoFee: 0, infoFeePaymentSource: '现金', note: '', attachments: [], createdAt: encodeSwiftDate(new Date()) }
        : JSON.parse(JSON.stringify(trip.routeLegs[index]));
      const att = leg.attachments || (leg.attachments = []);
      const infoPay = leg.infoFeePaymentSource === '公司账户' ? '公司账户' : '现金';
      const freightInput = (leg.freightExpression && String(leg.freightExpression).trim())
        ? leg.freightExpression
        : (leg.freight ? String(leg.freight) : '');
      this.modal(`
        <h3>${index == null ? '添加' : '编辑'}路线</h3>
        <p id="modal-err" class="error"></p>
        <label>装货地<input id="m-load" value="${esc(leg.loadPlace)}"></label>
        <label>卸货地<input id="m-unload" value="${esc(leg.unloadPlace)}"></label>
        <label>运费（支持运算式，如 32*280、8000*3%）
          <input id="m-freight" inputmode="decimal" value="${esc(freightInput)}" placeholder="数字或表达式">
          <div id="m-freight-hint" class="muted" style="margin-top:4px"></div>
        </label>
        <label>信息费（可不填，默认 0）<input id="m-info" type="number" step="0.01" inputmode="decimal" value="${leg.infoFee}"></label>
        <label>备注<input id="m-note" value="${esc(leg.note)}"></label>
        <label>信息费支付方式
          <div class="seg-group">${INFO_PAY.map((s) => `<label class="seg"><input type="radio" name="infosrc" value="${s}" ${infoPay === s ? 'checked' : ''}> ${s}</label>`).join('')}</div>
        </label>
        <div class="att-section"><div class="att-label">凭证图片</div><div id="att-box"></div></div>
      `, async (overlay, showErr) => {
        const load = document.getElementById('m-load').value.trim();
        const unload = document.getElementById('m-unload').value.trim();
        if (!load || !unload) { showErr('装货地/卸货地不能为空'); return false; }
        const rawFreight = document.getElementById('m-freight').value.trim();
        const freight = parseAmountOrExpression(rawFreight);
        if (freight == null) { showErr('运费请输入数字或运算式（如 32*280、8000*3%）'); return false; }
        const src = overlay.querySelector('input[name="infosrc"]:checked');
        leg.loadPlace = load;
        leg.unloadPlace = unload;
        leg.freight = freight;
        leg.freightExpression = parseAmount(rawFreight) == null ? rawFreight : '';
        leg.infoFee = parseAmount(document.getElementById('m-info').value) ?? 0;
        leg.infoFeePaymentSource = src?.value || '现金';
        leg.note = document.getElementById('m-note').value.trim();
        if (!trip.routeLegs) trip.routeLegs = [];
        if (index == null) trip.routeLegs.push(leg);
        else trip.routeLegs[index] = leg;
        await this.commit();
        return true;
      }, {
        onMount: (overlay) => {
          this.mountAttachmentEditor(overlay.querySelector('#att-box'), att);
          const freightEl = overlay.querySelector('#m-freight');
          const hint = overlay.querySelector('#m-freight-hint');
          const updateHint = () => {
            const raw = freightEl.value.trim();
            const v = parseAmountOrExpression(raw);
            if (raw && parseAmount(raw) == null && v != null) {
              hint.textContent = `计算结果：${v.toFixed(2)}`;
            } else {
              hint.textContent = '支持 + - * / ( ) 与 %';
            }
          };
          freightEl.addEventListener('input', updateHint);
          updateHint();
        },
      });
    }

    editExpense(trip, globalIndex, defaultCat) {
      const isNew = globalIndex == null;
      let e;
      if (isNew) {
        const cat = defaultCat || '油费';
        e = {
          id: uuid(), category: cat,
          title: '',
          amount: 0,
          paymentSource: cat === '高速费' ? 'ETC' : '现金',
          isReimbursable: false,
          attachments: [],
          createdAt: encodeSwiftDate(new Date()),
          tollCashAmount: 0, tollEtcAmount: 0,
          fuelKilograms: 0, fuelUnitPrice: 0,
        };
      } else {
        e = JSON.parse(JSON.stringify(trip.expenses[globalIndex]));
      }
      const att = e.attachments || (e.attachments = []);
      const cat = e.category;

      const buildPay = () => {
        if (cat === '高速费') {
          const pay = e.paymentSource === 'ETC' ? 'ETC' : '现金';
          return `<div class="seg-group" id="m-toll-seg">
            ${TOLL_PAY.map((s) => `<label class="seg"><input type="radio" name="tollpay" value="${s}" ${pay === s ? 'checked' : ''}> ${s}</label>`).join('')}
          </div>
          <p class="hint">若同一笔同时含现金与 ETC，请新增两条高速费分别记录。ETC 将按 0.35% 加计对账手续费。</p>`;
        }
        const pay = e.paymentSource === '公司账户' ? '公司账户' : '现金';
        return `<div class="seg-group">${FUEL_OTHER_PAY.map((s) => `<label class="seg"><input type="radio" name="fuelpay" value="${s}" ${pay === s ? 'checked' : ''}> ${s}</label>`).join('')}</div>`;
      };

      const reimbBlock = cat === '其他费用'
        ? `<label class="check"><input type="checkbox" id="m-reimb" ${e.isReimbursable ? 'checked' : ''}> 老板报销承担（仅现金）</label>`
        : '';

      const titleValue = isNew ? '' : esc(e.title || '');
      const amountValue = (!isNew && e.amount) ? e.amount : '';
      const kgValue = (!isNew && e.fuelKilograms) ? e.fuelKilograms : '';
      const priceValue = (!isNew && e.fuelUnitPrice) ? e.fuelUnitPrice : '';

      const fuelFields = cat === '油费'
        ? `<label>公斤数<input id="m-fuel-kg" type="text" inputmode="decimal" placeholder="支持小数，如 12.5" value="${kgValue}"></label>
           <label>单价（元/kg）<input id="m-fuel-price" type="text" inputmode="decimal" placeholder="可自动算出" value="${priceValue}"></label>
           <p class="hint">手动填过的数字不会被覆盖；清空后可再自动生成。金额 = 公斤数 × 单价。</p>`
        : '';

      this.modal(`
        <h3>${isNew ? '添加' : '编辑'}${cat}</h3>
        <p id="modal-err" class="error"></p>
        <label>标题<input id="m-title" placeholder="${esc(cat)}" value="${titleValue}"></label>
        <label>金额<input id="m-amount" type="text" inputmode="decimal" placeholder="${cat === '油费' ? '可自动算出' : ''}" value="${amountValue}"></label>
        ${fuelFields}
        <label>${cat}支付方式<div id="m-pay-wrap">${buildPay()}</div></label>
        ${reimbBlock}
        <div class="att-section"><div class="att-label">凭证图片</div><div id="att-box"></div></div>
      `, async (overlay, showErr) => {
        let title = document.getElementById('m-title').value.trim();
        if (!title) title = cat;
        const amount = parseAmount(document.getElementById('m-amount').value);
        if (amount == null) { showErr('金额请输入数字（或填公斤数与单价自动算出）'); return false; }

        let payForItem = e.paymentSource;
        let tollCash = 0, tollEtc = 0;
        let reimb = document.getElementById('m-reimb')?.checked || false;
        let fuelKg = 0, fuelPrice = 0;

        if (cat === '高速费') {
          const sel = overlay.querySelector('input[name="tollpay"]:checked');
          payForItem = sel?.value === 'ETC' ? 'ETC' : '现金';
          tollCash = payForItem === '现金' ? amount : 0;
          tollEtc = payForItem === 'ETC' ? amount : 0;
          reimb = false;
        } else {
          const sel = overlay.querySelector('input[name="fuelpay"]:checked');
          payForItem = sel?.value || '现金';
          if (cat !== '其他费用') reimb = false;
          if (payForItem !== '现金') reimb = false;
        }

        if (cat === '油费') {
          fuelKg = parseAmount(document.getElementById('m-fuel-kg')?.value) || 0;
          fuelPrice = parseAmount(document.getElementById('m-fuel-price')?.value) || 0;
          if (fuelKg < 0 || fuelPrice < 0) { showErr('公斤数与单价不能为负数'); return false; }
        }

        e.title = title;
        e.amount = amount;
        e.paymentSource = payForItem;
        e.isReimbursable = reimb;
        e.tollCashAmount = tollCash;
        e.tollEtcAmount = tollEtc;
        e.fuelKilograms = cat === '油费' ? fuelKg : 0;
        e.fuelUnitPrice = cat === '油费' ? fuelPrice : 0;

        if (!trip.expenses) trip.expenses = [];
        if (isNew) trip.expenses.push(e);
        else trip.expenses[globalIndex] = e;
        await this.commit();
        return true;
      }, {
        onMount: (overlay) => {
          this.mountAttachmentEditor(overlay.querySelector('#att-box'), att);
          const reimb = overlay.querySelector('#m-reimb');
          if (reimb) {
            reimb.addEventListener('change', () => {
              if (reimb.checked) {
                const cash = overlay.querySelector('input[name="fuelpay"][value="现金"]');
                if (cash) cash.checked = true;
              }
            });
            overlay.querySelectorAll('input[name="fuelpay"]').forEach((r) => {
              r.addEventListener('change', () => {
                if (r.value !== '现金') reimb.checked = false;
              });
            });
          }
          if (cat === '油费') {
            const amtEl = overlay.querySelector('#m-amount');
            const kgEl = overlay.querySelector('#m-fuel-kg');
            const priceEl = overlay.querySelector('#m-fuel-price');
            let syncing = false;
            const manual = {
              amount: !!(amtEl && amtEl.value.trim()),
              kg: !!(kgEl && kgEl.value.trim()),
              price: !!(priceEl && priceEl.value.trim()),
            };
            const roundMoney = (v) => Math.round(v * 100) / 100;
            const roundKg = (v) => Math.round(v * 10000) / 10000;
            const setAuto = (el, key, v) => {
              if (!el || manual[key]) return;
              const next = (v == null || Number.isNaN(v)) ? '' : String(v);
              if (el.value !== next) el.value = next;
            };
            const syncFrom = (changed) => {
              if (syncing) return;
              const raw = changed === 'amount' ? amtEl?.value
                : changed === 'kg' ? kgEl?.value : priceEl?.value;
              if (!(raw || '').trim()) manual[changed] = false;
              else manual[changed] = true;

              const a = parseAmount(amtEl?.value);
              const k = parseAmount(kgEl?.value);
              const p = parseAmount(priceEl?.value);
              let autoA = null, autoK = null, autoP = null;

              if (k != null && p != null && a == null && !manual.amount) autoA = roundMoney(k * p);
              else if (a != null && p != null && k == null && !manual.kg && p !== 0) autoK = roundKg(a / p);
              else if (a != null && k != null && p == null && !manual.price && k !== 0) autoP = roundMoney(a / k);
              else if (a != null && k != null && p != null) {
                if (changed === 'amount') {
                  if (!manual.price && k !== 0) autoP = roundMoney(a / k);
                  else if (!manual.kg && p !== 0) autoK = roundKg(a / p);
                } else if (changed === 'kg') {
                  if (!manual.amount) autoA = roundMoney(k * p);
                  else if (!manual.price && k !== 0) autoP = roundMoney(a / k);
                } else if (changed === 'price') {
                  if (!manual.amount) autoA = roundMoney(k * p);
                  else if (!manual.kg && p !== 0) autoK = roundKg(a / p);
                }
              }

              syncing = true;
              if (autoA != null) setAuto(amtEl, 'amount', autoA);
              if (autoK != null) setAuto(kgEl, 'kg', autoK);
              if (autoP != null) setAuto(priceEl, 'price', autoP);
              syncing = false;
            };
            amtEl?.addEventListener('input', () => syncFrom('amount'));
            kgEl?.addEventListener('input', () => syncFrom('kg'));
            priceEl?.addEventListener('input', () => syncFrom('price'));
          }
        },
      });
    }

    editAdvance(trip, index) {
      const isNew = index == null;
      const a = isNew
        ? { id: uuid(), title: '出车费', amount: 0, attachments: [], createdAt: encodeSwiftDate(new Date()) }
        : JSON.parse(JSON.stringify(trip.cashAdvances[index]));
      const att = a.attachments || (a.attachments = []);
      this.modal(`
        <h3>${isNew ? '添加' : '编辑'}现金支取</h3>
        <p id="modal-err" class="error"></p>
        <label>标题<input id="m-adv-title" value="${esc(a.title)}"></label>
        <label>金额<input id="m-adv-amount" type="number" step="0.01" inputmode="decimal" value="${a.amount}"></label>
        <div class="att-section"><div class="att-label">凭证图片</div><div id="att-box"></div></div>
      `, async (overlay, showErr) => {
        const title = document.getElementById('m-adv-title').value.trim();
        if (!title) { showErr('标题不能为空'); return false; }
        const amount = parseAmount(document.getElementById('m-adv-amount').value);
        if (amount == null) { showErr('金额请输入数字'); return false; }
        a.title = title;
        a.amount = amount;
        if (!trip.cashAdvances) trip.cashAdvances = [];
        if (isNew) trip.cashAdvances.push(a);
        else trip.cashAdvances[index] = a;
        await this.commit();
        return true;
      }, {
        onMount: (overlay) => this.mountAttachmentEditor(overlay.querySelector('#att-box'), att),
      });
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    const root = document.getElementById('app');
    if (!root) return;
    new App(root).start();
  });
})();
