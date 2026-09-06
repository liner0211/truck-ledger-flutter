<?php
declare(strict_types=1);

final class Config
{
    private static ?array $cfg = null;

    public static function load(string $root): array
    {
        if (self::$cfg !== null) {
            return self::$cfg;
        }
        $file = $root . '/config.php';
        if (!is_file($file)) {
            $file = $root . '/config.example.php';
        }
        self::$cfg = require $file;
        self::$cfg['root'] = $root;
        self::$cfg['data_dir'] = $root . '/data';
        self::$cfg['db_path'] = $root . '/data/truck_ledger.db';
        self::$cfg['attachments_dir'] = $root . '/data/attachments';
        self::$cfg['message_attachments_dir'] = $root . '/data/message_attachments';
        return self::$cfg;
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        return self::$cfg[$key] ?? $default;
    }
}
