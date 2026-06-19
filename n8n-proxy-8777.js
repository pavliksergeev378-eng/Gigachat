// n8n-proxy-8777.js
// Node.js fallback proxy, версия 3.

const http = require('http');
const https = require('https');
const { URL } = require('url');

const PORT = Number(process.env.PROXY_PORT || 8777);
const N8N_BASE = process.env.N8N_BASE || 'http://130.100.92.170:5678';

const N8N_BASIC_AUTH_USER = process.env.N8N_BASIC_AUTH_USER || '';
const N8N_BASIC_AUTH_PASSWORD = process.env.N8N_BASIC_AUTH_PASSWORD || '';
const N8N_API_KEY = process.env.N8N_API_KEY || '';
const N8N_COOKIE = process.env.N8N_COOKIE || '';

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Auth-Token, Authorization, X-N8N-API-KEY');
  res.setHeader('Access-Control-Max-Age', '86400');
}

function sendJson(res, status, obj) {
  setCors(res);
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj, null, 2));
}

function isAllowedPath(pathname) {
  return pathname === '/n8n-healthz' ||
    pathname === '/rest' ||
    pathname.startsWith('/rest/') ||
    pathname.startsWith('/webhook') ||
    pathname.startsWith('/webhook-trigger');
}

function mapPath(pathname, search) {
  if (pathname === '/n8n-healthz') return '/healthz' + (search || '');
  return pathname + (search || '');
}

function applyUpstreamAuth(headers) {
  if (N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD && !headers.authorization) {
    const raw = Buffer.from(`${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}`, 'utf8').toString('base64');
    headers.authorization = `Basic ${raw}`;
  }
  if (N8N_API_KEY && !headers['x-n8n-api-key']) {
    headers['x-n8n-api-key'] = N8N_API_KEY;
  }
  if (N8N_COOKIE && !headers.cookie) {
    headers.cookie = N8N_COOKIE;
  }
}

function proxy(req, res, pathname, search) {
  const base = new URL(N8N_BASE);
  const targetPath = mapPath(pathname, search);
  const client = base.protocol === 'https:' ? https : http;

  const headers = { ...req.headers };
  headers.host = base.host;
  delete headers.connection;
  delete headers['content-length'];

  applyUpstreamAuth(headers);

  const options = {
    protocol: base.protocol,
    hostname: base.hostname,
    port: base.port || (base.protocol === 'https:' ? 443 : 80),
    method: req.method,
    path: targetPath,
    headers,
  };

  const upstreamReq = client.request(options, (upstreamRes) => {
    setCors(res);
    res.statusCode = upstreamRes.statusCode || 502;
    for (const [key, value] of Object.entries(upstreamRes.headers)) {
      const lower = key.toLowerCase();
      if (lower.startsWith('access-control-')) continue;
      if (['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade'].includes(lower)) continue;
      if (value !== undefined) res.setHeader(key, value);
    }
    upstreamRes.pipe(res);
  });

  upstreamReq.on('error', (err) => {
    sendJson(res, 502, {
      error: 'n8n proxy error',
      message: err.message,
      n8nBase: N8N_BASE,
      path: targetPath,
    });
  });

  req.pipe(upstreamReq);
}

const server = http.createServer((req, res) => {
  let parsed;
  try {
    parsed = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch (e) {
    return sendJson(res, 400, { error: 'Bad request' });
  }

  if (req.method === 'OPTIONS') {
    setCors(res);
    res.statusCode = 204;
    return res.end();
  }

  if (!isAllowedPath(parsed.pathname)) {
    return sendJson(res, 404, {
      error: 'Proxy route not found',
      allowed: ['/n8n-healthz', '/rest/*', '/webhook*', '/webhook-trigger*'],
    });
  }

  return proxy(req, res, parsed.pathname, parsed.search);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('n8n proxy started');
  console.log(`Proxy: http://localhost:${PORT}`);
  console.log(`n8n:   ${N8N_BASE}`);
  console.log('');
  console.log('Auth forwarding:');
  console.log(`  Basic Auth: ${N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD ? 'ON' : 'OFF'}`);
  console.log(`  API key:    ${N8N_API_KEY ? 'ON' : 'OFF'}`);
  console.log(`  Cookie:     ${N8N_COOKIE ? 'ON' : 'OFF'}`);
  console.log('');
  console.log(`Health check: http://localhost:${PORT}/n8n-healthz`);
});

server.on('error', (err) => {
  console.error('Proxy failed:', err.message);
  if (err.code === 'EADDRINUSE') console.error(`Port ${PORT} is already in use.`);
  process.exit(1);
});
