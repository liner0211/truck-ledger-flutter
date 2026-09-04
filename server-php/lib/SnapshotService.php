<?php
declare(strict_types=1);

final class SnapshotService
{
    private const KEEP = 10;

    public static function save(PDO $pdo, int $userId, int $revision, string $dataJson, string $note = ''): void
    {
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO ledger_snapshots (user_id, revision, data_json, created_at, note) VALUES (?,?,?,?,?)'
        )->execute([$userId, $revision, $dataJson, $now, $note]);

        $ids = $pdo->prepare(
            'SELECT id FROM ledger_snapshots WHERE user_id = ? ORDER BY created_at DESC'
        );
        $ids->execute([$userId]);
        $all = $ids->fetchAll();
        if (count($all) > self::KEEP) {
            $drop = array_slice($all, self::KEEP);
            $del = $pdo->prepare('DELETE FROM ledger_snapshots WHERE id = ?');
            foreach ($drop as $row) {
                $del->execute([(int)$row['id']]);
            }
        }
    }

    public static function list(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare(
            'SELECT id, revision, created_at, note FROM ledger_snapshots WHERE user_id = ? ORDER BY created_at DESC LIMIT 20'
        );
        $stmt->execute([$userId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'id' => (int)$row['id'],
                'revision' => (int)$row['revision'],
                'created_at' => (int)$row['created_at'],
                'note' => (string)$row['note'],
            ];
        }
        return $out;
    }

    public static function restore(PDO $pdo, int $userId, int $snapshotId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM ledger_snapshots WHERE id = ? AND user_id = ?');
        $stmt->execute([$snapshotId, $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $data = json_decode($row['data_json'], true);
        $rounds = (is_array($data) && isset($data['rounds'])) ? $data['rounds'] : [];
        return LedgerService::put($pdo, $userId, ['rounds' => $rounds], null, true, true);
    }
}
