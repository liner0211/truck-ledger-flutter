<?php
declare(strict_types=1);

/** 简单文件限流（按 IP+动作），无需 Redis。 */
final class RateLimitService
{
    public static function assert(array $cfg, string $action, int $maxAttempts = 20, int $windowSec = 600): void
    {
        $dir = ($cfg['data_dir'] ?? sys_get_temp_dir()) . '/rate_limit';
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }
        $ip = (string)($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $key = preg_replace('/[^A-Za-z0-9._-]/', '_', $action . '_' . $ip) ?: 'x';
        $file = $dir . '/' . $key . '.json';
        $now = time();
        $data = ['window_start' => $now, 'count' => 0];
        if (is_file($file)) {
            $raw = @file_get_contents($file);
            $decoded = $raw ? json_decode($raw, true) : null;
            if (is_array($decoded)) {
                $data = $decoded;
            }
        }
        $start = (int)($data['window_start'] ?? $now);
        $count = (int)($data['count'] ?? 0);
        if ($now - $start > $windowSec) {
            $start = $now;
            $count = 0;
        }
        $count++;
        @file_put_contents($file, json_encode(['window_start' => $start, 'count' => $count]));
        if ($count > $maxAttempts) {
            JsonResponse::error('请求过于频繁，请稍后再试', 429);
        }
    }
}
