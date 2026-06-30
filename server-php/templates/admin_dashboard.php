<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>管理后台 — 卡车记账</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; font-family: system-ui, sans-serif; background: #f4f6f4; color: #222; }
    header {
      background: #1b5e20; color: #fff; padding: 16px 24px;
      display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;
    }
    header h1 { margin: 0; font-size: 1.2rem; }
    header nav a { color: #c8e6c9; margin-left: 16px; text-decoration: none; font-size: .9rem; }
    main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 48px; }
    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 14px; margin-bottom: 24px; }
    .stat { background: #fff; border-radius: 12px; padding: 18px 16px; border: 1px solid #e0e0e0; }
    .stat .label { font-size: .8rem; color: #666; margin-bottom: 6px; }
    .stat .value { font-size: 1.6rem; font-weight: 700; color: #1b5e20; }
    .panel { background: #fff; border-radius: 12px; border: 1px solid #e0e0e0; overflow: hidden; }
    .panel h2 { margin: 0; padding: 16px 18px; font-size: 1rem; border-bottom: 1px solid #eee; }
    table { width: 100%; border-collapse: collapse; font-size: .88rem; }
    th, td { padding: 12px 14px; text-align: left; border-bottom: 1px solid #f0f0f0; }
    th { background: #fafafa; }
    .btn-del { padding: 6px 12px; border: 0; border-radius: 8px; background: #ffebee; color: #c62828; cursor: pointer; }
    .btn-view { padding: 6px 12px; border-radius: 8px; background: #e8f5e9; color: #1b5e20; text-decoration: none; font-size: .85rem; margin-right: 8px; display: inline-block; }
    .ops { white-space: nowrap; }
    .muted { color: #888; font-size: .82rem; }
    .flash { background: #e8f5e9; border: 1px solid #a5d6a7; color: #2e7d32; padding: 12px 16px; border-radius: 10px; margin-bottom: 16px; }
  </style>
</head>
<body>
  <header>
    <h1>🚛 卡车记账 · 管理后台（PHP）</h1>
    <nav>
      <a href="/app/" target="_blank">用户 Web 账本</a>
      <a href="/api/health" target="_blank">健康检查</a>
      <a href="/admin/logout">退出</a>
    </nav>
  </header>
  <main>
    <?php if (!empty($message)): ?>
      <div class="flash"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
    <?php endif; ?>
    <div class="stats">
      <div class="stat"><div class="label">注册用户</div><div class="value"><?= (int)$stats['user_count'] ?></div></div>
      <div class="stat"><div class="label">圈次总数</div><div class="value"><?= (int)$stats['round_count'] ?></div></div>
      <div class="stat"><div class="label">附件文件</div><div class="value"><?= (int)$stats['attachment_count'] ?></div></div>
      <div class="stat"><div class="label">数据占用</div><div class="value"><?= htmlspecialchars((string)$stats['data_size_mb'], ENT_QUOTES, 'UTF-8') ?> MB</div></div>
    </div>
    <div class="panel">
      <h2>用户列表</h2>
      <?php if (empty($users)): ?>
        <p style="padding:24px;color:#888;">暂无注册用户</p>
      <?php else: ?>
      <table>
        <thead>
          <tr>
            <th>ID</th><th>用户名</th><th>车牌号</th><th>注册时间</th><th>圈次</th><th>附件</th><th>最后同步</th><th>操作</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($users as $u): ?>
          <tr>
            <td><?= (int)$u['id'] ?></td>
            <td><strong><?= htmlspecialchars($u['username'], ENT_QUOTES, 'UTF-8') ?></strong></td>
            <td><?= htmlspecialchars($u['license_plate'] ?: '—', ENT_QUOTES, 'UTF-8') ?></td>
            <td class="muted"><?= htmlspecialchars($u['created_at'], ENT_QUOTES, 'UTF-8') ?></td>
            <td><?= (int)$u['round_count'] ?></td>
            <td><?= (int)$u['attachment_count'] ?></td>
            <td class="muted"><?= htmlspecialchars($u['updated_at'], ENT_QUOTES, 'UTF-8') ?></td>
            <td class="ops">
              <a class="btn-view" href="/admin/users/<?= (int)$u['id'] ?>/ledger" target="_blank">查看账本</a>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/delete" style="display:inline"
                    onsubmit="return confirm('确定删除用户 <?= htmlspecialchars($u['username'], ENT_QUOTES, 'UTF-8') ?>？');">
                <button type="submit" class="btn-del">删除</button>
              </form>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
      <?php endif; ?>
    </div>
  </main>
</body>
</html>
