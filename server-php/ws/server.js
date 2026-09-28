#!/usr/bin/env node
/**
 * WebSocket 实时枢纽（不用 FCM）。
 *
 * 环境变量（可由 start_ws.sh 从 config.php 注入）：
 *   WS_PORT              默认 8765
 *   JWT_SECRET           与 PHP jwt_secret 相同
 *   WS_INTERNAL_TOKEN    PHP 发布事件时的共享密钥
 *
 * 客户端：wss://域名/ws?token=<user|admin JWT>
 * PHP 发布：POST http://127.0.0.1:8765/publish
 *   Header: X-Internal-Token: <WS_INTERNAL_TOKEN>
 *   Body: { "targets":[{"role":"user"|"admin","id":number|null}], "payload":{...} }
 *   role=admin 且 id 省略/null → 所有在线管理员
 *   role=user 且 id 省略/null → 所有在线用户（广播站内信）
 */
'use strict';

const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.WS_PORT || '8765', 10);
const JWT_SECRET = process.env.JWT_SECRET || '';
const INTERNAL = process.env.WS_INTERNAL_TOKEN || '';

if (!JWT_SECRET) {
  console.error('ERROR: JWT_SECRET 未设置');
  process.exit(1);
}
if (!INTERNAL) {
  console.error('ERROR: WS_INTERNAL_TOKEN 未设置');
  process.exit(1);
}

function b64urlDecode(s) {
  const pad = 4 - (s.length % 4);
  const raw = s + (pad < 4 ? '='.repeat(pad) : '');
  return Buffer.from(raw.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function verifyJwt(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const signing = `${h}.${p}`;
  const expected = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(signing)
    .digest('base64')
    .replace(/=+$/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  const a = Buffer.from(expected);
  const b = Buffer.from(s);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let payload;
  try {
    payload = JSON.parse(b64urlDecode(p).toString('utf8'));
  } catch {
    return null;
  }
  if (payload.exp != null && Date.now() / 1000 >= Number(payload.exp)) return null;
  return payload;
}

/** @type {Map<import('ws').WebSocket, {role:string,id:number}>} */
const clients = new Map();

function identityKey(role, id) {
  if (role === 'admin') return id == null ? 'admin:*' : `admin:${id}`;
  if (role === 'user') return id == null ? 'user:*' : `user:${id}`;
  return '';
}

function sendJson(ws, obj) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(obj));
  }
}

function broadcast(targets, payload) {
  const list = Array.isArray(targets) ? targets : [];
  let n = 0;
  for (const [ws, idn] of clients) {
    for (const t of list) {
      const role = t.role;
      const tid = t.id == null || t.id === '' ? null : Number(t.id);
      if (role === 'admin' && idn.role === 'admin') {
        if (tid == null || tid === idn.id) {
          sendJson(ws, payload);
          n += 1;
          break;
        }
      }
      if (role === 'user' && idn.role === 'user') {
        if (tid == null || tid === idn.id) {
          sendJson(ws, payload);
          n += 1;
          break;
        }
      }
    }
  }
  return n;
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/' || req.url === '/health')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, clients: clients.size }));
    return;
  }
  if (req.method === 'POST' && req.url === '/publish') {
    const token = req.headers['x-internal-token'] || '';
    if (token !== INTERNAL) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'forbidden' }));
      return;
    }
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 1e6) req.destroy();
    });
    req.on('end', () => {
      try {
        const msg = JSON.parse(body || '{}');
        const delivered = broadcast(msg.targets || [], msg.payload || {});
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, delivered }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'bad_json' }));
      }
    });
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url || '/', 'http://localhost');
  const token = url.searchParams.get('token') || '';
  const payload = verifyJwt(token);
  if (!payload) {
    sendJson(ws, { type: 'error', message: 'unauthorized' });
    ws.close(4401, 'unauthorized');
    return;
  }

  let role;
  let id;
  if (payload.typ === 'admin') {
    role = 'admin';
    id = parseInt(String(payload.sub ?? payload.admin_id ?? 0), 10);
  } else {
    role = 'user';
    id = parseInt(String(payload.sub ?? 0), 10);
  }
  if (!id) {
    ws.close(4401, 'unauthorized');
    return;
  }

  clients.set(ws, { role, id });
  sendJson(ws, { type: 'hello', role, id, key: identityKey(role, id) });

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(String(raw));
    } catch {
      return;
    }
    if (data && data.type === 'ping') {
      sendJson(ws, { type: 'pong', t: Date.now() });
    }
  });

  ws.on('close', () => clients.delete(ws));
  ws.on('error', () => clients.delete(ws));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[ws] listening 127.0.0.1:${PORT} path=/ws clients=0`);
});

setInterval(() => {
  for (const ws of clients.keys()) {
    sendJson(ws, { type: 'ping', t: Date.now() });
  }
}, 25000);
