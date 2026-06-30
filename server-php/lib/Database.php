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
        self::migrate(self::$pdo);
        return self::$pdo;
    }

    private static function migrate(PDO $pdo): void
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
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS ledgers (
                user_id INTEGER PRIMARY KEY,
                data_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )'
        );
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
