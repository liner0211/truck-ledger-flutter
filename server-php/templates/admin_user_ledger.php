<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>账本 — <?= htmlspecialchars($user['username'], ENT_QUOTES, 'UTF-8') ?></title>
  <link rel="stylesheet" href="/app/app.css">
</head>
<body>
  <div id="app"></div>
  <script>
    window.LEDGER_APP_CONFIG = {
      mode: 'admin',
      userId: <?= (int)$user['id'] ?>,
      username: <?= json_encode($user['username'], JSON_UNESCAPED_UNICODE) ?>
    };
  </script>
  <script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
  <script src="/app/profit.js"></script>
  <script src="/app/backup.js"></script>
  <script src="/app/ledger-app.js"></script>
</body>
</html>
