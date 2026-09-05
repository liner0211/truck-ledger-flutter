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
    main { max-width: 1200px; margin: 0 auto; padding: 24px 16px 48px; }
    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 14px; margin-bottom: 24px; }
    .stat { background: #fff; border-radius: 12px; padding: 18px 16px; border: 1px solid #e0e0e0; }
    .stat .label { font-size: .8rem; color: #666; margin-bottom: 6px; }
    .stat .value { font-size: 1.5rem; font-weight: 700; color: #1b5e20; }
    .panel { background: #fff; border-radius: 12px; border: 1px solid #e0e0e0; overflow: hidden; margin-bottom: 20px; }
    .panel h2 { margin: 0; padding: 16px 18px; font-size: 1rem; border-bottom: 1px solid #eee; }
    .panel-body { padding: 16px 18px; }
    table { width: 100%; border-collapse: collapse; font-size: .85rem; }
    th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #f0f0f0; vertical-align: top; }
    th { background: #fafafa; }
    .btn-del { padding: 6px 10px; border: 0; border-radius: 8px; background: #ffebee; color: #c62828; cursor: pointer; }
    .btn-view { padding: 6px 10px; border-radius: 8px; background: #e8f5e9; color: #1b5e20; text-decoration: none; font-size: .82rem; margin-right: 4px; display: inline-block; }
    .btn-toggle { padding: 6px 10px; border: 0; border-radius: 8px; cursor: pointer; font-size: .82rem; margin: 2px 4px 2px 0; }
    .btn-disable { background: #fff3e0; color: #e65100; }
    .btn-enable { background: #e8f5e9; color: #1b5e20; }
    .btn-primary { padding: 8px 14px; border: 0; border-radius: 8px; background: #1b5e20; color: #fff; cursor: pointer; }
    .btn-warn { padding: 8px 14px; border: 0; border-radius: 8px; background: #ef6c00; color: #fff; cursor: pointer; }
    .ops { white-space: normal; min-width: 220px; }
    .muted { color: #888; font-size: .82rem; }
    .flash { background: #e8f5e9; border: 1px solid #a5d6a7; color: #2e7d32; padding: 12px 16px; border-radius: 10px; margin-bottom: 16px; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: .75rem; font-weight: 600; }
    .badge-ok { background: #e8f5e9; color: #2e7d32; }
    .badge-off { background: #ffebee; color: #c62828; }
    .badge-trial { background: #e3f2fd; color: #1565c0; }
    .badge-paid { background: #f3e5f5; color: #6a1b9a; }
    .setting-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; flex-wrap: wrap; margin-bottom: 14px; padding-bottom: 14px; border-bottom: 1px solid #f0f0f0; }
    .setting-row:last-child { border-bottom: 0; margin-bottom: 0; padding-bottom: 0; }
    input[type=text], input[type=number], select, textarea {
      padding: 8px 10px; border: 1px solid #ccc; border-radius: 8px; font-size: .9rem; min-width: 160px;
    }
    textarea { width: 100%; min-height: 64px; }
    .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    @media (max-width: 900px) { .grid2 { grid-template-columns: 1fr; } }
    .health-ok { color: #2e7d32; }
    .health-bad { color: #c62828; }
    code { font-size: .78rem; background: #f5f5f5; padding: 1px 4px; border-radius: 4px; }
  </style>
</head>
<body>
  <header>
    <h1>卡车记账 · 管理后台</h1>
    <nav>
      <?php if (!empty($admin)): ?>
        <span style="color:#c8e6c9;font-size:.85rem;margin-right:8px">
          <?= htmlspecialchars($admin['username'], ENT_QUOTES, 'UTF-8') ?>
          · <?= htmlspecialchars($admin['role'] === 'super' ? '超级管理员' : '运营', ENT_QUOTES, 'UTF-8') ?>
        </span>
      <?php endif; ?>
      <a href="/app/" target="_blank">用户 Web 账本</a>
      <a href="/api/health?deep=1" target="_blank">健康检查</a>
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
      <div class="stat"><div class="label">设备数</div><div class="value"><?= (int)($stats['device_count'] ?? 0) ?></div></div>
      <div class="stat"><div class="label">站内信</div><div class="value"><?= (int)($stats['message_count'] ?? 0) ?></div></div>
      <div class="stat"><div class="label">数据占用</div><div class="value"><?= htmlspecialchars((string)$stats['data_size_mb'], ENT_QUOTES, 'UTF-8') ?> MB</div></div>
    </div>

    <div class="grid2">
      <div class="panel">
        <h2>系统健康</h2>
        <div class="panel-body">
          <div>总体：
            <strong class="<?= ($health['status'] ?? '') === 'ok' ? 'health-ok' : 'health-bad' ?>">
              <?= htmlspecialchars((string)($health['status'] ?? ''), ENT_QUOTES, 'UTF-8') ?>
            </strong>
          </div>
          <ul class="muted" style="margin:10px 0 0; padding-left:18px;">
            <?php foreach (($health['checks'] ?? []) as $k => $v): ?>
              <li><?= htmlspecialchars((string)$k, ENT_QUOTES, 'UTF-8') ?>:
                <code><?= htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8') ?></code>
              </li>
            <?php endforeach; ?>
          </ul>
        </div>
      </div>

      <div class="panel">
        <h2>注册开关</h2>
        <div class="panel-body setting-row">
          <div>
            <strong>用户注册</strong>
            <div class="muted" style="margin-top:4px;">
              当前：<?= !empty($registration_enabled) ? '已开放' : '已关闭' ?>
            </div>
          </div>
          <form method="post" action="/admin/settings/registration" style="display:inline">
            <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
            <?php if (!empty($registration_enabled)): ?>
              <input type="hidden" name="enabled" value="0">
              <button type="submit" class="btn-warn" onclick="return confirm('确定关闭注册？');">关闭注册</button>
            <?php else: ?>
              <input type="hidden" name="enabled" value="1">
              <button type="submit" class="btn-primary">开放注册</button>
            <?php endif; ?>
          </form>
        </div>
      </div>
    </div>

    <div class="panel">
      <h2>应用控制面</h2>
      <div class="panel-body">
        <?php
          $ctrlFields = [
            'app_status' => ['应用状态', 'select', ['ACTIVE'=>'运行','MAINTENANCE'=>'维护','DISABLED'=>'停用']],
            'min_version' => ['最低版本', 'text', null],
            'latest_version' => ['最新版本', 'text', null],
            'force_update' => ['强制升级(仅低于最新版时拦截)', 'select', ['0'=>'否','1'=>'是']],
            'apk_download_url' => ['Android APK 下载地址', 'text', null],
            'ios_download_url' => ['iOS 安装包/页面地址', 'text', null],
            'update_release_notes' => ['更新说明', 'text', null],
            'maintenance_message' => ['维护文案', 'text', null],
            'announcement' => ['全局公告', 'text', null],
            'offline_grace_sec' => ['离线宽限秒数', 'number', null],
            'trial_days' => ['试用天数', 'number', null],
            'trial_max_rounds' => ['试用圈次上限(0不限)', 'number', null],
            'trial_max_attachments' => ['试用附件上限(0不限)', 'number', null],
            'expiry_policy' => ['到期策略', 'select', ['readonly'=>'只读','block'=>'禁止登录']],
          ];
          $canControl = !empty($admin) && in_array('control.write', $admin['permissions'] ?? [], true);
          foreach ($ctrlFields as $key => $meta):
            $label = $meta[0]; $type = $meta[1]; $opts = $meta[2];
            $val = (string)($settings[$key] ?? '');
        ?>
        <div class="setting-row">
          <div>
            <strong><?= htmlspecialchars($label, ENT_QUOTES, 'UTF-8') ?></strong>
            <div class="muted"><code><?= htmlspecialchars($key, ENT_QUOTES, 'UTF-8') ?></code>
              当前：<?= htmlspecialchars($val !== '' ? $val : '—', ENT_QUOTES, 'UTF-8') ?></div>
          </div>
          <?php if ($canControl): ?>
          <form method="post" action="/admin/settings" style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
            <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="key" value="<?= htmlspecialchars($key, ENT_QUOTES, 'UTF-8') ?>">
            <?php if ($type === 'select' && is_array($opts)): ?>
              <select name="value">
                <?php foreach ($opts as $ov => $ol): ?>
                  <option value="<?= htmlspecialchars((string)$ov, ENT_QUOTES, 'UTF-8') ?>" <?= $val === (string)$ov ? 'selected' : '' ?>>
                    <?= htmlspecialchars($ol, ENT_QUOTES, 'UTF-8') ?>
                  </option>
                <?php endforeach; ?>
              </select>
            <?php else: ?>
              <input type="<?= $type === 'number' ? 'number' : 'text' ?>" name="value" value="<?= htmlspecialchars($val, ENT_QUOTES, 'UTF-8') ?>" style="min-width:220px">
            <?php endif; ?>
            <button type="submit" class="btn-primary">保存</button>
          </form>
          <?php else: ?>
            <span class="muted">只读（需超级管理员）</span>
          <?php endif; ?>
        </div>
        <?php endforeach; ?>
        <p class="muted" style="margin-top:12px">说明：开启「强制升级」后，仅当客户端版本 &lt; 最新版本时才会拦截；已达最新版可正常使用。</p>
      </div>
    </div>

    <div class="panel">
      <h2>功能开关</h2>
      <div class="panel-body">
        <?php
          $ffRaw = (string)($settings['feature_flags'] ?? '');
          $ff = json_decode($ffRaw, true);
          if (!is_array($ff)) {
            $ff = ['excel_export'=>true,'backup_import'=>true,'messages'=>true,'web_ledger'=>true];
          }
        ?>
        <form method="post" action="/admin/settings/feature-flags">
          <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
          <label style="display:block;margin:6px 0;"><input type="checkbox" name="excel_export" <?= !empty($ff['excel_export'])?'checked':'' ?>> Excel / 报表导出</label>
          <label style="display:block;margin:6px 0;"><input type="checkbox" name="backup_import" <?= !empty($ff['backup_import'])?'checked':'' ?>> 备份导入导出</label>
          <label style="display:block;margin:6px 0;"><input type="checkbox" name="messages" <?= !empty($ff['messages'])?'checked':'' ?>> 消息中心</label>
          <label style="display:block;margin:6px 0;"><input type="checkbox" name="web_ledger" <?= !empty($ff['web_ledger'])?'checked':'' ?>> Web 账本入口提示</label>
          <div style="margin-top:12px;"><button type="submit" class="btn-primary">保存开关</button></div>
        </form>
      </div>
    </div>

    <div class="panel">
      <h2>远程通知 / 站内信</h2>
      <div class="panel-body">
        <form method="post" action="/admin/push">
          <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
          <div class="setting-row">
            <div style="flex:1; min-width:220px;">
              <label class="muted">标题</label><br>
              <input type="text" name="title" required placeholder="维护预告 / 试用提醒…" style="width:100%;">
            </div>
            <div style="width:140px;">
              <label class="muted">用户 ID（空=广播）</label><br>
              <input type="number" name="user_id" min="0" placeholder="0">
            </div>
          </div>
          <label class="muted">内容</label>
          <textarea name="body" required placeholder="通知正文"></textarea>
          <div style="margin-top:12px;">
            <button type="submit" class="btn-primary">发送（站内信必达；FCM 可选）</button>
            <span class="muted">未配置 fcm_server_key 时仍会写入站内信。</span>
          </div>
        </form>
      </div>
    </div>

    <div class="panel">
      <h2>用户列表</h2>
      <?php if (empty($users)): ?>
        <p style="padding:24px;color:#888;">暂无注册用户</p>
      <?php else: ?>
      <div style="overflow-x:auto;">
      <table>
        <thead>
          <tr>
            <th>ID</th><th>用户</th><th>状态</th><th>套餐</th><th>到期</th>
            <th>圈次</th><th>附件</th><th>rev</th><th>同步</th><th>操作</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($users as $u): ?>
          <?php
            $enabled = !empty($u['is_enabled']);
            $st = (string)($u['status'] ?? '');
            $plan = (string)($u['plan'] ?? '');
          ?>
          <tr>
            <td><?= (int)$u['id'] ?></td>
            <td>
              <strong><?= htmlspecialchars($u['username'], ENT_QUOTES, 'UTF-8') ?></strong><br>
              <span class="muted"><?= htmlspecialchars($u['license_plate'] ?: '—', ENT_QUOTES, 'UTF-8') ?></span>
            </td>
            <td>
              <?php if ($st === 'ACTIVE' && $enabled): ?>
                <span class="badge badge-ok">ACTIVE</span>
              <?php elseif ($st === 'EXPIRED'): ?>
                <span class="badge badge-off">EXPIRED</span>
              <?php else: ?>
                <span class="badge badge-off"><?= htmlspecialchars($st ?: 'OFF', ENT_QUOTES, 'UTF-8') ?></span>
              <?php endif; ?>
            </td>
            <td>
              <span class="badge <?= $plan === 'paid' ? 'badge-paid' : 'badge-trial' ?>">
                <?= htmlspecialchars($plan, ENT_QUOTES, 'UTF-8') ?>
              </span>
            </td>
            <td class="muted">
              <?php if (!empty($u['expires_at'])): ?>
                <?= htmlspecialchars(date('Y-m-d', (int)($u['expires_at'] / 1000)), ENT_QUOTES, 'UTF-8') ?>
                <?php if ($u['days_left'] !== null): ?>
                  <br>(<?= (int)$u['days_left'] ?>天)
                <?php endif; ?>
              <?php else: ?>—<?php endif; ?>
            </td>
            <td><?= (int)$u['round_count'] ?></td>
            <td><?= (int)$u['attachment_count'] ?></td>
            <td><?= (int)($u['revision'] ?? 0) ?></td>
            <td class="muted"><?= htmlspecialchars($u['updated_at'], ENT_QUOTES, 'UTF-8') ?></td>
            <td class="ops">
              <a class="btn-view" href="/admin/users/<?= (int)$u['id'] ?>/ledger" target="_blank">账本</a>
              <a class="btn-view" href="/admin/users/<?= (int)$u['id'] ?>/ops" target="_blank">快照/设备</a>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/extend" style="display:inline">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <input type="hidden" name="days" value="14">
                <button type="submit" class="btn-toggle btn-enable">延期14天</button>
              </form>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/convert" style="display:inline">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn-toggle btn-enable">转正</button>
              </form>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/reset-password" style="display:inline"
                    onsubmit="var p=prompt('输入新密码（至少6位）'); if(!p||p.length<6){alert('密码太短');return false;} this.new_password.value=p; return confirm('确定重置密码？');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <input type="hidden" name="new_password" value="">
                <button type="submit" class="btn-toggle btn-disable">重置密码</button>
              </form>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/kick" style="display:inline"
                    onsubmit="return confirm('踢下线后需重新登录，确定？');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn-toggle btn-disable">踢下线</button>
              </form>
              <?php if ($enabled): ?>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/disable" style="display:inline"
                    onsubmit="return confirm('禁止后该用户将无法登录，确定？');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn-toggle btn-disable">禁止</button>
              </form>
              <?php else: ?>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/enable" style="display:inline">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn-toggle btn-enable">允许</button>
              </form>
              <?php endif; ?>
              <form method="post" action="/admin/users/<?= (int)$u['id'] ?>/delete" style="display:inline"
                    onsubmit="return confirm('确定删除用户 <?= htmlspecialchars($u['username'], ENT_QUOTES, 'UTF-8') ?>？');">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                <button type="submit" class="btn-del">删除</button>
              </form>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
      </div>
      <?php endif; ?>
    </div>

    <div class="panel">
      <h2>最近审计</h2>
      <div class="panel-body" style="overflow-x:auto;">
        <?php if (empty($audits)): ?>
          <p class="muted">暂无审计记录</p>
        <?php else: ?>
        <table>
          <thead><tr><th>时间</th><th>动作</th><th>目标</th><th>详情</th></tr></thead>
          <tbody>
          <?php foreach ($audits as $a): ?>
            <tr>
              <td class="muted"><?= htmlspecialchars(date('Y-m-d H:i', (int)($a['created_at'] / 1000)), ENT_QUOTES, 'UTF-8') ?></td>
              <td><code><?= htmlspecialchars($a['action'], ENT_QUOTES, 'UTF-8') ?></code></td>
              <td><?= htmlspecialchars($a['target_type'] . ':' . $a['target_id'], ENT_QUOTES, 'UTF-8') ?></td>
              <td class="muted"><code><?= htmlspecialchars(json_encode($a['details'], JSON_UNESCAPED_UNICODE) ?: '', ENT_QUOTES, 'UTF-8') ?></code></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
        <?php endif; ?>
      </div>
    </div>

    <?php if (!empty($admin) && in_array('admins.manage', $admin['permissions'] ?? [], true)): ?>
    <div class="panel">
      <h2>运营账号</h2>
      <div class="panel-body">
        <form method="post" action="/admin/operators/create" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px;align-items:end">
          <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
          <div>
            <label class="muted">用户名</label><br>
            <input type="text" name="username" required pattern="[A-Za-z0-9_]{3,32}">
          </div>
          <div>
            <label class="muted">初始密码</label><br>
            <input type="password" name="password" required minlength="6">
          </div>
          <button type="submit" class="btn-primary">创建运营账号</button>
        </form>
        <table>
          <thead><tr><th>ID</th><th>用户名</th><th>角色</th><th>状态</th><th>操作</th></tr></thead>
          <tbody>
          <?php foreach (($admins ?? []) as $op): ?>
            <tr>
              <td><?= (int)$op['id'] ?></td>
              <td><?= htmlspecialchars($op['username'], ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= htmlspecialchars($op['role'], ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= !empty($op['is_enabled']) ? '启用' : '禁用' ?></td>
              <td>
                <?php if ($op['role'] !== 'super'): ?>
                  <?php if (!empty($op['is_enabled'])): ?>
                  <form method="post" action="/admin/operators/<?= (int)$op['id'] ?>/disable" style="display:inline">
                    <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                    <button type="submit" class="btn-toggle btn-disable">禁用</button>
                  </form>
                  <?php else: ?>
                  <form method="post" action="/admin/operators/<?= (int)$op['id'] ?>/enable" style="display:inline">
                    <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                    <button type="submit" class="btn-toggle btn-enable">启用</button>
                  </form>
                  <?php endif; ?>
                  <form method="post" action="/admin/operators/<?= (int)$op['id'] ?>/reset-password" style="display:inline"
                        onsubmit="var p=prompt('新密码(至少6位)'); if(!p||p.length<6) return false; this.new_password.value=p; return true;">
                    <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
                    <input type="hidden" name="new_password" value="">
                    <button type="submit" class="btn-toggle">重置密码</button>
                  </form>
                <?php else: ?>
                  <span class="muted">—</span>
                <?php endif; ?>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </div>
    <?php endif; ?>
  </main>
</body>
</html>
