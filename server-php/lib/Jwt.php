<?php
declare(strict_types=1);

final class Jwt
{
    public static function encode(array $payload, string $secret): string
    {
        $header = ['typ' => 'JWT', 'alg' => 'HS256'];
        $segments = [
            self::b64url(json_encode($header, JSON_THROW_ON_ERROR)),
            self::b64url(json_encode($payload, JSON_THROW_ON_ERROR)),
        ];
        $signing = implode('.', $segments);
        $sig = hash_hmac('sha256', $signing, $secret, true);
        $segments[] = self::b64url($sig);
        return implode('.', $segments);
    }

    public static function decode(string $token, string $secret): ?array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            return null;
        }
        [$h, $p, $s] = $parts;
        $signing = $h . '.' . $p;
        $expected = self::b64url(hash_hmac('sha256', $signing, $secret, true));
        if (!hash_equals($expected, $s)) {
            return null;
        }
        $payload = json_decode(self::b64urlDecode($p), true);
        if (!is_array($payload)) {
            return null;
        }
        if (isset($payload['exp']) && time() >= (int)$payload['exp']) {
            return null;
        }
        return $payload;
    }

    private static function b64url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function b64urlDecode(string $data): string
    {
        $pad = 4 - (strlen($data) % 4);
        if ($pad < 4) {
            $data .= str_repeat('=', $pad);
        }
        return base64_decode(strtr($data, '-_', '+/'), true) ?: '';
    }
}
