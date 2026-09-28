<?php
declare(strict_types=1);

final class Database
{
    private static ?PDO $pdo = null;

    public static function conn(array $cfg): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }
        $dataDir = $cfg['data_dir'];
        if (!is_dir($dataDir)) {
            mkdir($dataDir, 0755, true);
        }
        $attDir = $cfg['attachments_dir'];
        if (!is_dir($attDir)) {
            mkdir($attDir, 0755, true);
        }
        self::$pdo = new PDO('sqlite:' . $cfg['db_path']);
        self::$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        self::$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        self::$pdo->exec('PRAGMA foreign_keys = ON');
        self::migrate(self::$pdo, $cfg);
        return self::$pdo;
    }

    private static function migrate(PDO $pdo, array $cfg): void
    {
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                license_plate TEXT NOT NULL DEFAULT "",
                created_at INTEGER NOT NULL
            )'
        );
        self::ensureColumn($pdo, 'users', 'license_plate', 'TEXT NOT NULL DEFAULT ""');
        self::ensureColumn($pdo, 'users', 'is_enabled', 'INTEGER NOT NULL DEFAULT 1');
        self::ensureColumn($pdo, 'users', 'status', "TEXT NOT NULL DEFAULT 'ACTIVE'");
        self::ensureColumn($pdo, 'users', 'plan', "TEXT NOT NULL DEFAULT 'trial'");
        self::ensureColumn($pdo, 'users', 'expires_at', 'INTEGER');
        self::ensureColumn($pdo, 'users', 'token_version', 'INTEGER NOT NULL DEFAULT 0');

        // 兼容旧库：is_enabled=0 → SUSPENDED
        $pdo->exec("UPDATE users SET status='SUSPENDED' WHERE is_enabled=0 AND status='ACTIVE'");

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT 0
            )'
        );
        self::ensureColumn($pdo, 'app_settings', 'updated_at', 'INTEGER NOT NULL DEFAULT 0');

        $defaults = [
            'registration_enabled' => '1',
            'trial_days' => '14',
            'trial_max_rounds' => '30',
            'trial_max_attachments' => '100',
            'expiry_policy' => 'readonly', // readonly | block
            'app_status' => 'ACTIVE',
            'min_version' => '1.0.0',
            'latest_version' => '1.2.0',
            'force_update' => '0',
            'maintenance_message' => '',
            'offline_grace_sec' => '259200',
            'control_version' => '1',
            'announcement' => '',
            'feature_flags' => '{"excel_export":true,"backup_import":true,"messages":true,"web_ledger":true}',
            // 客服会话默认接待管理员 id（0=任意有 messages.send 的管理员可回复）
            'support_admin_id' => '0',
            'apk_download_url' => '',
            'ios_download_url' => '',
            'update_release_notes' => '',
            'admin_latest_version' => '',
            'admin_min_version' => '',
            'admin_force_update' => '0',
            'admin_apk_download_url' => '',
            'admin_ios_download_url' => '',
            'admin_linux_download_url' => '',
            'admin_windows_download_url' => '',
            'admin_update_release_notes' => '',
        ];
        $now = (int)(microtime(true) * 1000);
        $ins = $pdo->prepare('INSERT OR IGNORE INTO app_settings (key, value, updated_at) VALUES (?,?,?)');
        foreach ($defaults as $k => $v) {
            $ins->execute([$k, $v, $now]);
        }

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS admins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT \'operator\',
                is_enabled INTEGER NOT NULL DEFAULT 1,
                token_version INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                last_login_at INTEGER
            )'
        );
        self::seedSuperAdmin($pdo, $cfg);

        // 管理端 App JWT → 网页 Session 的一次性票据
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS admin_sso_tickets (
                ticket TEXT PRIMARY KEY,
                admin_id INTEGER NOT NULL,
                redirect TEXT NOT NULL,
                expires_at INTEGER NOT NULL,
                FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
            )'
        );

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS ledgers (
                user_id INTEGER PRIMARY KEY,
                data_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                revision INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );
        self::ensureColumn($pdo, 'ledgers', 'revision', 'INTEGER NOT NULL DEFAULT 0');

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS devices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                device_id TEXT NOT NULL,
                platform TEXT NOT NULL DEFAULT "unknown",
                app_version TEXT NOT NULL DEFAULT "",
                status TEXT NOT NULL DEFAULT "ACTIVE",
                registered_at INTEGER NOT NULL,
                last_seen_at INTEGER NOT NULL,
                UNIQUE(user_id, device_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS push_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                device_id TEXT NOT NULL,
                token TEXT NOT NULL,
                platform TEXT NOT NULL DEFAULT "unknown",
                updated_at INTEGER NOT NULL,
                UNIQUE(user_id, device_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT "ops.broadcast",
                created_at INTEGER NOT NULL,
                expires_at INTEGER
            )'
        );
        self::ensureColumn($pdo, 'messages', 'meta_json', 'TEXT');
        self::ensureColumn($pdo, 'messages', 'admin_id', 'INTEGER');
        self::ensureColumn($pdo, 'messages', 'force_deleted_at', 'INTEGER');
        $msgAtt = $cfg['message_attachments_dir'] ?? ($cfg['data_dir'] . '/message_attachments');
        if (!is_dir($msgAtt)) {
            mkdir($msgAtt, 0755, true);
        }
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS message_reads (
                message_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                read_at INTEGER NOT NULL,
                PRIMARY KEY (message_id, user_id),
                FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );
        // 站内信回复线程（用户/管理员）
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS message_replies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                message_id INTEGER NOT NULL,
                sender_role TEXT NOT NULL,
                sender_user_id INTEGER,
                sender_admin_id INTEGER,
                body TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
            )'
        );
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_message_replies_msg ON message_replies(message_id, created_at)');
        // 用户 ↔ 管理员客服会话（每用户一条线程）
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS support_threads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL UNIQUE,
                admin_id INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS support_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                thread_id INTEGER NOT NULL,
                sender_role TEXT NOT NULL,
                sender_user_id INTEGER,
                sender_admin_id INTEGER,
                body TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                read_by_peer_at INTEGER,
                FOREIGN KEY (thread_id) REFERENCES support_threads(id) ON DELETE CASCADE
            )'
        );
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_support_msgs_thread ON support_messages(thread_id, created_at)');

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                admin_id INTEGER,
                action TEXT NOT NULL,
                target_type TEXT NOT NULL,
                target_id TEXT NOT NULL,
                details_json TEXT,
                created_at INTEGER NOT NULL
            )'
        );

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS ledger_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                revision INTEGER NOT NULL,
                data_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                note TEXT NOT NULL DEFAULT "",
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_snapshots_user ON ledger_snapshots(user_id, created_at DESC)');
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at DESC)');
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id)');
    }

    private static function seedSuperAdmin(PDO $pdo, array $cfg): void
    {
        $count = (int)$pdo->query('SELECT COUNT(*) FROM admins')->fetchColumn();
        if ($count > 0) {
            return;
        }
        $username = trim((string)($cfg['admin_username'] ?? 'liner0211'));
        if ($username === '') {
            $username = 'liner0211';
        }
        $hash = (string)($cfg['admin_password_hash'] ?? '');
        if ($hash === '') {
            $plain = (string)($cfg['admin_password'] ?? '');
            if ($plain !== '' && str_starts_with($plain, '$2y$')) {
                $hash = $plain;
            } elseif ($plain !== '' && $plain !== '请改成强密码') {
                $hash = password_hash($plain, PASSWORD_BCRYPT);
            }
        }
        if ($hash === '') {
            // 无可用密码时不建账号，避免空口令超级管理员
            return;
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO admins (username, password_hash, role, is_enabled, token_version, created_at)
             VALUES (?,?,?,?,0,?)'
        )->execute([$username, $hash, 'super', 1, $now]);
    }

    private static function ensureColumn(PDO $pdo, string $table, string $column, string $definition): void
    {
        $stmt = $pdo->query('PRAGMA table_info(' . $table . ')');
        foreach ($stmt as $row) {
            if (($row['name'] ?? '') === $column) {
                return;
            }
        }
        $pdo->exec('ALTER TABLE ' . $table . ' ADD COLUMN ' . $column . ' ' . $definition);
    }
}
