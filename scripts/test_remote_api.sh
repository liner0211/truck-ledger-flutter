#!/usr/bin/env bash
# 本地 API 联调：健康检查 → 注册 → 登录 → 上传账本 → 拉取验证
set -euo pipefail

BASE="${API_BASE_URL:-https://truck.liner0211.online}"
USER="${TEST_USERNAME:-test_$(date +%s)}"
PASS="${TEST_PASSWORD:-TestPass123456}"
PLATE="${TEST_LICENSE_PLATE:-京A12345}"

echo "=== 卡车记账 API 本地测试 ==="
echo "BASE=$BASE"
echo "USER=$USER"
echo

echo "[1/5] GET /api/health"
HEALTH=$(curl -sS -m 15 "$BASE/api/health")
echo "  $HEALTH"
echo "$HEALTH" | grep -q '"status":"ok"' || { echo "FAIL: health"; exit 1; }
echo "  OK"
echo

echo "[2/5] POST /api/auth/register"
REG=$(curl -sS -m 20 -w "\nHTTP_CODE:%{http_code}" -X POST "$BASE/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\",\"license_plate\":\"$PLATE\"}")
REG_BODY=$(echo "$REG" | sed '/HTTP_CODE:/d')
REG_CODE=$(echo "$REG" | grep HTTP_CODE | cut -d: -f2)
echo "  HTTP $REG_CODE"
echo "  $REG_BODY"
if [[ "$REG_CODE" != "200" ]]; then
  echo "[2b] 注册失败，尝试登录已有账号"
  REG_BODY=""
fi
echo

echo "[3/5] POST /api/auth/login"
LOGIN=$(curl -sS -m 20 -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}")
echo "  $LOGIN"
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)
if [[ -z "$TOKEN" ]]; then
  echo "FAIL: 无法获取 token"
  exit 1
fi
echo "  token=${TOKEN:0:20}..."
echo "  OK"
echo

SAMPLE='{"rounds":[{"id":"test-trip-1","title":"本地测试圈次","startPlace":"2026-01-01 08:00","endPlace":"2026-01-02 18:00","createdAt":"2026-01-01T08:00:00.000","isReconciled":false,"isSalarySettled":false,"routeLegs":[],"expenses":[],"cashAdvances":[]}]}'

echo "[4/5] PUT /api/ledger"
PUT=$(curl -sS -m 30 -w "\nHTTP_CODE:%{http_code}" -X PUT "$BASE/api/ledger" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$SAMPLE")
PUT_BODY=$(echo "$PUT" | sed '/HTTP_CODE:/d')
PUT_CODE=$(echo "$PUT" | grep HTTP_CODE | cut -d: -f2)
echo "  HTTP $PUT_CODE"
echo "  $PUT_BODY"
[[ "$PUT_CODE" == "200" ]] || { echo "FAIL: put ledger"; exit 1; }
echo "  OK"
echo

echo "[5/5] GET /api/ledger"
GET=$(curl -sS -m 20 "$BASE/api/ledger" -H "Authorization: Bearer $TOKEN")
echo "  $GET" | python3 -c "
import sys, json
d = json.load(sys.stdin)
n = len(d.get('rounds', []))
title = d['rounds'][0]['title'] if n else ''
print(f'  rounds={n}, first_title={title!r}, updated_at={d.get(\"updated_at\")}')
assert n >= 1 and title == '本地测试圈次', 'ledger mismatch'
print('  OK')
"

echo
echo "=== 全部通过 ==="
echo "测试账号: $USER / $PASS"
