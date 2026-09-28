<?php
declare(strict_types=1);

/**
 * 站内通知（inbox）：Admin → User（广播或指定用户）。
 * 用户可已读、回复；管理员可查已读回执并强制删除。
 * 客服双向聊天见 SupportChatService。
 */
final class MessageService
{
    public static function create(
        PDO $pdo,
        ?int $userId,
        string $title,
        string $body,
        string $type = 'ops.broadcast',
        ?int $expiresAt = null,
        ?array $meta = null,
        ?int $adminId = null
    ): int {
        $now = (int)(microtime(true) * 1000);
        $metaJson = $meta === null || $meta === []
            ? null
            : (json_encode($meta, JSON_UNESCAPED_UNICODE) ?: null);
        $pdo->prepare(
            'INSERT INTO messages (user_id, title, body, type, created_at, expires_at, meta_json, admin_id)
             VALUES (?,?,?,?,?,?,?,?)'
        )->execute([$userId, $title, $body, $type, $now, $expiresAt, $metaJson, $adminId]);
        return (int)$pdo->lastInsertId();
    }

    public static function listForUser(PDO $pdo, int $userId, int $limit = 50): array
    {
        $now = (int)(microtime(true) * 1000);
        $limit = max(1, min(100, $limit));
        $stmt = $pdo->prepare(
            "SELECT m.id, m.title, m.body, m.type, m.created_at, m.expires_at, m.meta_json,
                    (SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user_id=?) AS is_read,
                    (SELECT COUNT(*) FROM message_replies rp WHERE rp.message_id=m.id) AS reply_count
             FROM messages m
             WHERE (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)
               AND m.force_deleted_at IS NULL
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
    private static function publicRow(array $row, bool $withReplies = false, PDO $pdo = null): array
    {
        $meta = null;
        $raw = $row['meta_json'] ?? null;
        if (is_string($raw) && $raw !== '') {
            $decoded = json_decode($raw, true);
            if (is_array($decoded)) {
                $meta = $decoded;
            }
        }
        $item = [
            'id' => (int)$row['id'],
            'title' => $row['title'],
            'body' => $row['body'],
            'type' => $row['type'],
            'created_at' => (int)$row['created_at'],
            'is_read' => !empty($row['is_read']),
            'reply_count' => (int)($row['reply_count'] ?? 0),
            'meta' => $meta,
            'user_id' => isset($row['user_id']) && $row['user_id'] !== null ? (int)$row['user_id'] : null,
            'admin_id' => isset($row['admin_id']) && $row['admin_id'] !== null ? (int)$row['admin_id'] : null,
        ];
        if ($withReplies && $pdo !== null) {
            $item['replies'] = self::listReplies($pdo, (int)$row['id']);
        }
        return $item;
    }

    public static function findForUser(PDO $pdo, int $userId, int $messageId): ?array
    {
        $now = (int)(microtime(true) * 1000);
        $stmt = $pdo->prepare(
            'SELECT m.*, (SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user_id=?) AS is_read,
                    (SELECT COUNT(*) FROM message_replies rp WHERE rp.message_id=m.id) AS reply_count
             FROM messages m
             WHERE m.id=?
               AND (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)
               AND m.force_deleted_at IS NULL'
        );
        $stmt->execute([$userId, $messageId, $userId, $now]);
        $row = $stmt->fetch();
        return $row ? self::publicRow($row, true, $pdo) : null;
    }

    public static function unreadCount(PDO $pdo, int $userId): int
    {
        $now = (int)(microtime(true) * 1000);
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM messages m
             WHERE (m.user_id IS NULL OR m.user_id=?)
               AND (m.expires_at IS NULL OR m.expires_at > ?)
               AND m.force_deleted_at IS NULL
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

    /** @return list<array<string,mixed>> */
    public static function listReplies(PDO $pdo, int $messageId): array
    {
        $stmt = $pdo->prepare(
            'SELECT id, message_id, sender_role, sender_user_id, sender_admin_id, body, created_at
             FROM message_replies WHERE message_id=? ORDER BY created_at ASC'
        );
        $stmt->execute([$messageId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'id' => (int)$row['id'],
                'message_id' => (int)$row['message_id'],
                'sender_role' => (string)$row['sender_role'],
                'sender_user_id' => $row['sender_user_id'] !== null ? (int)$row['sender_user_id'] : null,
                'sender_admin_id' => $row['sender_admin_id'] !== null ? (int)$row['sender_admin_id'] : null,
                'body' => (string)$row['body'],
                'created_at' => (int)$row['created_at'],
            ];
        }
        return $out;
    }

    public static function addReply(
        PDO $pdo,
        int $messageId,
        string $role,
        string $body,
        ?int $userId = null,
        ?int $adminId = null
    ): array {
        $body = trim($body);
        if ($body === '' || mb_strlen($body) > 4000) {
            JsonResponse::error('回复内容无效（1–4000 字）', 400);
        }
        if ($role !== 'user' && $role !== 'admin') {
            JsonResponse::error('非法发送方', 400);
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO message_replies (message_id, sender_role, sender_user_id, sender_admin_id, body, created_at)
             VALUES (?,?,?,?,?,?)'
        )->execute([$messageId, $role, $userId, $adminId, $body, $now]);
        $id = (int)$pdo->lastInsertId();
        return [
            'id' => $id,
            'message_id' => $messageId,
            'sender_role' => $role,
            'sender_user_id' => $userId,
            'sender_admin_id' => $adminId,
            'body' => $body,
            'created_at' => $now,
        ];
    }

    public static function userCanAccess(PDO $pdo, int $userId, int $messageId): bool
    {
        return self::findForUser($pdo, $userId, $messageId) !== null;
    }

    /** 管理端列表（不含已强制删除）。 */
    public static function listForAdmin(PDO $pdo, int $limit = 100, ?int $userIdFilter = null): array
    {
        $limit = max(1, min(200, $limit));
        $sql = 'SELECT m.*,
                       (SELECT COUNT(*) FROM message_reads r WHERE r.message_id=m.id) AS read_count,
                       (SELECT COUNT(*) FROM message_replies rp WHERE rp.message_id=m.id) AS reply_count,
                       u.username AS target_username
                FROM messages m
                LEFT JOIN users u ON u.id = m.user_id
                WHERE m.force_deleted_at IS NULL';
        $args = [];
        if ($userIdFilter !== null && $userIdFilter > 0) {
            $sql .= ' AND m.user_id = ?';
            $args[] = $userIdFilter;
        }
        $sql .= " ORDER BY m.created_at DESC LIMIT {$limit}";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($args);
        $userTotal = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
        $out = [];
        foreach ($stmt as $row) {
            $targetUid = $row['user_id'] !== null ? (int)$row['user_id'] : null;
            $audience = $targetUid === null ? $userTotal : 1;
            $item = self::publicRow($row);
            $item['read_count'] = (int)$row['read_count'];
            $item['audience'] = $audience;
            $item['target_username'] = $row['target_username'] ?? null;
            $item['is_broadcast'] = $targetUid === null;
            $out[] = $item;
        }
        return $out;
    }

    /** @return list<array{user_id:int,username:string,read_at:int}> */
    public static function readReceipts(PDO $pdo, int $messageId): array
    {
        $stmt = $pdo->prepare(
            'SELECT r.user_id, r.read_at, u.username
             FROM message_reads r
             JOIN users u ON u.id = r.user_id
             WHERE r.message_id=?
             ORDER BY r.read_at DESC'
        );
        $stmt->execute([$messageId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'user_id' => (int)$row['user_id'],
                'username' => (string)$row['username'],
                'read_at' => (int)$row['read_at'],
            ];
        }
        return $out;
    }

    public static function findRaw(PDO $pdo, int $messageId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM messages WHERE id=? AND force_deleted_at IS NULL');
        $stmt->execute([$messageId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /** 强制删除：用户端立即不可见；物理删除 + 附件清理。 */
    public static function forceDelete(PDO $pdo, array $cfg, int $messageId): bool
    {
        $row = self::findRaw($pdo, $messageId);
        if ($row === null) {
            return false;
        }
        $dir = self::messageAttachmentsDir($cfg, $messageId);
        $pdo->prepare('DELETE FROM messages WHERE id=?')->execute([$messageId]);
        if (is_dir($dir)) {
            foreach (glob($dir . '/*') ?: [] as $f) {
                @unlink($f);
            }
            @rmdir($dir);
        }
        return true;
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
