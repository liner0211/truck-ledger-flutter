<?php
declare(strict_types=1);

final class LedgerService
{
    public static function get(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare('SELECT data_json, updated_at, revision FROM ledgers WHERE user_id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['rounds' => [], 'updated_at' => 0, 'revision' => 0];
        }
        $data = json_decode($row['data_json'], true);
        $rounds = (is_array($data) && isset($data['rounds']) && is_array($data['rounds']))
            ? $data['rounds']
            : [];
        return [
            'rounds' => $rounds,
            'updated_at' => (int)$row['updated_at'],
            'revision' => (int)($row['revision'] ?? 0),
        ];
    }

    public static function revision(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare('SELECT updated_at, revision FROM ledgers WHERE user_id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['updated_at' => 0, 'revision' => 0];
        }
        return [
            'updated_at' => (int)$row['updated_at'],
            'revision' => (int)($row['revision'] ?? 0),
        ];
    }

    /**
     * @param int|null $baseRevision 客户端基于的 revision；null 表示强制覆盖（管理员/显式 force）
     */
    public static function put(
        PDO $pdo,
        int $userId,
        array $body,
        ?int $baseRevision = null,
        bool $force = false,
        bool $snapshot = true
    ): array {
        $rounds = $body['rounds'] ?? [];
        if (!is_array($rounds)) {
            JsonResponse::error('rounds 须为数组', 400);
        }
        if (array_key_exists('base_revision', $body)) {
            $baseRevision = (int)$body['base_revision'];
        }
        if (!empty($body['force'])) {
            $force = true;
        }

        $current = self::get($pdo, $userId);
        $curRev = (int)$current['revision'];

        if (!$force && $baseRevision !== null && $baseRevision !== $curRev) {
            http_response_code(409);
            header('Content-Type: application/json; charset=utf-8');
            echo json_encode([
                'detail' => '账本版本冲突，请先拉取或解决冲突',
                'conflict' => true,
                'server' => $current,
            ], JSON_UNESCAPED_UNICODE);
            exit;
        }

        $updatedAt = (int)(microtime(true) * 1000);
        $newRev = $curRev + 1;
        $json = json_encode(['rounds' => $rounds], JSON_UNESCAPED_UNICODE);

        if ($snapshot && $curRev > 0 && !empty($current['rounds'])) {
            SnapshotService::save(
                $pdo,
                $userId,
                $curRev,
                json_encode(['rounds' => $current['rounds']], JSON_UNESCAPED_UNICODE) ?: '{"rounds":[]}',
                'auto-before-put'
            );
        }

        $pdo->prepare(
            'INSERT INTO ledgers (user_id, data_json, updated_at, revision) VALUES (?, ?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET
               data_json = excluded.data_json,
               updated_at = excluded.updated_at,
               revision = excluded.revision'
        )->execute([$userId, $json, $updatedAt, $newRev]);

        // 删除未被账本引用的附件，避免试用配额与磁盘膨胀
        try {
            $attDir = Config::get('attachments_dir');
            if (is_string($attDir) && $attDir !== '') {
                $refs = AttachmentService::collectReferencedNames($rounds);
                AttachmentService::gcOrphans(['attachments_dir' => $attDir], $userId, $refs);
            }
        } catch (Throwable $e) {
            // GC 失败不影响账本保存
        }

        return ['updated_at' => $updatedAt, 'revision' => $newRev];
    }
}
