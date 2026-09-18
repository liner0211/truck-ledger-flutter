<?php
declare(strict_types=1);

/** 账号权益：试用 / 到期 / 只读 / 配额。 */
final class EntitlementService
{
    public static function normalizeStatus(array $user): string
    {
        $now = (int)(microtime(true) * 1000);
        if ((int)($user['is_enabled'] ?? 1) !== 1) {
            return 'SUSPENDED';
        }
        $status = strtoupper((string)($user['status'] ?? 'ACTIVE'));
        if ($status === '') {
            $status = 'ACTIVE';
        }
        $expires = $user['expires_at'] ?? null;
        if ($expires !== null && $expires !== '' && (int)$expires > 0 && (int)$expires <= $now) {
            if ($status === 'ACTIVE' || $status === 'TRIAL') {
                return 'EXPIRED';
            }
        }
        if ($status === 'TRIAL') {
            return 'ACTIVE'; // 试用期内对外仍为可用，plan 区分
        }
        return $status;
    }

    public static function plan(array $user): string
    {
        $p = strtolower((string)($user['plan'] ?? 'trial'));
        return in_array($p, ['trial', 'paid'], true) ? $p : 'trial';
    }

    public static function isWriteAllowed(PDO $pdo, array $user): bool
    {
        $status = self::normalizeStatus($user);
        if (in_array($status, ['SUSPENDED', 'REVOKED', 'EXPIRED'], true)) {
            if ($status === 'EXPIRED' && SettingsService::expiryPolicy($pdo) === 'readonly') {
                return false;
            }
            return false;
        }
        return true;
    }

    public static function assertLoginAllowed(PDO $pdo, array $user): void
    {
        $status = self::normalizeStatus($user);
        if ($status === 'REVOKED') {
            JsonResponse::error('账号已被吊销，请联系管理员', 403);
        }
        if ($status === 'SUSPENDED') {
            JsonResponse::error('账号已被禁止使用，请联系管理员', 403);
        }
        if ($status === 'EXPIRED' && SettingsService::expiryPolicy($pdo) === 'block') {
            JsonResponse::error('试用或订阅已到期，请联系管理员开通', 403);
        }
    }

    public static function assertWriteAllowed(PDO $pdo, array $user): void
    {
        if (!self::isWriteAllowed($pdo, $user)) {
            $status = self::normalizeStatus($user);
            if ($status === 'EXPIRED') {
                JsonResponse::error('账号已到期，当前为只读模式', 403);
            }
            JsonResponse::error('当前账号无权写入数据', 403);
        }
    }

    public static function publicProfile(PDO $pdo, array $user): array
    {
        $status = self::normalizeStatus($user);
        $plan = self::plan($user);
        $expires = !empty($user['expires_at']) ? (int)$user['expires_at'] : null;
        $write = self::isWriteAllowed($pdo, $user);
        $daysLeft = null;
        if ($expires !== null && $expires > 0) {
            $daysLeft = (int)ceil(($expires - (int)(microtime(true) * 1000)) / 86400000);
        }
        return [
            'user_id' => (int)$user['id'],
            'username' => $user['username'],
            'license_plate' => (string)($user['license_plate'] ?? ''),
            'is_enabled' => (int)($user['is_enabled'] ?? 1) === 1,
            'status' => $status,
            'plan' => $plan,
            'expires_at' => $expires,
            'days_left' => $daysLeft,
            'write_allowed' => $write,
            'expiry_policy' => SettingsService::expiryPolicy($pdo),
            'announcement' => SettingsService::announcement($pdo),
            'limits' => [
                'max_rounds' => $plan === 'trial' ? SettingsService::trialMaxRounds($pdo) : 0,
                'max_attachments' => $plan === 'trial' ? SettingsService::trialMaxAttachments($pdo) : 0,
            ],
        ];
    }

    public static function assertQuotaForRounds(PDO $pdo, array $user, int $roundCount): void
    {
        if (self::plan($user) !== 'trial') {
            return;
        }
        $max = SettingsService::trialMaxRounds($pdo);
        if ($max > 0 && $roundCount > $max) {
            JsonResponse::error("试用版最多 {$max} 个圈次，请联系管理员升级", 403);
        }
    }

    public static function assertQuotaForAttachments(PDO $pdo, array $cfg, array $user): void
    {
        if (self::plan($user) !== 'trial') {
            return;
        }
        $max = SettingsService::trialMaxAttachments($pdo);
        if ($max <= 0) {
            return;
        }
        // 优先按账本引用计数；无账本时回退目录文件数
        $ledger = LedgerService::get($pdo, (int)$user['id']);
        $rounds = is_array($ledger['rounds'] ?? null) ? $ledger['rounds'] : [];
        $refs = AttachmentService::collectReferencedNames($rounds);
        $count = count($refs);
        if ($count === 0) {
            $count = AttachmentService::countFiles($cfg, (int)$user['id']);
        }
        if ($count >= $max) {
            JsonResponse::error("试用版附件上限 {$max} 张，请联系管理员升级", 403);
        }
    }
}
