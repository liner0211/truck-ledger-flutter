<?php
declare(strict_types=1);

final class LedgerService
{
    public static function get(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare('SELECT data_json, updated_at FROM ledgers WHERE user_id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['rounds' => [], 'updated_at' => 0];
        }
        $data = json_decode($row['data_json'], true);
        $rounds = (is_array($data) && isset($data['rounds']) && is_array($data['rounds']))
            ? $data['rounds']
            : [];
        return ['rounds' => $rounds, 'updated_at' => (int)$row['updated_at']];
    }

    public static function put(PDO $pdo, int $userId, array $body): array
    {
        $rounds = $body['rounds'] ?? [];
        if (!is_array($rounds)) {
            JsonResponse::error('rounds 须为数组', 400);
        }
        $updatedAt = (int)(microtime(true) * 1000);
        $json = json_encode(['rounds' => $rounds], JSON_UNESCAPED_UNICODE);
        $pdo->prepare(
            'INSERT INTO ledgers (user_id, data_json, updated_at) VALUES (?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET data_json = excluded.data_json, updated_at = excluded.updated_at'
        )->execute([$userId, $json, $updatedAt]);
        return ['updated_at' => $updatedAt];
    }
}
