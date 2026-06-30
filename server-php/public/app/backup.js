/* 账本 ZIP / JSON 备份（与 App LedgerBackupExporter / Importer 格式一致） */
(function (global) {
  'use strict';

  function collectAttachmentNames(book) {
    const names = new Set();
    (book.rounds || []).forEach((trip) => {
      [...(trip.routeLegs || []), ...(trip.expenses || []), ...(trip.cashAdvances || [])].forEach((item) => {
        (item.attachments || []).forEach((n) => { if (n && n.trim()) names.add(n.trim()); });
      });
    });
    return names;
  }

  function tsName() {
    const d = new Date();
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  }

  async function exportZip(book, fetchBlob) {
    if (!global.JSZip) throw new Error('JSZip 未加载');
    const zip = new JSZip();
    zip.file('ledger_book.json', JSON.stringify({ rounds: book.rounds || [] }, null, 2));
    let attached = 0;
    for (const name of collectAttachmentNames(book)) {
      try {
        const blob = await fetchBlob(name);
        zip.file(`attachments/${name}`, blob);
        attached++;
      } catch (_) {}
    }
    const blob = await zip.generateAsync({ type: 'blob' });
    const filename = `卡车记账备份_${tsName()}.zip`;
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
    URL.revokeObjectURL(a.href);
    return { roundCount: (book.rounds || []).length, attachmentCount: attached, filename };
  }

  async function parseImportFile(file) {
    const name = file.name || '';
    if (name.endsWith('.json') || file.type === 'application/json') {
      const text = await file.text();
      const data = JSON.parse(text);
      const rounds = data.rounds || (data.id ? [data] : []);
      return { book: { rounds }, attachmentFiles: {} };
    }
    if (!global.JSZip) throw new Error('导入 ZIP 需要 JSZip');
    const zip = await JSZip.loadAsync(await file.arrayBuffer());
    let book = { rounds: [] };
    const jsonEntry = zip.file('ledger_book.json');
    if (jsonEntry) {
      book = JSON.parse(await jsonEntry.async('string'));
      if (!book.rounds) book = { rounds: [] };
    }
    const attachmentFiles = {};
    const files = Object.keys(zip.files);
    for (const path of files) {
      if (path.startsWith('attachments/') && !zip.files[path].dir) {
        const base = path.slice('attachments/'.length);
        if (/^[A-Za-z0-9._-]+\.jpg$/.test(base)) {
          attachmentFiles[base] = await zip.files[path].async('blob');
        }
      }
    }
    return { book, attachmentFiles };
  }

  function cloneTripFreshIds(trip, newId, uuidFn) {
    const uid = uuidFn;
    return {
      id: newId,
      title: trip.title,
      startPlace: trip.startPlace,
      endPlace: trip.endPlace,
      createdAt: trip.createdAt,
      isReconciled: !!trip.isReconciled,
      isSalarySettled: !!trip.isSalarySettled,
      routeLegs: (trip.routeLegs || []).map((l) => ({
        ...l, id: uid(), attachments: [...(l.attachments || [])],
      })),
      expenses: (trip.expenses || []).map((e) => ({
        ...e, id: uid(), attachments: [...(e.attachments || [])],
      })),
      cashAdvances: (trip.cashAdvances || []).map((a) => ({
        ...a, id: uid(), attachments: [...(a.attachments || [])],
      })),
    };
  }

  function mergeBook(current, incoming, uuidFn) {
    const existing = new Set((current.rounds || []).map((r) => r.id));
    const rounds = [...(current.rounds || [])];
    (incoming.rounds || []).forEach((trip) => {
      if (existing.has(trip.id)) {
        const cloned = cloneTripFreshIds(trip, uuidFn(), uuidFn);
        rounds.push(cloned);
        existing.add(cloned.id);
      } else {
        rounds.push(JSON.parse(JSON.stringify(trip)));
        existing.add(trip.id);
      }
    });
    return { rounds };
  }

  function replaceBook(incoming) {
    return { rounds: JSON.parse(JSON.stringify(incoming.rounds || [])) };
  }

  global.LedgerBackup = {
    collectAttachmentNames,
    exportZip,
    parseImportFile,
    mergeBook,
    replaceBook,
  };
})(window);
