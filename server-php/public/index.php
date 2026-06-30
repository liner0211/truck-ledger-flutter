<?php
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/lib/Config.php';
require $root . '/lib/JsonResponse.php';
require $root . '/lib/Jwt.php';
require $root . '/lib/Database.php';
require $root . '/lib/AuthService.php';
require $root . '/lib/LedgerService.php';
require $root . '/lib/AttachmentService.php';
require $root . '/lib/AdminService.php';

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
    extract($vars, EXTR_SKIP);
    require $root . '/templates/' . $template;
    exit;
}

// ---------- API（带 CORS）----------
if (strpos($uri, '/api/') === 0) {
    JsonResponse::cors();

    if ($uri === '/api/health' && $method === 'GET') {
        JsonResponse::send(['status' => 'ok']);
    }

    if ($uri === '/api/auth/register' && $method === 'POST') {
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
        $body = readJsonBody();
        $result = AuthService::login(
            $pdo,
            $cfg,
            (string)($body['username'] ?? ''),
            (string)($body['password'] ?? '')
        );
        JsonResponse::send($result);
    }

    if ($uri === '/api/auth/me' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send([
            'user_id' => (int)$user['id'],
            'username' => $user['username'],
            'license_plate' => (string)($user['license_plate'] ?? ''),
        ]);
    }

    if ($uri === '/api/ledger' && $method === 'GET') {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(LedgerService::get($pdo, (int)$user['id']));
    }

    if ($uri === '/api/ledger' && ($method === 'PUT' || $method === 'POST')) {
        $user = AuthService::requireUser($pdo, $cfg);
        JsonResponse::send(LedgerService::put($pdo, (int)$user['id'], readJsonBody()));
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
            JsonResponse::send(AttachmentService::upload($cfg, (int)$user['id'], $filename));
        }
    }

    JsonResponse::error('Not Found', 404);
}

// ---------- 管理后台 API（Session 鉴权）----------
if (strpos($uri, '/admin/api/') === 0) {
    AdminService::requireLoginJson();

    if (preg_match('#^/admin/api/users/(\d+)/ledger$#', $uri, $m)) {
        $userId = (int)$m[1];
        if ($method === 'GET') {
            $ledger = AdminService::getUserLedger($pdo, $userId);
            if ($ledger === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send($ledger);
        }
        if ($method === 'PUT' || $method === 'POST') {
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
            $user = AdminService::getUser($pdo, $userId);
            if ($user === null) {
                JsonResponse::error('用户不存在', 404);
            }
            AttachmentService::download($cfg, $userId, $filename);
        }
        if ($method === 'POST') {
            $user = AdminService::getUser($pdo, $userId);
            if ($user === null) {
                JsonResponse::error('用户不存在', 404);
            }
            JsonResponse::send(AttachmentService::upload($cfg, $userId, $filename));
        }
    }

    JsonResponse::error('Not Found', 404);
}

// ---------- 管理后台 ----------
if ($uri === '/' || $uri === '/admin') {
    if (AdminService::isLoggedIn()) {
        header('Location: /admin/dashboard');
    } else {
        header('Location: /admin/login');
    }
    exit;
}

if ($uri === '/admin/login' && $method === 'GET') {
    render('admin_login.php', [
        'error' => isset($_GET['error']) ? '密码错误' : '',
    ]);
}

if ($uri === '/admin/login' && $method === 'POST') {
    $password = (string)($_POST['password'] ?? '');
    if (!AdminService::login($password, $cfg)) {
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
    render('admin_dashboard.php', [
        'stats' => AdminService::stats($pdo, $cfg),
        'users' => AdminService::listUsers($pdo, $cfg),
        'message' => (string)($_GET['msg'] ?? ''),
    ]);
}

if (preg_match('#^/admin/users/(\d+)/delete$#', $uri, $m) && $method === 'POST') {
    AdminService::requireLogin();
    $name = AdminService::deleteUser($pdo, $cfg, (int)$m[1]);
    $msg = $name ? '已删除用户 ' . $name : '用户不存在';
    header('Location: /admin/dashboard?msg=' . urlencode($msg));
    exit;
}

if (preg_match('#^/admin/users/(\d+)/ledger$#', $uri, $m) && $method === 'GET') {
    AdminService::requireLogin();
    $user = AdminService::getUser($pdo, (int)$m[1]);
    if ($user === null) {
        http_response_code(404);
        echo '用户不存在';
        exit;
    }
    render('admin_user_ledger.php', ['user' => $user]);
}

http_response_code(404);
echo '404 Not Found';
