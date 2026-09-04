<?php
declare(strict_types=1);

final class JsonResponse
{
    public static function send(array $data, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE);
        exit;
    }

    public static function error(string $detail, int $status = 400): void
    {
        self::send(['detail' => $detail], $status);
    }

    public static function cors(?array $cfg = null): void
    {
        $origins = $cfg['cors_origins'] ?? ['*'];
        if (!is_array($origins) || $origins === []) {
            $origins = ['*'];
        }
        $requestOrigin = $_SERVER['HTTP_ORIGIN'] ?? '';
        if (in_array('*', $origins, true)) {
            header('Access-Control-Allow-Origin: *');
        } elseif ($requestOrigin !== '' && in_array($requestOrigin, $origins, true)) {
            header('Access-Control-Allow-Origin: ' . $requestOrigin);
            header('Vary: Origin');
        }
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Authorization, Content-Type, X-App-Platform, X-App-Version, X-Device-Id, If-Match');
        if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
    }
}
