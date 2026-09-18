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

    /** @return list<string> */
    public static function collectReferencedNames(array $rounds): array
    {
        $names = [];
        $walk = function ($node) use (&$walk, &$names): void {
            if (!is_array($node)) {
                return;
            }
            if (isset($node['attachments']) && is_array($node['attachments'])) {
                foreach ($node['attachments'] as $a) {
                    if (is_string($a) && $a !== '') {
                        $names[$a] = true;
                    }
                }
            }
            foreach ($node as $v) {
                if (is_array($v)) {
                    $walk($v);
                }
            }
        };
        $walk($rounds);
        return array_keys($names);
    }

    /**
     * 删除目录中未被账本引用的 jpg，返回删除数量。
     *
     * @param list<string> $referenced
     */
    public static function gcOrphans(array $cfg, int $userId, array $referenced): int
    {
        $dir = self::userDir($cfg, $userId);
        $keep = array_fill_keys($referenced, true);
        $deleted = 0;
        foreach (glob($dir . '/*.jpg') ?: [] as $path) {
            if (!is_file($path)) {
                continue;
            }
            $base = basename($path);
            if (isset($keep[$base])) {
                continue;
            }
            if (@unlink($path)) {
                $deleted++;
            }
        }
        return $deleted;
    }

    public static function countFiles(array $cfg, int $userId): int
    {
        $dir = self::userDir($cfg, $userId);
        return count(glob($dir . '/*.jpg') ?: []);
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
        $tmp = $_FILES['file']['tmp_name'];
        $dest = self::userDir($cfg, $userId) . '/' . $safe;
        if (!move_uploaded_file($tmp, $dest)) {
            JsonResponse::error('保存失败', 500);
        }
        self::recompressIfNeeded($dest);
        return ['filename' => $safe];
    }

    /** 边长过大或体积过大时用 GD 再压一遍（最长边 1600，质量 75）。 */
    public static function recompressIfNeeded(string $path): void
    {
        if (!function_exists('imagecreatefromjpeg') || !is_file($path)) {
            return;
        }
        $info = @getimagesize($path);
        if ($info === false) {
            return;
        }
        $w = (int)($info[0] ?? 0);
        $h = (int)($info[1] ?? 0);
        $size = (int)filesize($path);
        $maxSide = 1600;
        $maxBytes = 900 * 1024;
        if ($w <= $maxSide && $h <= $maxSide && $size <= $maxBytes) {
            return;
        }
        $im = @imagecreatefromjpeg($path);
        if ($im === false) {
            return;
        }
        $nw = $w;
        $nh = $h;
        if ($w > $maxSide || $h > $maxSide) {
            $scale = $maxSide / max($w, $h);
            $nw = max(1, (int)round($w * $scale));
            $nh = max(1, (int)round($h * $scale));
        }
        $out = imagecreatetruecolor($nw, $nh);
        if ($out === false) {
            imagedestroy($im);
            return;
        }
        imagecopyresampled($out, $im, 0, 0, 0, 0, $nw, $nh, $w, $h);
        imagedestroy($im);
        imagejpeg($out, $path, 75);
        imagedestroy($out);
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
