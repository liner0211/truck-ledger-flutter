<?php
declare(strict_types=1);

final class AttachmentService
{
    public static function safeFilename(string $name): ?string
    {
        $base = basename($name);
        if (!preg_match('/^[A-Za-z0-9._-]+\.jpg$/', $base)) {
            return null;
        }
        return $base;
    }

    public static function userDir(array $cfg, int $userId): string
    {
        $dir = $cfg['attachments_dir'] . '/' . $userId;
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        return $dir;
    }

    public static function list(array $cfg, int $userId): array
    {
        $dir = self::userDir($cfg, $userId);
        $files = [];
        foreach (glob($dir . '/*.jpg') ?: [] as $path) {
            if (is_file($path)) {
                $files[] = basename($path);
            }
        }
        sort($files);
        return ['files' => $files];
    }

    public static function upload(array $cfg, int $userId, string $filename): array
    {
        $safe = self::safeFilename($filename);
        if ($safe === null) {
            JsonResponse::error('非法附件文件名', 400);
        }
        if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
            JsonResponse::error('缺少上传文件', 400);
        }
        $size = (int)($_FILES['file']['size'] ?? 0);
        if ($size <= 0) {
            JsonResponse::error('空文件', 400);
        }
        $max = (int)($cfg['max_upload_bytes'] ?? 20971520);
        if ($size > $max) {
            JsonResponse::error('附件过大（上限 20MB）', 400);
        }
        $dest = self::userDir($cfg, $userId) . '/' . $safe;
        if (!move_uploaded_file($_FILES['file']['tmp_name'], $dest)) {
            JsonResponse::error('保存失败', 500);
        }
        return ['filename' => $safe];
    }

    public static function download(array $cfg, int $userId, string $filename): void
    {
        $safe = self::safeFilename($filename);
        if ($safe === null) {
            JsonResponse::error('非法附件文件名', 400);
        }
        $path = self::userDir($cfg, $userId) . '/' . $safe;
        if (!is_file($path)) {
            JsonResponse::error('附件不存在', 404);
        }
        header('Content-Type: image/jpeg');
        header('Content-Length: ' . (string)filesize($path));
        readfile($path);
        exit;
    }
}
