<?php
declare(strict_types=1);

/** 全局应用设置（SQLite key-value）。 */
final class SettingsService
{
    public const KEY_REGISTRATION_ENABLED = 'registration_enabled';
    public const KEY_TRIAL_DAYS = 'trial_days';
    public const KEY_TRIAL_MAX_ROUNDS = 'trial_max_rounds';
    public const KEY_TRIAL_MAX_ATTACHMENTS = 'trial_max_attachments';
    public const KEY_EXPIRY_POLICY = 'expiry_policy';
    public const KEY_ANNOUNCEMENT = 'announcement';

    public static function ensureTable(PDO $pdo): void
    {
        // 表结构由 Database::migrate 保证
    }

    public static function get(PDO $pdo, string $key, string $default = ''): string
    {
        $stmt = $pdo->prepare('SELECT value FROM app_settings WHERE key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        return $row ? (string)$row['value'] : $default;
    }

    public static function set(PDO $pdo, string $key, string $value): void
    {
        $now = (int)(microtime(true) * 1000);
        $stmt = $pdo->prepare(
            'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at'
        );
        $stmt->execute([$key, $value, $now]);
    }

    public static function isRegistrationEnabled(PDO $pdo): bool
    {
        return self::get($pdo, self::KEY_REGISTRATION_ENABLED, '1') === '1';
    }

    public static function setRegistrationEnabled(PDO $pdo, bool $enabled): void
    {
        self::set($pdo, self::KEY_REGISTRATION_ENABLED, $enabled ? '1' : '0');
    }

    public static function trialDays(PDO $pdo): int
    {
        return max(0, (int)self::get($pdo, self::KEY_TRIAL_DAYS, '14'));
    }

    public static function trialMaxRounds(PDO $pdo): int
    {
        return max(0, (int)self::get($pdo, self::KEY_TRIAL_MAX_ROUNDS, '30'));
    }

    public static function trialMaxAttachments(PDO $pdo): int
    {
        return max(0, (int)self::get($pdo, self::KEY_TRIAL_MAX_ATTACHMENTS, '100'));
    }

    /** readonly | block */
    public static function expiryPolicy(PDO $pdo): string
    {
        $p = self::get($pdo, self::KEY_EXPIRY_POLICY, 'readonly');
        return $p === 'block' ? 'block' : 'readonly';
    }

    public static function announcement(PDO $pdo): string
    {
        return self::get($pdo, self::KEY_ANNOUNCEMENT, '');
    }

    /** @return array<string,mixed> */
    public static function featureFlags(PDO $pdo): array
    {
        $raw = self::get($pdo, 'feature_flags', '');
        if ($raw === '') {
            return [
                'excel_export' => true,
                'backup_import' => true,
                'messages' => true,
                'web_ledger' => true,
            ];
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return [
                'excel_export' => true,
                'backup_import' => true,
                'messages' => true,
                'web_ledger' => true,
            ];
        }
        return $decoded;
    }

    public static function setFeatureFlags(PDO $pdo, array $flags): void
    {
        self::set($pdo, 'feature_flags', json_encode($flags, JSON_UNESCAPED_UNICODE) ?: '{}');
    }
}
