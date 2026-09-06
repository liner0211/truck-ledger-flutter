<?php
declare(strict_types=1);

final class MessageService
{
    public static function create(
        PDO $pdo,
        ?int $userId,
        string $title,
        string $body,
        string $type = 'ops.broadcast',
        ?int $expiresAt = null,
        ?array $meta = null
    ): int {
        $now = (int)(microtime(true) * 1000);
        $metaJson = $meta === null || $meta === []
            ? null
            : (json_encode($meta, JSON_UNESCAPED_UNICODE) ?: null);
        $pdo->prepare(
            'INSERT INTO messages (user_id, title, body, type, created_at, expires_at, meta_json) VALUES (?,?,?,?,?,?,?)'
        )->execute([$userId, $title, $body, $type, $now, $expiresAt, $metaJson]);
        return (int)$pdo->lastInsertId();
    }

    public static function listForUser(PDO $pdo, int $userId, int $limit = 50): array
    {
        $now = (int)(microtime(true) * 1000);
        $limit = max(1, min(100, $limit));
        $stmt = $pdo->prepare(
            "SELECT m.id, m.title, m.body, m.type, m.created_at, m.expires_at, m.meta_json,
                    (SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user_id=?) AS is_read
             FROM messages m
             WHERE (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)
             ORDER BY m.created_at DESC
             LIMIT {$limit}"
        );
        $stmt->execute([$userId, $userId, $now]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = self::publicRow($row);
        }
        return $out;
    }

    /** @param array<string,mixed> $row */
    private static function publicRow(array $row): array
    {
        $meta = null;
        $raw = $row['meta_json'] ?? null;
        if (is_string($raw) && $raw !== '') {
            $decoded = json_decode($raw, true);
            if (is_array($decoded)) {
                $meta = $decoded;
            }
        }
        return [
            'id' => (int)$row['id'],
            'title' => $row['title'],
            'body' => $row['body'],
            'type' => $row['type'],
            'created_at' => (int)$row['created_at'],
            'is_read' => !empty($row['is_read']),
            'meta' => $meta,
        ];
    }

    public static function findForUser(PDO $pdo, int $userId, int $messageId): ?array
    {
        $now = (int)(microtime(true) * 1000);
        $stmt = $pdo->prepare(
            'SELECT m.*, (SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user_id=?) AS is_read
             FROM messages m
             WHERE m.id=?
               AND (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)'
        );
        $stmt->execute([$userId, $messageId, $userId, $now]);
        $row = $stmt->fetch();
        return $row ? self::publicRow($row) : null;
    }

    public static function unreadCount(PDO $pdo, int $userId): int
    {
        $now = (int)(microtime(true) * 1000);
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM messages m
             WHERE (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)
               AND NOT EXISTS (
                 SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user_id=?
               )'
        );
        $stmt->execute([$userId, $now, $userId]);
        return (int)$stmt->fetchColumn();
    }

    public static function markRead(PDO $pdo, int $userId, int $messageId): void
    {
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT OR IGNORE INTO message_reads (message_id, user_id, read_at) VALUES (?,?,?)'
        )->execute([$messageId, $userId, $now]);
    }

    public static function markAllRead(PDO $pdo, int $userId): void
    {
        $msgs = self::listForUser($pdo, $userId, 100);
        foreach ($msgs as $m) {
            if (!$m['is_read']) {
                self::markRead($pdo, $userId, (int)$m['id']);
            }
        }
    }

    public static function messageAttachmentsDir(array $cfg, int $messageId): string
    {
        $dir = ($cfg['message_attachments_dir'] ?? ($cfg['data_dir'] . '/message_attachments')) . '/' . $messageId;
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        return $dir;
    }

    public static function safeFilename(string $name): ?string
    {
        $base = basename($name);
        if (!preg_match('/^[A-Za-z0-9._-]+\.jpg$/', $base)) {
            return null;
        }
        return $base;
    }

    /** @return list<string> */
    public static function saveUploadedImages(array $cfg, int $messageId): array
    {
        $saved = [];
        $files = $_FILES['images'] ?? $_FILES['file'] ?? null;
        if ($files === null) {
            return $saved;
        }
        // Normalize single vs multi
        $names = [];
        $tmps = [];
        $errs = [];
        if (is_array($files['name'] ?? null)) {
            $names = $files['name'];
            $tmps = $files['tmp_name'];
            $errs = $files['error'];
        } else {
            $names = [$files['name'] ?? ''];
            $tmps = [$files['tmp_name'] ?? ''];
            $errs = [$files['error'] ?? UPLOAD_ERR_NO_FILE];
        }
        $dir = self::messageAttachmentsDir($cfg, $messageId);
        $max = (int)($cfg['max_upload_bytes'] ?? 20971520);
        foreach ($names as $i => $orig) {
            if ((int)($errs[$i] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
                continue;
            }
            $tmp = (string)($tmps[$i] ?? '');
            if ($tmp === '' || !is_uploaded_file($tmp)) {
                continue;
            }
            $size = (int)filesize($tmp);
            if ($size <= 0 || $size > $max) {
                continue;
            }
            $destName = bin2hex(random_bytes(16)) . '.jpg';
            $dest = $dir . '/' . $destName;
            if (!move_uploaded_file($tmp, $dest)) {
                continue;
            }
            $saved[] = $destName;
        }
        return $saved;
    }

    public static function downloadAttachment(array $cfg, int $messageId, string $filename): void
    {
        $safe = self::safeFilename($filename);
        if ($safe === null) {
            JsonResponse::error('非法附件文件名', 400);
        }
        $path = self::messageAttachmentsDir($cfg, $messageId) . '/' . $safe;
        if (!is_file($path)) {
            JsonResponse::error('附件不存在', 404);
        }
        header('Content-Type: image/jpeg');
        header('Content-Length: ' . (string)filesize($path));
        readfile($path);
        exit;
    }
}
