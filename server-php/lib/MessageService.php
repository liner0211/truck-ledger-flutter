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
        ?int $expiresAt = null
    ): int {
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO messages (user_id, title, body, type, created_at, expires_at) VALUES (?,?,?,?,?,?)'
        )->execute([$userId, $title, $body, $type, $now, $expiresAt]);
        return (int)$pdo->lastInsertId();
    }

    public static function listForUser(PDO $pdo, int $userId, int $limit = 50): array
    {
        $now = (int)(microtime(true) * 1000);
        $limit = max(1, min(100, $limit));
        $stmt = $pdo->prepare(
            "SELECT m.id, m.title, m.body, m.type, m.created_at, m.expires_at,
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
            $out[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'body' => $row['body'],
                'type' => $row['type'],
                'created_at' => (int)$row['created_at'],
                'is_read' => !empty($row['is_read']),
            ];
        }
        return $out;
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
}
