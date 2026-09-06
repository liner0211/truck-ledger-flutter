<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>账本 — <?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?></title>
  <link rel="stylesheet" href="/app/app.css">
  <style>
    .admin-ledger-bar {
      max-width: 960px; margin: 0 auto; padding: 10px 12px;
      font-family: system-ui, sans-serif; font-size: .9rem;
      display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center;
      border-bottom: 1px solid #e8e8e8; background: #fafafa;
    }
    .admin-ledger-bar a { color: #1b5e20; text-decoration: none; }
    .admin-ledger-bar .muted { color: #888; }
    .admin-ledger-bar .flash {
      flex: 1 1 100%; background: #e8f5e9; color: #2e7d32;
      padding: 8px 10px; border-radius: 8px;
    }
  </style>
</head>
<body>
  <div class="admin-ledger-bar">
    <a href="/admin/dashboard">← 管理后台</a>
    <span>
      用户 <strong><?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?></strong>
      <span class="muted">#<?= (int)$userId ?></span>
    </span>
    <span class="muted">
      <?= htmlspecialchars((string)($user['status'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
      · <?= htmlspecialchars((string)($user['plan'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
      · rev <?= (int)($ledger['revision'] ?? 0) ?>
      · <?= count($ledger['rounds'] ?? []) ?> 个圈次
    </span>
    <?php if (!empty($canOps)): ?>
    <a href="/admin/users/<?= (int)$userId ?>/ops">快照与设备</a>
    <?php endif; ?>
    <?php if (!empty($message)): ?>
      <div class="flash"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
    <?php endif; ?>
  </div>

  <div id="app"></div>
  <script>
    window.LEDGER_APP_CONFIG = {
      mode: 'admin',
      userId: <?= (int)$userId ?>,
      username: <?= json_encode($user['username'] ?? '', JSON_UNESCAPED_UNICODE) ?>,
      initialLedger: <?= json_encode($ledger, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS) ?>
    };
  </script>
  <script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
  <script src="/app/profit.js"></script>
  <script src="/app/backup.js"></script>
  <script src="/app/ledger-app.js"></script>
</body>
</html>
