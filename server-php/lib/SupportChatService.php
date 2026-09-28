<?php
declare(strict_types=1);

/**
 * 客服会话：用户 ↔ 指定/任意管理员（双向）。
 * 配置 support_admin_id：>0 时默认指派该管理员；0 表示任意有 messages.manage 的管理员可回复。
 */
final class SupportChatService
{
    public static function designatedAdminId(PDO $pdo): int
    {
        return max(0, (int)SettingsService::get($pdo, 'support_admin_id', '0'));
    }

    public static function getOrCreateThread(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare('SELECT * FROM support_threads WHERE user_id=?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if ($row) {
            return self::publicThread($pdo, $row);
        }
        $now = (int)(microtime(true) * 1000);
        $adminId = self::designatedAdminId($pdo);
        $adminId = $adminId > 0 ? $adminId : null;
        $pdo->prepare(
            'INSERT INTO support_threads (user_id, admin_id, created_at, updated_at) VALUES (?,?,?,?)'
        )->execute([$userId, $adminId, $now, $now]);
        $id = (int)$pdo->lastInsertId();
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            JsonResponse::error('创建会话失败', 500);
        }
        return self::publicThread($pdo, $row);
    }

    /** @param array<string,mixed> $row */
    private static function publicThread(PDO $pdo, array $row): array
    {
        $threadId = (int)$row['id'];
        $userId = (int)$row['user_id'];
        $uStmt = $pdo->prepare('SELECT username FROM users WHERE id=?');
        $uStmt->execute([$userId]);
        $uname = (string)($uStmt->fetchColumn() ?: '');
        $c = $pdo->prepare(
            'SELECT COUNT(*) FROM support_messages
             WHERE thread_id=? AND sender_role=\'user\' AND read_by_peer_at IS NULL'
        );
        $c->execute([$threadId]);
        $unreadAdmin = (int)$c->fetchColumn();
        $c2 = $pdo->prepare(
            'SELECT COUNT(*) FROM support_messages
             WHERE thread_id=? AND sender_role=\'admin\' AND read_by_peer_at IS NULL'
        );
        $c2->execute([$threadId]);
        $unreadUser = (int)$c2->fetchColumn();
        return [
            'id' => $threadId,
            'user_id' => $userId,
            'username' => $uname,
            'admin_id' => $row['admin_id'] !== null ? (int)$row['admin_id'] : null,
            'created_at' => (int)$row['created_at'],
            'updated_at' => (int)$row['updated_at'],
            'unread_for_admin' => $unreadAdmin,
            'unread_for_user' => $unreadUser,
        ];
    }

    /** @return list<array<string,mixed>> */
    public static function listMessages(PDO $pdo, int $threadId, int $limit = 200): array
    {
        $limit = max(1, min(500, $limit));
        $stmt = $pdo->prepare(
            "SELECT * FROM support_messages WHERE thread_id=? ORDER BY created_at ASC LIMIT {$limit}"
        );
        $stmt->execute([$threadId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = self::publicMessage($row);
        }
        return $out;
    }

    /** @param array<string,mixed> $row */
    private static function publicMessage(array $row): array
    {
        return [
            'id' => (int)$row['id'],
            'thread_id' => (int)$row['thread_id'],
            'sender_role' => (string)$row['sender_role'],
            'sender_user_id' => $row['sender_user_id'] !== null ? (int)$row['sender_user_id'] : null,
            'sender_admin_id' => $row['sender_admin_id'] !== null ? (int)$row['sender_admin_id'] : null,
            'body' => (string)$row['body'],
            'created_at' => (int)$row['created_at'],
            'read_by_peer_at' => $row['read_by_peer_at'] !== null ? (int)$row['read_by_peer_at'] : null,
        ];
    }

    public static function postMessage(
        PDO $pdo,
        int $threadId,
        string $role,
        string $body,
        ?int $userId = null,
        ?int $adminId = null
    ): array {
        $body = trim($body);
        if ($body === '' || mb_strlen($body) > 4000) {
            JsonResponse::error('消息内容无效（1–4000 字）', 400);
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO support_messages (thread_id, sender_role, sender_user_id, sender_admin_id, body, created_at)
             VALUES (?,?,?,?,?,?)'
        )->execute([$threadId, $role, $userId, $adminId, $body, $now]);
        $pdo->prepare('UPDATE support_threads SET updated_at=?, admin_id=COALESCE(admin_id, ?) WHERE id=?')
            ->execute([$now, $adminId, $threadId]);
        $id = (int)$pdo->lastInsertId();
        $stmt = $pdo->prepare('SELECT * FROM support_messages WHERE id=?');
        $stmt->execute([$id]);
        return self::publicMessage($stmt->fetch());
    }

    public static function markPeerRead(PDO $pdo, int $threadId, string $readerRole): void
    {
        // 用户读 → 标记 admin 消息；管理员读 → 标记 user 消息
        $peerRole = $readerRole === 'user' ? 'admin' : 'user';
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'UPDATE support_messages SET read_by_peer_at=?
             WHERE thread_id=? AND sender_role=? AND read_by_peer_at IS NULL'
        )->execute([$now, $threadId, $peerRole]);
    }

    /** @return list<array<string,mixed>> */
    public static function listThreadsForAdmin(PDO $pdo, int $limit = 100): array
    {
        $limit = max(1, min(200, $limit));
        $stmt = $pdo->query(
            "SELECT * FROM support_threads ORDER BY updated_at DESC LIMIT {$limit}"
        );
        $out = [];
        foreach ($stmt as $row) {
            $out[] = self::publicThread($pdo, $row);
        }
        return $out;
    }

    public static function getThread(PDO $pdo, int $threadId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM support_threads WHERE id=?');
        $stmt->execute([$threadId]);
        $row = $stmt->fetch();
        return $row ? self::publicThread($pdo, $row) : null;
    }

    public static function getThreadForUser(PDO $pdo, int $userId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM support_threads WHERE user_id=?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        return $row ? self::publicThread($pdo, $row) : null;
    }

    public static function forceDeleteThread(PDO $pdo, int $threadId): bool
    {
        $t = self::getThread($pdo, $threadId);
        if ($t === null) {
            return false;
        }
        $pdo->prepare('DELETE FROM support_threads WHERE id=?')->execute([$threadId]);
        return true;
    }

    public static function forceDeleteMessage(PDO $pdo, int $messageId): bool
    {
        $stmt = $pdo->prepare('SELECT id FROM support_messages WHERE id=?');
        $stmt->execute([$messageId]);
        if (!$stmt->fetch()) {
            return false;
        }
        $pdo->prepare('DELETE FROM support_messages WHERE id=?')->execute([$messageId]);
        return true;
    }

    public static function unreadForUser(PDO $pdo, int $userId): int
    {
        $t = self::getThreadForUser($pdo, $userId);
        if ($t === null) {
            return 0;
        }
        return (int)$t['unread_for_user'];
    }
}
