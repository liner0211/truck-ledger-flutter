<?php
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/lib/Config.php';
require $root . '/lib/JsonResponse.php';
require $root . '/lib/Jwt.php';
require $root . '/lib/Database.php';
require $root . '/lib/SettingsService.php';
require $root . '/lib/AttachmentService.php';
require $root . '/lib/EntitlementService.php';
require $root . '/lib/AuthService.php';
require $root . '/lib/LedgerService.php';
require $root . '/lib/SnapshotService.php';
require $root . '/lib/AppControlService.php';
require $root . '/lib/MessageService.php';
require $root . '/lib/PushService.php';
require $root . '/lib/AdminService.php';
require $root . '/lib/AdminAuthService.php';
require $root . '/lib/RateLimitService.php';

$cfg = Config::load($root);
$pdo = Database::conn($cfg);

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$uri = rtrim($uri, '/') ?: '/';

function readJsonBody(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function render(string $template, array $vars = []): void
{
    global $root;
    extract($vars, EXTR_OVERWRITE);
    require $root . '/templates/' . $template;
    exit;
}

function requestHeader(string $name): string
{
    $key = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
    return (string)($_SERVER[$key] ?? '');
}

// ---------- API（带 CORS）----------
if (strpos($uri, '/api/') === 0) {
    JsonResponse::cors($cfg);

    if ($uri === '/api/health' && $method === 'GET') {
        $deep = isset($_GET['deep']);
        if ($deep) {
            JsonResponse::send(AdminService::health($pdo, $cfg));
        }
        JsonResponse::send(['status' => 'ok']);
    }

    if ($uri === '/api/auth/config' && $method === 'GET') {
        JsonResponse::send(AuthService::publicConfig($pdo));
    }

    // CI：发布版本（更新 latest_version / 下载地址）；Header: X-CI-Token
    if ($uri === '/api/ci/publish-release' && $method === 'POST') {
        $expected = trim((string)($cfg['ci_publish_token'] ?? ''));
        $got = trim(requestHeader('X-CI-Token'));
        if ($expected === '' || $got === '' || !hash_equals($expected, $got)) {
            JsonResponse::error('CI 令牌无效', 401);
        }
        $body = readJsonBody();
        $version = trim((string)($body['latest_version'] ?? ''));
        if ($version === '') {
            JsonResponse::error('latest_version 不能为空', 400);
        }
        $adminId = null;
        AppControlService::setSetting($pdo, 'latest_version', $version, $adminId);
        if (array_key_exists('min_version', $body) && trim((string)$body['min_version']) !== '') {
            AppControlService::setSetting($pdo, 'min_version', trim((string)$body['min_version']), $adminId);
        }
        if (array_key_exists('apk_download_url', $body)) {
            AppControlService::setSetting($pdo, 'apk_download_url', trim((string)$body['apk_download_url']), $adminId);
        }
        if (array_key_exists('ios_download_url', $body)) {
            AppControlService::setSetting($pdo, 'ios_download_url', trim((string)$body['ios_download_url']), $adminId);
        }
        if (array_key_exists('update_release_notes', $body)) {
            AppControlService::setSetting($pdo, 'update_release_notes', trim((string)$body['update_release_notes']), $adminId);
        }
        if (array_key_exists('force_update', $body)) {
            $fu = (string)$body['force_update'];
            if (in_array($fu, ['0', '1'], true)) {
                AppControlService::setSetting($pdo, 'force_update', $fu, $adminId);
            }
        }
        AppControlService::audit($pdo, null, 'CI_PUBLISH_RELEASE', 'app_settings', 'latest_version', [
            'latest_version' => $version,
            'apk_download_url' => $body['apk_download_url'] ?? null,
            'ios_download_url' => $body['ios_download_url'] ?? null,
            'force_update' => $body['force_update'] ?? null,
        ]);
        JsonResponse::send([
            'ok' => true,
            'latest_version' => $version,
            'settings' => [
                'latest_version' => SettingsService::get($pdo, 'latest_version', $version),
                'min_version' => SettingsService::get($pdo, 'min_version', ''),
                'apk_download_url' => SettingsService::get($pdo, 'apk_download_url', ''),
                'ios_download_url' => SettingsService::get($pdo, 'ios_download_url', ''),
                'force_update' => SettingsService::get($pdo, 'force_update', '0'),
            ],
        ]);
    }

    // CI：管理端发版回写（与司机端字段分离）
    if ($uri === '/api/ci/publish-admin-release' && $method === 'POST') {
        $expected = trim((string)($cfg['ci_publish_token'] ?? ''));
        $got = trim(requestHeader('X-CI-Token'));
        if ($expected === '' || $got === '' || !hash_equals($expected, $got)) {
            JsonResponse::error('CI 令牌无效', 401);
        }
        $body = readJsonBody();
        $version = trim((string)($body['admin_latest_version'] ?? $body['latest_version'] ?? ''));
        if ($version === '') {
            JsonResponse::error('admin_latest_version 不能为空', 400);
        }
        AppControlService::setSetting($pdo, 'admin_latest_version', $version, null);
        $map = [
            'admin_min_version' => 'admin_min_version',
            'admin_apk_download_url' => 'admin_apk_download_url',
            'admin_ios_download_url' => 'admin_ios_download_url',
            'admin_linux_download_url' => 'admin_linux_download_url',
            'admin_windows_download_url' => 'admin_windows_download_url',
            'admin_update_release_notes' => 'admin_update_release_notes',
        ];
        foreach ($map as $bodyKey => $settingKey) {
            if (array_key_exists($bodyKey, $body)) {
                AppControlService::setSetting($pdo, $settingKey, trim((string)$body[$bodyKey]), null);
            }
        }
        if (array_key_exists('admin_force_update', $body) && in_array((string)$body['admin_force_update'], ['0', '1'], true)) {
            AppControlService::setSetting($pdo, 'admin_force_update', (string)$body['admin_force_update'], null);
        }
        AppControlService::audit($pdo, null, 'CI_PUBLISH_ADMIN_RELEASE', 'app_settings', 'admin_latest_version', [
            'admin_latest_version' => $version,
        ]);
        JsonResponse::send(['ok' => true, 'admin_latest_version' => $version]);
    }

    if ($uri === '/api/auth/register' && $method === 'POST') {
        RateLimitService::assert($cfg, 'register', 10, 3600);
        $body = readJsonBody();
        $result = AuthService::register(
            $pdo,
            $cfg,
            (string)($body['username'] ?? ''),
            (string)($body['password'] ?? ''),
            (string)($body['license_plate'] ?? '')
        );
        JsonResponse::send($result);
    }

    if ($uri === '/api/auth/login' && $method === 'POST') {
        RateLimitService::assert($cfg, 'login', 30, 600);
        $body = readJsonBody();
        $result = AuthService::login(
            $pdo,
            $cfg,
            (string)($body['username'] ?? ''),
            (string)($body['password'] ?? '')
        );
        JsonResponse::send($result);
    }

    if ($uri === '/api/auth/change-password' && $method === 'POST') {
        RateLimitService::assert($cfg, 'change_password', 10, 600);
        $user = AuthService::requireUser($pdo, $cfg);
        $body = readJsonBody();
        AuthService::changePassword(
            $pdo,
            $user,
            (string)($body['old_password'] ?? ''),
            (string)($body['new_password'] ?? '')
        );
        JsonResponse::send(['ok' => true, 'detail' => '密码已修改，请重新登录']);
    }

    if ($uri === '/api/auth/me' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(EntitlementService::publicProfile($pdo, $user));
    }

    if ($uri === '/api/app/check' && ($method === 'GET' || $method === 'POST')) {
        $user = AuthService::requireUser($pdo, $cfg);
        $body = $method === 'POST' ? readJsonBody() : [];
        $version = (string)($body['app_version'] ?? $_GET['app_version'] ?? requestHeader('X-App-Version') ?: '0.0.0');
        $deviceId = (string)($body['device_id'] ?? $_GET['device_id'] ?? requestHeader('X-Device-Id') ?: '');
        JsonResponse::send(AppControlService::check($pdo, $user, $version, $deviceId !== '' ? $deviceId : null));
    }

    if ($uri === '/api/ledger' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(LedgerService::get($pdo, (int)$user['id']));
    }

    if ($uri === '/api/ledger/revision' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(LedgerService::revision($pdo, (int)$user['id']));
    }

    if ($uri === '/api/ledger' && ($method === 'PUT' || $method === 'POST')) {
        $user = AuthService::requireUser($pdo, $cfg);
        EntitlementService::assertWriteAllowed($pdo, $user);
        $body = readJsonBody();
        $rounds = $body['rounds'] ?? [];
        EntitlementService::assertQuotaForRounds($pdo, $user, is_array($rounds) ? count($rounds) : 0);
        $ifMatch = requestHeader('If-Match');
        if ($ifMatch !== '' && !array_key_exists('base_revision', $body)) {
            $body['base_revision'] = (int)$ifMatch;
        }
        // 兼容旧客户端：未传 base_revision 时强制写入（仍递增 revision）
        $force = !array_key_exists('base_revision', $body);
        JsonResponse::send(LedgerService::put($pdo, (int)$user['id'], $body, null, $force, true));
    }

    if ($uri === '/api/attachments' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(AttachmentService::list($cfg, (int)$user['id']));
    }

    if (preg_match('#^/api/attachments/([^/]+)$#', $uri, $m)) {
        $user = AuthService::requireUser($pdo, $cfg);
        $filename = urldecode($m[1]);
        if ($method === 'GET') {
            AttachmentService::download($cfg, (int)$user['id'], $filename);
        }
        if ($method === 'POST') {
            EntitlementService::assertWriteAllowed($pdo, $user);
            EntitlementService::assertQuotaForAttachments($pdo, $cfg, $user);
            JsonResponse::send(AttachmentService::upload($cfg, (int)$user['id'], $filename));
        }
    }

    if ($uri === '/api/devices/push-token' && $method === 'POST') {
        $user = AuthService::requireUser($pdo, $cfg);
        $body = readJsonBody();
        PushService::upsertToken(
            $pdo,
            (int)$user['id'],
            (string)($body['device_id'] ?? ''),
            (string)($body['token'] ?? ''),
            (string)($body['platform'] ?? requestHeader('X-App-Platform') ?: 'unknown')
        );
        JsonResponse::send(['ok' => true]);
    }

    if ($uri === '/api/devices/push-token' && $method === 'DELETE') {
        $user = AuthService::requireUser($pdo, $cfg);
        $body = readJsonBody();
        PushService::removeToken($pdo, (int)$user['id'], (string)($body['device_id'] ?? ''));
        JsonResponse::send(['ok' => true]);
    }

    if ($uri === '/api/devices' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(['devices' => AppControlService::listDevices($pdo, (int)$user['id'])]);
    }

    if (preg_match('#^/api/devices/([^/]+)$#', $uri, $m) && $method === 'DELETE') {
        $user = AuthService::requireUser($pdo, $cfg);
        $deviceId = urldecode($m[1]);
        $ok = AppControlService::setDeviceStatus($pdo, (int)$user['id'], $deviceId, 'REVOKED', null);
        PushService::removeToken($pdo, (int)$user['id'], $deviceId);
        if (!$ok) {
            JsonResponse::error('设备不存在', 404);
        }
        JsonResponse::send(['ok' => true]);
    }

    if ($uri === '/api/messages' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send([
            'messages' => MessageService::listForUser($pdo, (int)$user['id']),
            'unread' => MessageService::unreadCount($pdo, (int)$user['id']),
        ]);
    }

    if ($uri === '/api/messages/read-all' && $method === 'POST') {
        $user = AuthService::requireUser($pdo, $cfg);
        MessageService::markAllRead($pdo, (int)$user['id']);
        JsonResponse::send(['ok' => true]);
    }

    if (preg_match('#^/api/messages/(\d+)/read$#', $uri, $m) && $method === 'POST') {
        $user = AuthService::requireUser($pdo, $cfg);
        MessageService::markRead($pdo, (int)$user['id'], (int)$m[1]);
        JsonResponse::send(['ok' => true]);
    }

    if (preg_match('#^/api/messages/(\d+)/attachments/([^/]+)$#', $uri, $m) && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        $msgId = (int)$m[1];
        if (MessageService::findForUser($pdo, (int)$user['id'], $msgId) === null) {
            JsonResponse::error('消息不存在', 404);
        }
        MessageService::downloadAttachment($cfg, $msgId, urldecode($m[2]));
    }

    // ---------- Admin Flutter / PC JSON API（JWT typ=admin）----------
    if ($uri === '/api/admin/login' && $method === 'POST') {
        RateLimitService::assert($cfg, 'admin_login', 20, 600);
        $body = readJsonBody();
        $username = (string)($body['username'] ?? '');
        $password = (string)($body['password'] ?? '');
        $admin = AdminAuthService::verifyLogin($pdo, $username, $password);
        if ($admin === null) {
            JsonResponse::error('用户名或密码错误', 401);
        }
        JsonResponse::send([
            'access_token' => AdminAuthService::createToken($admin, $cfg),
            'admin' => AdminAuthService::publicAdmin($admin),
        ]);
    }

    if (strpos($uri, '/api/admin/') === 0 && $uri !== '/api/admin/login') {
        $admin = AdminAuthService::requireAdminJwt($pdo, $cfg);
        $adminId = (int)$admin['id'];

        if ($uri === '/api/admin/me' && $method === 'GET') {
            JsonResponse::send(AdminAuthService::publicAdmin($admin));
        }

        if ($uri === '/api/admin/app/check' && ($method === 'GET' || $method === 'POST')) {
            $body = $method === 'POST' ? readJsonBody() : [];
            $ver = trim((string)($body['app_version'] ?? ($_GET['app_version'] ?? '')));
            if ($ver === '') {
                $ver = trim((string)($_SERVER['HTTP_X_APP_VERSION'] ?? '0.0.0'));
            }
            JsonResponse::send(AppControlService::adminAppCheck($pdo, $ver));
        }

        if (preg_match('#^/api/admin/users/(\d+)/messages$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'messages.send');
            $userId = (int)$m[1];
            if (AdminService::getUser($pdo, $userId) === null) {
                JsonResponse::error('用户不存在', 404);
            }
            $title = trim((string)($_POST['title'] ?? ''));
            $text = trim((string)($_POST['body'] ?? ''));
            $tripId = trim((string)($_POST['trip_id'] ?? ''));
            $tripTitle = trim((string)($_POST['trip_title'] ?? ''));
            // JSON fallback
            if ($title === '' && str_contains((string)($_SERVER['CONTENT_TYPE'] ?? ''), 'application/json')) {
                $body = readJsonBody();
                $title = trim((string)($body['title'] ?? ''));
                $text = trim((string)($body['body'] ?? ''));
                $tripId = trim((string)($body['trip_id'] ?? ''));
                $tripTitle = trim((string)($body['trip_title'] ?? ''));
            }
            if ($title === '' || $text === '') {
                JsonResponse::error('标题与内容不能为空', 400);
            }
            $meta = [
                'trip_id' => $tripId,
                'trip_title' => $tripTitle,
                'images' => [],
            ];
            $msgId = MessageService::create($pdo, $userId, $title, $text, 'ops.reconcile', null, $meta);
            $images = MessageService::saveUploadedImages($cfg, $msgId);
            if ($images !== []) {
                $meta['images'] = $images;
                $pdo->prepare('UPDATE messages SET meta_json=? WHERE id=?')->execute([
                    json_encode($meta, JSON_UNESCAPED_UNICODE) ?: '{}',
                    $msgId,
                ]);
            }
            PushService::sendToUser($pdo, $cfg, $userId, $title, $text);
            AppControlService::audit($pdo, $adminId, 'ADMIN_RECONCILE_MSG', 'user', (string)$userId, [
                'message_id' => $msgId,
                'trip_id' => $tripId,
            ]);
            JsonResponse::send(['ok' => true, 'message_id' => $msgId, 'images' => $images]);
        }

        if ($uri === '/api/admin/dashboard' && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'dashboard.read');
            $settings = AppControlService::settings($pdo);
            JsonResponse::send([
                'stats' => AdminService::stats($pdo, $cfg),
                'health' => AdminService::health($pdo, $cfg),
                'settings' => [
                    'app_status' => $settings['app_status'] ?? 'ACTIVE',
                    'min_version' => $settings['min_version'] ?? '',
                    'latest_version' => $settings['latest_version'] ?? '',
                    'force_update' => $settings['force_update'] ?? '0',
                    'apk_download_url' => $settings['apk_download_url'] ?? '',
                    'ios_download_url' => $settings['ios_download_url'] ?? '',
                    'update_release_notes' => $settings['update_release_notes'] ?? '',
                    'announcement' => $settings['announcement'] ?? '',
                    'maintenance_message' => $settings['maintenance_message'] ?? '',
                    'registration_enabled' => $settings['registration_enabled'] ?? '1',
                    'admin_latest_version' => $settings['admin_latest_version'] ?? '',
                    'admin_min_version' => $settings['admin_min_version'] ?? '',
                    'admin_force_update' => $settings['admin_force_update'] ?? '0',
                    'admin_apk_download_url' => $settings['admin_apk_download_url'] ?? '',
                    'admin_ios_download_url' => $settings['admin_ios_download_url'] ?? '',
                    'admin_linux_download_url' => $settings['admin_linux_download_url'] ?? '',
                    'admin_windows_download_url' => $settings['admin_windows_download_url'] ?? '',
                    'admin_update_release_notes' => $settings['admin_update_release_notes'] ?? '',
                ],
                'admin' => AdminAuthService::publicAdmin($admin),
            ]);
        }

        if ($uri === '/api/admin/settings' && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'dashboard.read');
            JsonResponse::send(['settings' => AppControlService::settings($pdo)]);
        }

        if ($uri === '/api/admin/settings' && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'control.write');
            $body = readJsonBody();
            $key = (string)($body['key'] ?? '');
            $value = (string)($body['value'] ?? '');
            AppControlService::setSetting($pdo, $key, $value, $adminId);
            JsonResponse::send(['ok' => true, 'key' => $key, 'value' => $value]);
        }

        if ($uri === '/api/admin/users' && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'users.read');
            JsonResponse::send(['users' => AdminService::listUsers($pdo, $cfg)]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/extend$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $body = readJsonBody();
            $days = max(1, (int)($body['days'] ?? 7));
            $msg = AdminService::extendTrial($pdo, (int)$m[1], $days);
            if ($msg === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => $msg]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/convert$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $msg = AdminService::convertPaid($pdo, (int)$m[1]);
            if ($msg === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => $msg]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/kick$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $stmt = $pdo->prepare('UPDATE users SET token_version=token_version+1 WHERE id=?');
            $stmt->execute([(int)$m[1]]);
            if ($stmt->rowCount() < 1) {
                JsonResponse::error('用户不存在', 404);
            }
            AppControlService::audit($pdo, $adminId, 'USER_KICK', 'user', $m[1], []);
            JsonResponse::send(['ok' => true, 'detail' => '已踢下线']);
        }

        if (preg_match('#^/api/admin/users/(\d+)/reset-password$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $body = readJsonBody();
            $newPass = (string)($body['password'] ?? '');
            if (strlen($newPass) < 6) {
                JsonResponse::error('新密码至少 6 位', 400);
            }
            $name = AuthService::adminResetPassword($pdo, (int)$m[1], $newPass);
            if ($name === null) {
                JsonResponse::error('用户不存在', 404);
            }
            AppControlService::audit($pdo, $adminId, 'USER_PASSWORD_RESET', 'user', $m[1], []);
            JsonResponse::send(['ok' => true, 'detail' => "已重置 {$name} 的密码"]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/enable$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $msg = AdminService::setUserEnabled($pdo, (int)$m[1], true);
            if ($msg === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => $msg]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/disable$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'users.write');
            $msg = AdminService::setUserEnabled($pdo, (int)$m[1], false);
            if ($msg === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => $msg]);
        }

        if (preg_match('#^/api/admin/users/(\d+)$#', $uri, $m) && $method === 'DELETE') {
            AdminAuthService::requirePermission($admin, 'users.delete');
            $name = AdminService::deleteUser($pdo, $cfg, (int)$m[1]);
            if ($name === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => "已删除 {$name}"]);
        }

        if ($uri === '/api/admin/push' && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'messages.send');
            $body = readJsonBody();
            $title = trim((string)($body['title'] ?? ''));
            $text = trim((string)($body['body'] ?? ''));
            $userId = (int)($body['user_id'] ?? 0);
            if ($title === '' || $text === '') {
                JsonResponse::error('标题与内容不能为空', 400);
            }
            if ($userId > 0) {
                $r = PushService::notifyUser($pdo, $cfg, $userId, $title, $text);
            } else {
                $r = PushService::broadcast($pdo, $cfg, $title, $text);
            }
            AppControlService::audit($pdo, $adminId, 'ADMIN_PUSH', 'message', (string)$userId, [
                'title' => $title,
            ]);
            JsonResponse::send(['ok' => true, 'sent' => $r['sent'] ?? 0]);
        }

        // JWT → 网页 Session：管理端打开与后台相同的账本编辑器
        if ($uri === '/api/admin/web-ticket' && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'dashboard.read');
            $body = readJsonBody();
            $redirect = AdminAuthService::sanitizeAdminRedirect(
                (string)($body['redirect'] ?? '/admin/dashboard')
            );
            if (str_contains($redirect, '/ledger')) {
                AdminAuthService::requirePermission($admin, 'ledger.read');
            }
            $ticket = AdminAuthService::createWebTicket($pdo, $adminId, $redirect);
            $path = '/admin/sso?ticket=' . rawurlencode($ticket);
            JsonResponse::send([
                'ok' => true,
                'ticket' => $ticket,
                'path' => $path,
                'redirect' => $redirect,
            ]);
        }

        if ($uri === '/api/admin/operators' && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            JsonResponse::send(['admins' => AdminAuthService::listAdmins($pdo)]);
        }

        if ($uri === '/api/admin/operators' && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            $body = readJsonBody();
            try {
                $created = AdminAuthService::createOperator(
                    $pdo,
                    (string)($body['username'] ?? ''),
                    (string)($body['password'] ?? ''),
                    $adminId
                );
            } catch (InvalidArgumentException $e) {
                JsonResponse::error($e->getMessage(), 400);
            }
            JsonResponse::send(['admin' => $created]);
        }

        if (preg_match('#^/api/admin/operators/(\d+)/enable$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            if (!AdminAuthService::setEnabled($pdo, (int)$m[1], true, $adminId)) {
                JsonResponse::error('管理员不存在', 404);
            }
            JsonResponse::send(['ok' => true]);
        }

        if (preg_match('#^/api/admin/operators/(\d+)/disable$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            try {
                if (!AdminAuthService::setEnabled($pdo, (int)$m[1], false, $adminId)) {
                    JsonResponse::error('管理员不存在', 404);
                }
            } catch (InvalidArgumentException $e) {
                JsonResponse::error($e->getMessage(), 400);
            }
            JsonResponse::send(['ok' => true]);
        }

        if (preg_match('#^/api/admin/operators/(\d+)/reset-password$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            $body = readJsonBody();
            try {
                if (!AdminAuthService::resetPassword($pdo, (int)$m[1], (string)($body['password'] ?? ''), $adminId)) {
                    JsonResponse::error('管理员不存在', 404);
                }
            } catch (InvalidArgumentException $e) {
                JsonResponse::error($e->getMessage(), 400);
            }
            JsonResponse::send(['ok' => true]);
        }

        if (preg_match('#^/api/admin/operators/(\d+)$#', $uri, $m) && $method === 'DELETE') {
            AdminAuthService::requirePermission($admin, 'admins.manage');
            try {
                if (!AdminAuthService::deleteAdmin($pdo, (int)$m[1], $adminId)) {
                    JsonResponse::error('管理员不存在', 404);
                }
            } catch (InvalidArgumentException $e) {
                JsonResponse::error($e->getMessage(), 400);
            }
            JsonResponse::send(['ok' => true, 'detail' => '已删除会计管理员']);
        }

        if (preg_match('#^/api/admin/users/(\d+)/ledger$#', $uri, $m)) {
            $userId = (int)$m[1];
            if ($method === 'GET') {
                AdminAuthService::requirePermission($admin, 'ledger.read');
                $ledger = AdminService::getUserLedger($pdo, $userId);
                if ($ledger === null) {
                    JsonResponse::error('用户不存在', 404);
                }
                JsonResponse::send($ledger);
            }
            if ($method === 'PUT' || $method === 'POST') {
                AdminAuthService::requirePermission($admin, 'ledger.write');
                $result = AdminService::putUserLedger($pdo, $userId, readJsonBody());
                if ($result === null) {
                    JsonResponse::error('用户不存在', 404);
                }
                AppControlService::audit($pdo, $adminId, 'ADMIN_LEDGER_PUT', 'user', (string)$userId, []);
                JsonResponse::send($result);
            }
        }

        if (preg_match('#^/api/admin/users/(\d+)/attachments/([^/]+)$#', $uri, $m)) {
            $userId = (int)$m[1];
            $filename = urldecode($m[2]);
            if ($method === 'GET') {
                AdminAuthService::requirePermission($admin, 'ledger.read');
                if (AdminService::getUser($pdo, $userId) === null) {
                    JsonResponse::error('用户不存在', 404);
                }
                AttachmentService::download($cfg, $userId, $filename);
            }
            if ($method === 'POST') {
                AdminAuthService::requirePermission($admin, 'ledger.write');
                if (AdminService::getUser($pdo, $userId) === null) {
                    JsonResponse::error('用户不存在', 404);
                }
                JsonResponse::send(AttachmentService::upload($cfg, $userId, $filename));
            }
        }

        if (preg_match('#^/api/admin/users/(\d+)/devices$#', $uri, $m) && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'users.read');
            JsonResponse::send(['devices' => AppControlService::listDevices($pdo, (int)$m[1])]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/devices/([^/]+)/revoke$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'devices.write');
            $ok = AppControlService::setDeviceStatus($pdo, (int)$m[1], urldecode($m[2]), 'REVOKED', $adminId);
            if (!$ok) {
                JsonResponse::error('设备不存在', 404);
            }
            JsonResponse::send(['ok' => true, 'detail' => '已吊销设备']);
        }

        if (preg_match('#^/api/admin/users/(\d+)/snapshots$#', $uri, $m) && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'ledger.read');
            JsonResponse::send(['snapshots' => SnapshotService::list($pdo, (int)$m[1])]);
        }

        if (preg_match('#^/api/admin/users/(\d+)/snapshots/(\d+)/restore$#', $uri, $m) && $method === 'POST') {
            AdminAuthService::requirePermission($admin, 'snapshots.restore');
            $result = SnapshotService::restore($pdo, (int)$m[1], (int)$m[2]);
            if ($result === null) {
                JsonResponse::error('快照不存在', 404);
            }
            AppControlService::audit($pdo, $adminId, 'SNAPSHOT_RESTORE', 'user', $m[1], ['snapshot_id' => (int)$m[2]]);
            JsonResponse::send($result);
        }

        if ($uri === '/api/admin/audits' && $method === 'GET') {
            AdminAuthService::requirePermission($admin, 'dashboard.read');
            $limit = max(1, min(100, (int)($_GET['limit'] ?? 30)));
            JsonResponse::send(['audits' => AppControlService::recentAudits($pdo, $limit)]);
        }

        JsonResponse::error('Not Found', 404);
    }

    JsonResponse::error('Not Found', 404);
}

// ---------- 管理后台 API（Session 鉴权）----------
if (strpos($uri, '/admin/api/') === 0) {
    AdminService::requireLoginJson();
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);

    if (preg_match('#^/admin/api/users/(\d+)/ledger$#', $uri, $m)) {
        $userId = (int)$m[1];
        if ($method === 'GET') {
            AdminAuthService::requirePermission($sessionAdmin, 'ledger.read');
            $ledger = AdminService::getUserLedger($pdo, $userId);
            if ($ledger === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send($ledger);
        }
        if ($method === 'PUT' || $method === 'POST') {
            AdminAuthService::requirePermission($sessionAdmin, 'ledger.write');
            $result = AdminService::putUserLedger($pdo, $userId, readJsonBody());
            if ($result === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send($result);
        }
    }

    if (preg_match('#^/admin/api/users/(\d+)/attachments/([^/]+)$#', $uri, $m)) {
        $userId = (int)$m[1];
        $filename = urldecode($m[2]);
        if ($method === 'GET') {
            AdminAuthService::requirePermission($sessionAdmin, 'ledger.read');
            $user = AdminService::getUser($pdo, $userId);
            if ($user === null) {
                JsonResponse::error('用户不存在', 404);
            }
            AttachmentService::download($cfg, $userId, $filename);
        }
        if ($method === 'POST') {
            AdminAuthService::requirePermission($sessionAdmin, 'ledger.write');
            $user = AdminService::getUser($pdo, $userId);
            if ($user === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(AttachmentService::upload($cfg, $userId, $filename));
        }
    }

    if (preg_match('#^/admin/api/users/(\d+)/snapshots$#', $uri, $m) && $method === 'GET') {
        AdminAuthService::requirePermission($sessionAdmin, 'ledger.read');
        JsonResponse::send(['snapshots' => SnapshotService::list($pdo, (int)$m[1])]);
    }

    if (preg_match('#^/admin/api/users/(\d+)/snapshots/(\d+)/restore$#', $uri, $m) && $method === 'POST') {
        AdminAuthService::requirePermission($sessionAdmin, 'snapshots.restore');
        $result = SnapshotService::restore($pdo, (int)$m[1], (int)$m[2]);
        if ($result === null) {
            JsonResponse::error('快照不存在', 404);
        }
        JsonResponse::send($result);
    }

    if (preg_match('#^/admin/api/users/(\d+)/devices$#', $uri, $m) && $method === 'GET') {
        AdminAuthService::requirePermission($sessionAdmin, 'users.read');
        JsonResponse::send(['devices' => AppControlService::listDevices($pdo, (int)$m[1])]);
    }

    JsonResponse::error('Not Found', 404);
}

// ---------- 管理后台页面 ----------
if ($uri === '/' || $uri === '/admin') {
    if (AdminService::isLoggedIn()) {
        header('Location: /admin/dashboard');
    } else {
        header('Location: /admin/login');
    }
    exit;
}

// 管理端 App 一次性票据换 Web Session，再跳转到完整账本/后台页
if ($uri === '/admin/sso' && $method === 'GET') {
    $ticket = (string)($_GET['ticket'] ?? '');
    $consumed = AdminAuthService::consumeWebTicket($pdo, $ticket);
    if ($consumed === null) {
        http_response_code(400);
        echo '登录票据无效或已过期，请在管理端重新打开。';
        exit;
    }
    AdminAuthService::loginSession($consumed['admin']);
    header('Location: ' . $consumed['redirect']);
    exit;
}

if ($uri === '/admin/login' && $method === 'GET') {
    render('admin_login.php', [
        'error' => isset($_GET['error']) ? '用户名或密码错误' : '',
        'default_username' => (string)($cfg['admin_username'] ?? 'liner0211'),
    ]);
}

if ($uri === '/admin/login' && $method === 'POST') {
    $username = trim((string)($_POST['username'] ?? ''));
    $password = (string)($_POST['password'] ?? '');
    if ($username === '') {
        $username = (string)($cfg['admin_username'] ?? 'liner0211');
    }
    if (!AdminService::loginWithCredentials($username, $password, $cfg, $pdo)) {
        header('Location: /admin/login?error=1');
        exit;
    }
    header('Location: /admin/dashboard');
    exit;
}

if ($uri === '/admin/logout') {
    AdminService::logout();
    header('Location: /admin/login');
    exit;
}

if ($uri === '/admin/dashboard' && $method === 'GET') {
    AdminService::requireLogin();
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    $settings = AppControlService::settings($pdo);
    render('admin_dashboard.php', [
        'stats' => AdminService::stats($pdo, $cfg),
        'users' => AdminService::listUsers($pdo, $cfg),
        'registration_enabled' => SettingsService::isRegistrationEnabled($pdo),
        'settings' => $settings,
        'audits' => AppControlService::recentAudits($pdo, 30),
        'health' => AdminService::health($pdo, $cfg),
        'csrf' => AdminService::csrfToken(),
        'message' => (string)($_GET['msg'] ?? ''),
        'admin' => $sessionAdmin ? AdminAuthService::publicAdmin($sessionAdmin) : null,
        'admins' => ($sessionAdmin && AdminAuthService::can($sessionAdmin, 'admins.manage'))
            ? AdminAuthService::listAdmins($pdo)
            : [],
    ]);
}

if ($uri === '/admin/settings' && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'control.write')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足：无法修改控制面'));
        exit;
    }
    $key = (string)($_POST['key'] ?? '');
    $value = (string)($_POST['value'] ?? '');
    try {
        AppControlService::setSetting($pdo, $key, $value, $sessionAdmin ? (int)$sessionAdmin['id'] : null);
        $msg = '已更新设置 ' . $key;
    } catch (Throwable $e) {
        $msg = '设置失败';
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if ($uri === '/admin/settings/registration' && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'control.write')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    $enabled = isset($_POST['enabled']) && (string)$_POST['enabled'] === '1';
    SettingsService::setRegistrationEnabled($pdo, $enabled);
    AppControlService::audit($pdo, $sessionAdmin ? (int)$sessionAdmin['id'] : null, 'REGISTRATION_TOGGLE', 'app_settings', 'registration_enabled', [
        'enabled' => $enabled,
    ]);
    $msg = $enabled ? '已开放用户注册' : '已关闭用户注册';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if ($uri === '/admin/push' && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'messages.send')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    $title = trim((string)($_POST['title'] ?? ''));
    $body = trim((string)($_POST['body'] ?? ''));
    $userId = (int)($_POST['user_id'] ?? 0);
    if ($title === '' || $body === '') {
        header('Location: /admin/dashboard?msg=' . urlencode('标题与内容不能为空'));
        exit;
    }
    if ($userId > 0) {
        $r = PushService::notifyUser($pdo, $cfg, $userId, $title, $body);
        $msg = "已通知用户 #{$userId}（推送成功 {$r['sent']}）";
    } else {
        $r = PushService::broadcast($pdo, $cfg, $title, $body);
        $msg = "已广播（推送成功 {$r['sent']}，站内信已写入）";
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/reset-password$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $newPass = trim((string)($_POST['new_password'] ?? ''));
    if (strlen($newPass) < 6) {
        header('Location: /admin/dashboard?msg=' . urlencode('新密码至少 6 位'));
        exit;
    }
    $name = AuthService::adminResetPassword($pdo, (int)$m[1], $newPass);
    $msg = $name ? "已重置 {$name} 的密码（需重新登录）" : '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/enable$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $msg = AdminService::setUserEnabled($pdo, (int)$m[1], true) ?? '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/disable$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $msg = AdminService::setUserEnabled($pdo, (int)$m[1], false) ?? '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/extend$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $days = max(1, (int)($_POST['days'] ?? 14));
    $msg = AdminService::extendTrial($pdo, (int)$m[1], $days) ?? '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/convert$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $msg = AdminService::convertPaid($pdo, (int)$m[1]) ?? '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/kick$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $pdo->prepare('UPDATE users SET token_version=token_version+1 WHERE id=?')->execute([(int)$m[1]]);
    AppControlService::audit($pdo, null, 'USER_KICK', 'user', $m[1], []);
    header('Location: /admin/dashboard?msg=' . urlencode('已踢下线（令牌失效）'));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/devices/([^/]+)/revoke$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'devices.write')) {
        header('Location: /admin/users/' . (int)$m[1] . '/ops?msg=' . urlencode('权限不足：仅开发者可吊销设备'));
        exit;
    }
    $ok = AppControlService::setDeviceStatus($pdo, (int)$m[1], urldecode($m[2]), 'REVOKED', $sessionAdmin ? (int)$sessionAdmin['id'] : null);
    $msg = $ok ? '已吊销设备' : '设备不存在';
    header('Location: /admin/users/' . (int)$m[1] . '/ops?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/delete$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'users.delete')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足：无法删除用户'));
        exit;
    }
    $name = AdminService::deleteUser($pdo, $cfg, (int)$m[1]);
    $msg = $name ? '已删除用户 ' . $name : '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if ($uri === '/admin/operators/create' && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'admins.manage')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    try {
        AdminAuthService::createOperator(
            $pdo,
            (string)($_POST['username'] ?? ''),
            (string)($_POST['password'] ?? ''),
            $sessionAdmin ? (int)$sessionAdmin['id'] : null
        );
        $msg = '已创建会计管理员';
    } catch (InvalidArgumentException $e) {
        $msg = $e->getMessage();
    } catch (Throwable $e) {
        $msg = '创建失败';
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/operators/(\d+)/enable$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'admins.manage')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    AdminAuthService::setEnabled($pdo, (int)$m[1], true, $sessionAdmin ? (int)$sessionAdmin['id'] : null);
    header('Location: /admin/dashboard?msg=' . urlencode('已启用'));
    exit;
}

if (preg_match('#^/admin/operators/(\d+)/disable$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'admins.manage')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    try {
        AdminAuthService::setEnabled($pdo, (int)$m[1], false, $sessionAdmin ? (int)$sessionAdmin['id'] : null);
        $msg = '已禁用';
    } catch (Throwable $e) {
        $msg = '操作失败';
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/operators/(\d+)/reset-password$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'admins.manage')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    try {
        AdminAuthService::resetPassword(
            $pdo,
            (int)$m[1],
            (string)($_POST['new_password'] ?? ''),
            $sessionAdmin ? (int)$sessionAdmin['id'] : null
        );
        $msg = '已重置运营密码';
    } catch (Throwable $e) {
        $msg = '重置失败';
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/operators/(\d+)/delete$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'admins.manage')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    try {
        AdminAuthService::deleteAdmin(
            $pdo,
            (int)$m[1],
            $sessionAdmin ? (int)$sessionAdmin['id'] : null
        );
        $msg = '已删除会计管理员';
    } catch (InvalidArgumentException $e) {
        $msg = $e->getMessage();
    } catch (Throwable $e) {
        $msg = '删除失败';
    }
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/ledger$#', $uri, $m) && $method === 'GET') {
    AdminService::requireLogin();
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'ledger.read')) {
        http_response_code(403);
        echo '权限不足：无法查看账本';
        exit;
    }
    $user = AdminService::getUser($pdo, (int)$m[1]);
    if ($user === null) {
        http_response_code(404);
        echo '用户不存在';
        exit;
    }
    $ledger = AdminService::getUserLedger($pdo, (int)$m[1]) ?? ['rounds' => [], 'updated_at' => 0, 'revision' => 0];
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    render('admin_user_ledger.php', [
        'user' => $user,
        'userId' => (int)$m[1],
        'ledger' => $ledger,
        'message' => (string)($_GET['msg'] ?? ''),
        'canOps' => AdminAuthService::can($sessionAdmin, 'devices.write')
            || AdminAuthService::can($sessionAdmin, 'snapshots.restore'),
    ]);
}

if (preg_match('#^/admin/users/(\d+)/ops$#', $uri, $m) && $method === 'GET') {
    AdminService::requireLogin();
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (
        !AdminAuthService::can($sessionAdmin, 'devices.write')
        && !AdminAuthService::can($sessionAdmin, 'snapshots.restore')
    ) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足：快照与设备仅开发者可访问'));
        exit;
    }
    $user = AdminService::getUser($pdo, (int)$m[1]);
    if ($user === null) {
        http_response_code(404);
        echo '用户不存在';
        exit;
    }
    render('admin_user_ops.php', [
        'user' => $user,
        'userId' => (int)$m[1],
        'snapshots' => SnapshotService::list($pdo, (int)$m[1]),
        'devices' => AppControlService::listDevices($pdo, (int)$m[1]),
        'csrf' => AdminService::csrfToken(),
        'message' => (string)($_GET['msg'] ?? ''),
        'admin' => AdminAuthService::publicAdmin($sessionAdmin ?? ['id'=>0,'username'=>'','role'=>'operator','is_enabled'=>1]),
    ]);
}

if (preg_match('#^/admin/users/(\d+)/snapshots/(\d+)/restore$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'snapshots.restore')) {
        header('Location: /admin/users/' . (int)$m[1] . '/ops?msg=' . urlencode('权限不足：仅开发者可恢复快照'));
        exit;
    }
    $result = SnapshotService::restore($pdo, (int)$m[1], (int)$m[2]);
    $msg = $result === null ? '快照不存在' : '已恢复到 revision ' . ($result['revision'] ?? '');
    header('Location: /admin/users/' . (int)$m[1] . '/ops?msg=' . urlencode($msg));
    exit;
}

if ($uri === '/admin/settings/feature-flags' && $method === 'POST') {
    AdminService::requireLogin();
    AdminService::assertCsrf($_POST['csrf'] ?? null);
    $sessionAdmin = AdminAuthService::currentSessionAdmin($pdo);
    if (!AdminAuthService::can($sessionAdmin, 'control.write')) {
        header('Location: /admin/dashboard?msg=' . urlencode('权限不足'));
        exit;
    }
    $flags = [
        'excel_export' => isset($_POST['excel_export']),
        'backup_import' => isset($_POST['backup_import']),
        'messages' => isset($_POST['messages']),
        'web_ledger' => isset($_POST['web_ledger']),
    ];
    AppControlService::setSetting(
        $pdo,
        'feature_flags',
        json_encode($flags, JSON_UNESCAPED_UNICODE) ?: '{}',
        $sessionAdmin ? (int)$sessionAdmin['id'] : null
    );
    header('Location: /admin/dashboard?msg=' . urlencode('功能开关已更新'));
    exit;
}

http_response_code(404);
echo '404 Not Found';
