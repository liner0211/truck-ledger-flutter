<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>账本 — <?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?></title>
  <link rel="stylesheet" href="/app/app.css">
  <style>
    .admin-tools { max-width: 960px; margin: 16px auto; padding: 0 12px; font-family: system-ui, sans-serif; }
    .admin-tools .panel { background: #fff; border: 1px solid #e0e0e0; border-radius: 12px; margin-bottom: 14px; overflow: hidden; }
    .admin-tools h2 { margin: 0; padding: 12px 14px; font-size: .95rem; border-bottom: 1px solid #eee; }
    .admin-tools table { width: 100%; border-collapse: collapse; font-size: .85rem; }
    .admin-tools th, .admin-tools td { padding: 8px 12px; border-bottom: 1px solid #f0f0f0; text-align: left; }
    .admin-tools .flash { background: #e8f5e9; color: #2e7d32; padding: 10px 12px; border-radius: 8px; margin-bottom: 12px; }
    .admin-tools .btn { padding: 6px 10px; border: 0; border-radius: 8px; background: #fff3e0; color: #e65100; cursor: pointer; }
    .admin-tools a.back { color: #1b5e20; }
    .muted { color: #888; font-size: .8rem; }
  </style>
</head>
<body>
  <div class="admin-tools">
    <p><a class="back" href="/admin/dashboard">← 返回管理后台</a></p>
    <?php if (!empty($message)): ?>
      <div class="flash"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
    <?php endif; ?>
    <p>
      用户 <strong><?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?></strong>
      · 状态 <?= htmlspecialchars((string)($user['status'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
      · 套餐 <?= htmlspecialchars((string)($user['plan'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
    </p>

    <div class="panel">
      <h2>账本快照（自动保留最近约 10 份）</h2>
      <?php if (empty($snapshots)): ?>
        <p class="muted" style="padding:12px;">暂无快照（用户保存账本后会产生）</p>
      <?php else: ?>
      <table>
        <thead><tr><th>ID</th><th>revision</th><th>时间</th><th>备注</th><th>操作</th></tr></thead>
        <tbody>
        <?php foreach ($snapshots as $s): ?>
          <tr>
            <td><?= (int)$s['id'] ?></td>
            <td><?= (int)$s['revision'] ?></td>
            <td class="muted"><?= htmlspecialchars(date('Y-m-d H:i', (int)($s['created_at'] / 1000)), ENT_QUOTES, 'UTF-8') ?></td>
            <td><?= htmlspecialchars((string)$s['note'], ENT_QUOTES, 'UTF-8') ?></td>
            <td>
              <form method="post" action="/admin/users/<?= (int)$user['id'] ?>/snapshots/<?= (int)$s['id'] ?>/restore"
                    onsubmit="return confirm('确定恢复到该快照？当前账本会再自动存一份快照。');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn">恢复</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
      <?php endif; ?>
    </div>

    <div class="panel">
      <h2>登录设备</h2>
      <?php if (empty($devices)): ?>
        <p class="muted" style="padding:12px;">暂无设备记录</p>
      <?php else: ?>
      <table>
        <thead><tr><th>设备 ID</th><th>平台</th><th>版本</th><th>状态</th><th>最近活跃</th><th>操作</th></tr></thead>
        <tbody>
        <?php foreach ($devices as $d): ?>
          <tr>
            <td><code><?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?></code></td>
            <td><?= htmlspecialchars($d['platform'], ENT_QUOTES, 'UTF-8') ?></td>
            <td><?= htmlspecialchars($d['app_version'], ENT_QUOTES, 'UTF-8') ?></td>
            <td><?= htmlspecialchars($d['status'], ENT_QUOTES, 'UTF-8') ?></td>
            <td class="muted"><?= htmlspecialchars(date('Y-m-d H:i', (int)($d['last_seen_at'] / 1000)), ENT_QUOTES, 'UTF-8') ?></td>
            <td>
              <?php if (($d['status'] ?? '') === 'ACTIVE'): ?>
              <form method="post" action="/admin/users/<?= (int)$user['id'] ?>/devices/<?= rawurlencode($d['device_id']) ?>/revoke"
                    onsubmit="return confirm('吊销后该设备下次控制检查将被拦截');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn">吊销</button>
              </form>
              <?php else: ?>—<?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
      <?php endif; ?>
    </div>
  </div>

  <div id="app"></div>
  <script>
    window.LEDGER_APP_CONFIG = {
      mode: 'admin',
      userId: <?= (int)$user['id'] ?>,
      username: <?= json_encode($user['username'] ?? '', JSON_UNESCAPED_UNICODE) ?>
    };
  </script>
  <script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
  <script src="/app/profit.js"></script>
  <script src="/app/backup.js"></script>
  <script src="/app/ledger-app.js"></script>
</body>
</html>
