<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>管理员登录 — 卡车记账</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      font-family: system-ui, sans-serif;
      background: linear-gradient(135deg, #1b5e20 0%, #2e7d32 50%, #1b5e20 100%);
      color: #1a1a1a;
    }
    .card {
      width: min(400px, 92vw); background: #fff; border-radius: 16px;
      padding: 32px 28px; box-shadow: 0 20px 60px rgba(0,0,0,.25);
    }
    h1 { margin: 0 0 8px; font-size: 1.35rem; color: #1b5e20; }
    p { margin: 0 0 24px; color: #666; font-size: .9rem; }
    label { display: block; margin-bottom: 6px; font-size: .85rem; font-weight: 600; }
    input {
      width: 100%; padding: 12px 14px; border: 1px solid #ccc;
      border-radius: 10px; font-size: 1rem; margin-bottom: 16px;
    }
    button {
      width: 100%; padding: 12px; border: 0; border-radius: 10px;
      background: #1b5e20; color: #fff; font-size: 1rem; font-weight: 600; cursor: pointer;
    }
    button:hover { background: #2e7d32; }
    .err { color: #c62828; font-size: .9rem; margin-bottom: 12px; }
    .hint { margin-top: 20px; font-size: .78rem; color: #888; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🚛 卡车记账 · 管理后台</h1>
    <p>请输入管理员密码（config.php 中 admin_password）</p>
    <?php if (!empty($error)): ?><div class="err"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div><?php endif; ?>
    <form method="post" action="/admin/login">
      <label for="password">管理员密码</label>
      <input id="password" name="password" type="password" autofocus required>
      <button type="submit">登录</button>
    </form>
    <div class="hint">健康检查：<a href="/api/health">/api/health</a></div>
  </div>
</body>
</html>
