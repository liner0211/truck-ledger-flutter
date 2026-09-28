<?php
declare(strict_types=1);

/**
 * 用户私聊 (dm) + 群聊 (group)。
 * msg_type 本期仅 text；预留 image / audio / call_invite。
 */
final class ChatService
{
    public static function dmKey(int $a, int $b): string
    {
        $x = min($a, $b);
        $y = max($a, $b);
        return "dm:{$x}:{$y}";
    }

    /** @return list<array{id:int,username:string,license_plate:string}> */
    public static function listPeers(PDO $pdo, int $selfId): array
    {
        $stmt = $pdo->prepare(
            'SELECT id, username, license_plate FROM users
             WHERE id != ? AND is_enabled = 1
             ORDER BY username COLLATE NOCASE LIMIT 500'
        );
        $stmt->execute([$selfId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'id' => (int)$row['id'],
                'username' => (string)$row['username'],
                'license_plate' => (string)($row['license_plate'] ?? ''),
            ];
        }
        return $out;
    }

    public static function getOrCreateDm(PDO $pdo, int $selfId, int $peerId): ?array
    {
        if ($peerId <= 0 || $peerId === $selfId) {
            return null;
        }
        $peer = $pdo->prepare('SELECT id FROM users WHERE id=? AND is_enabled=1');
        $peer->execute([$peerId]);
        if (!$peer->fetch()) {
            return null;
        }
        $key = self::dmKey($selfId, $peerId);
        $stmt = $pdo->prepare('SELECT * FROM chat_conversations WHERE dm_key=?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        if ($row) {
            return self::publicConversation($pdo, $row, $selfId);
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO chat_conversations (type, title, dm_key, created_by, created_at, updated_at)
             VALUES (?,?,?,?,?,?)'
        )->execute(['dm', null, $key, $selfId, $now, $now]);
        $cid = (int)$pdo->lastInsertId();
        $ins = $pdo->prepare(
            'INSERT INTO chat_members (conversation_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,?)'
        );
        $ins->execute([$cid, $selfId, 'member', $now, $now]);
        $ins->execute([$cid, $peerId, 'member', $now, 0]);
        return self::getConversationForUser($pdo, $cid, $selfId);
    }

    /** @param list<int> $memberIds */
    public static function createGroup(PDO $pdo, int $selfId, string $title, array $memberIds): ?array
    {
        $title = trim($title);
        if ($title === '' || mb_strlen($title) > 64) {
            return null;
        }
        $ids = [];
        foreach ($memberIds as $id) {
            $id = (int)$id;
            if ($id > 0 && $id !== $selfId) {
                $ids[$id] = true;
            }
        }
        $memberList = array_keys($ids);
        if ($memberList === []) {
            return null;
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO chat_conversations (type, title, dm_key, created_by, created_at, updated_at)
             VALUES (?,?,NULL,?,?,?)'
        )->execute(['group', $title, $selfId, $now, $now]);
        $cid = (int)$pdo->lastInsertId();
        $ins = $pdo->prepare(
            'INSERT INTO chat_members (conversation_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,?)'
        );
        $ins->execute([$cid, $selfId, 'owner', $now, $now]);
        foreach ($memberList as $uid) {
            $chk = $pdo->prepare('SELECT id FROM users WHERE id=? AND is_enabled=1');
            $chk->execute([$uid]);
            if ($chk->fetch()) {
                $ins->execute([$cid, $uid, 'member', $now, 0]);
            }
        }
        return self::getConversationForUser($pdo, $cid, $selfId);
    }

    public static function addMembers(PDO $pdo, int $cid, int $actorId, array $memberIds): bool
    {
        $conv = self::rawConversation($pdo, $cid);
        if ($conv === null || (string)$conv['type'] !== 'group') {
            return false;
        }
        $role = self::memberRole($pdo, $cid, $actorId);
        if ($role !== 'owner' && $role !== 'admin') {
            return false;
        }
        $now = (int)(microtime(true) * 1000);
        $ins = $pdo->prepare(
            'INSERT OR IGNORE INTO chat_members (conversation_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,?)'
        );
        foreach ($memberIds as $uid) {
            $uid = (int)$uid;
            if ($uid <= 0) {
                continue;
            }
            $chk = $pdo->prepare('SELECT id FROM users WHERE id=? AND is_enabled=1');
            $chk->execute([$uid]);
            if ($chk->fetch()) {
                $ins->execute([$cid, $uid, 'member', $now, 0]);
            }
        }
        $pdo->prepare('UPDATE chat_conversations SET updated_at=? WHERE id=?')->execute([$now, $cid]);
        return true;
    }

    public static function isMember(PDO $pdo, int $cid, int $userId): bool
    {
        return self::memberRole($pdo, $cid, $userId) !== null;
    }

    public static function memberRole(PDO $pdo, int $cid, int $userId): ?string
    {
        $stmt = $pdo->prepare('SELECT role FROM chat_members WHERE conversation_id=? AND user_id=?');
        $stmt->execute([$cid, $userId]);
        $r = $stmt->fetchColumn();
        return $r !== false ? (string)$r : null;
    }

    /** @return list<int> */
    public static function memberUserIds(PDO $pdo, int $cid): array
    {
        $stmt = $pdo->prepare('SELECT user_id FROM chat_members WHERE conversation_id=?');
        $stmt->execute([$cid]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = (int)$row['user_id'];
        }
        return $out;
    }

    public static function rawConversation(PDO $pdo, int $cid): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM chat_conversations WHERE id=?');
        $stmt->execute([$cid]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function getConversationForUser(PDO $pdo, int $cid, int $userId): ?array
    {
        if (!self::isMember($pdo, $cid, $userId)) {
            return null;
        }
        $row = self::rawConversation($pdo, $cid);
        return $row ? self::publicConversation($pdo, $row, $userId) : null;
    }

    /** @return list<array<string,mixed>> */
    public static function listForUser(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare(
            'SELECT c.* FROM chat_conversations c
             JOIN chat_members m ON m.conversation_id = c.id
             WHERE m.user_id = ?
             ORDER BY c.updated_at DESC LIMIT 200'
        );
        $stmt->execute([$userId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = self::publicConversation($pdo, $row, $userId);
        }
        return $out;
    }

    /** @return list<array<string,mixed>> */
    public static function listForAdmin(PDO $pdo, int $limit = 100): array
    {
        $limit = max(1, min(200, $limit));
        $stmt = $pdo->query(
            "SELECT * FROM chat_conversations ORDER BY updated_at DESC LIMIT {$limit}"
        );
        $out = [];
        foreach ($stmt as $row) {
            $out[] = self::publicConversation($pdo, $row, null);
        }
        return $out;
    }

    public static function publicConversation(PDO $pdo, array $row, ?int $viewerId): array
    {
        $cid = (int)$row['id'];
        $type = (string)$row['type'];
        $members = [];
        $mStmt = $pdo->prepare(
            'SELECT m.user_id, m.role, m.last_read_at, u.username, u.license_plate
             FROM chat_members m JOIN users u ON u.id = m.user_id
             WHERE m.conversation_id=?'
        );
        $mStmt->execute([$cid]);
        $peerName = '';
        $unread = 0;
        $myLastRead = 0;
        foreach ($mStmt as $m) {
            $uid = (int)$m['user_id'];
            $members[] = [
                'user_id' => $uid,
                'role' => (string)$m['role'],
                'username' => (string)$m['username'],
                'license_plate' => (string)($m['license_plate'] ?? ''),
            ];
            if ($viewerId !== null && $uid === $viewerId) {
                $myLastRead = (int)$m['last_read_at'];
            }
            if ($type === 'dm' && $viewerId !== null && $uid !== $viewerId) {
                $peerName = (string)$m['username'];
            }
        }
        if ($viewerId !== null) {
            $uStmt = $pdo->prepare(
                'SELECT COUNT(*) FROM chat_messages
                 WHERE conversation_id=? AND deleted_at IS NULL
                   AND created_at > ? AND sender_user_id != ?'
            );
            $uStmt->execute([$cid, $myLastRead, $viewerId]);
            $unread = (int)$uStmt->fetchColumn();
        }
        $last = $pdo->prepare(
            'SELECT body, created_at, sender_user_id, msg_type FROM chat_messages
             WHERE conversation_id=? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1'
        );
        $last->execute([$cid]);
        $lastRow = $last->fetch();
        $title = $type === 'group'
            ? (string)($row['title'] ?? '群聊')
            : ($peerName !== '' ? $peerName : '私聊');
        return [
            'id' => $cid,
            'type' => $type,
            'title' => $title,
            'created_by' => (int)$row['created_by'],
            'created_at' => (int)$row['created_at'],
            'updated_at' => (int)$row['updated_at'],
            'members' => $members,
            'unread' => $unread,
            'last_message' => $lastRow ? [
                'body' => (string)$lastRow['body'],
                'created_at' => (int)$lastRow['created_at'],
                'sender_user_id' => (int)$lastRow['sender_user_id'],
                'msg_type' => (string)$lastRow['msg_type'],
            ] : null,
        ];
    }

    /** @return list<array<string,mixed>> */
    public static function listMessages(PDO $pdo, int $cid, int $limit = 100, ?int $beforeId = null): array
    {
        $limit = max(1, min(200, $limit));
        if ($beforeId !== null && $beforeId > 0) {
            $stmt = $pdo->prepare(
                "SELECT m.*, u.username AS sender_username
                 FROM chat_messages m
                 LEFT JOIN users u ON u.id = m.sender_user_id
                 WHERE m.conversation_id=? AND m.deleted_at IS NULL AND m.id < ?
                 ORDER BY m.id DESC LIMIT {$limit}"
            );
            $stmt->execute([$cid, $beforeId]);
        } else {
            $stmt = $pdo->prepare(
                "SELECT m.*, u.username AS sender_username
                 FROM chat_messages m
                 LEFT JOIN users u ON u.id = m.sender_user_id
                 WHERE m.conversation_id=? AND m.deleted_at IS NULL
                 ORDER BY m.id DESC LIMIT {$limit}"
            );
            $stmt->execute([$cid]);
        }
        $rows = [];
        foreach ($stmt as $row) {
            $rows[] = self::publicMessage($row);
        }
        return array_reverse($rows);
    }

    public static function publicMessage(array $row): array
    {
        return [
            'id' => (int)$row['id'],
            'conversation_id' => (int)$row['conversation_id'],
            'sender_user_id' => (int)$row['sender_user_id'],
            'sender_username' => (string)($row['sender_username'] ?? ''),
            'body' => (string)$row['body'],
            'msg_type' => (string)($row['msg_type'] ?? 'text'),
            'created_at' => (int)$row['created_at'],
        ];
    }

    public static function postMessage(PDO $pdo, int $cid, int $senderId, string $body, string $msgType = 'text'): ?array
    {
        if (!self::isMember($pdo, $cid, $senderId)) {
            return null;
        }
        $body = trim($body);
        if ($body === '' || mb_strlen($body) > 4000) {
            return null;
        }
        $allowed = ['text', 'image', 'audio', 'call_invite'];
        if (!in_array($msgType, $allowed, true)) {
            $msgType = 'text';
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO chat_messages (conversation_id, sender_user_id, body, msg_type, created_at)
             VALUES (?,?,?,?,?)'
        )->execute([$cid, $senderId, $body, $msgType, $now]);
        $mid = (int)$pdo->lastInsertId();
        $pdo->prepare('UPDATE chat_conversations SET updated_at=? WHERE id=?')->execute([$now, $cid]);
        $pdo->prepare('UPDATE chat_members SET last_read_at=? WHERE conversation_id=? AND user_id=?')
            ->execute([$now, $cid, $senderId]);
        $stmt = $pdo->prepare('SELECT * FROM chat_messages WHERE id=?');
        $stmt->execute([$mid]);
        $row = $stmt->fetch();
        return $row ? self::publicMessage($row) : null;
    }

    public static function markRead(PDO $pdo, int $cid, int $userId): bool
    {
        if (!self::isMember($pdo, $cid, $userId)) {
            return false;
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare('UPDATE chat_members SET last_read_at=? WHERE conversation_id=? AND user_id=?')
            ->execute([$now, $cid, $userId]);
        return true;
    }

    /** @return array{dm:int,group:int,total:int} */
    public static function unreadCounts(PDO $pdo, int $userId): array
    {
        $dm = 0;
        $group = 0;
        foreach (self::listForUser($pdo, $userId) as $c) {
            $n = (int)($c['unread'] ?? 0);
            if (($c['type'] ?? '') === 'dm') {
                $dm += $n;
            } else {
                $group += $n;
            }
        }
        return ['dm' => $dm, 'group' => $group, 'total' => $dm + $group];
    }

    public static function forceDeleteMessage(PDO $pdo, int $messageId): bool
    {
        $stmt = $pdo->prepare('SELECT id, conversation_id FROM chat_messages WHERE id=? AND deleted_at IS NULL');
        $stmt->execute([$messageId]);
        $row = $stmt->fetch();
        if (!$row) {
            return false;
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare('UPDATE chat_messages SET deleted_at=? WHERE id=?')->execute([$now, $messageId]);
        return true;
    }

    public static function dissolve(PDO $pdo, int $cid): bool
    {
        $row = self::rawConversation($pdo, $cid);
        if ($row === null) {
            return false;
        }
        $pdo->prepare('DELETE FROM chat_conversations WHERE id=?')->execute([$cid]);
        return true;
    }
}
