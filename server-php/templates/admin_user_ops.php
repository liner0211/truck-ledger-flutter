<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>快照与设备 — <?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?></title>
  <style>
    body { margin: 0; background: #f5f5f5; font-family: system-ui, sans-serif; color: #222; }
    .wrap { max-width: 960px; margin: 0 auto; padding: 16px 12px 40px; }
    a { color: #1b5e20; }
    .panel { background: #fff; border: 1px solid #e0e0e0; border-radius: 12px; margin-bottom: 14px; overflow: hidden; }
    h1 { font-size: 1.15rem; margin: 0 0 8px; }
    h2 { margin: 0; padding: 12px 14px; font-size: .95rem; border-bottom: 1px solid #eee; }
    table { width: 100%; border-collapse: collapse; font-size: .85rem; }
    th, td { padding: 8px 12px; border-bottom: 1px solid #f0f0f0; text-align: left; }
    .flash { background: #e8f5e9; color: #2e7d32; padding: 10px 12px; border-radius: 8px; margin-bottom: 12px; }
    .btn { padding: 6px 10px; border: 0; border-radius: 8px; background: #fff3e0; color: #e65100; cursor: pointer; }
    .muted { color: #888; font-size: .8rem; }
    .nav { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; align-items: center; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="nav">
      <a href="/admin/dashboard">← 管理后台</a>
      <a href="/admin/users/<?= (int)$userId ?>/ledger">打开账本</a>
    </div>
    <h1>
      <?= htmlspecialchars($user['username'] ?? '', ENT_QUOTES, 'UTF-8') ?>
      <span class="muted">#<?= (int)$userId ?></span>
    </h1>
    <p class="muted" style="margin-top:0;">
      状态 <?= htmlspecialchars((string)($user['status'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
      · 套餐 <?= htmlspecialchars((string)($user['plan'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
      · 本页仅管理快照与登录设备，与账本圈次数据分开。
    </p>
    <?php if (!empty($message)): ?>
      <div class="flash"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
    <?php endif; ?>

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
              <?php if (!empty($admin) && in_array('snapshots.restore', $admin['permissions'] ?? [], true)): ?>
              <form method="post" action="/admin/users/<?= (int)$userId ?>/snapshots/<?= (int)$s['id'] ?>/restore"
                    onsubmit="return confirm('确定恢复到该快照？当前账本会再自动存一份快照。');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn">恢复</button>
              </form>
              <?php else: ?>
              <span class="muted">仅开发者</span>
              <?php endif; ?>
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
              <?php if (($d['status'] ?? '') === 'ACTIVE' && !empty($admin) && in_array('devices.write', $admin['permissions'] ?? [], true)): ?>
              <form method="post" action="/admin/users/<?= (int)$userId ?>/devices/<?= rawurlencode($d['device_id']) ?>/revoke"
                    onsubmit="return confirm('吊销后该设备下次控制检查将被拦截');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn">吊销</button>
              </form>
              <?php elseif (($d['status'] ?? '') === 'ACTIVE'): ?>
              <span class="muted">仅开发者</span>
              <?php else: ?>—<?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
      <?php endif; ?>
    </div>
  </div>
</body>
</html>
