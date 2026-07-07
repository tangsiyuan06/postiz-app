/**
 * Mock SSO verification server for local testing.
 *
 * Implements POST /api/sso/verify
 * Returns merchantId (user id) and merchantName (org name) from the token.
 *
 * Token format: any string — the token itself is used as merchantId,
 * or you can use one of the preset tokens below.
 *
 * Usage:
 *   node doc/sso-test/mock-sso-server.js
 *
 * Then set in .env:
 *   SSO_SERVER_URL=http://localhost:8080
 */

const http = require('http');

// Preset tokens → { merchantId, merchantName }
// Any token NOT in this map will use token value as merchantId directly.
const TOKENS = {
  'token-alice': { merchant_id: 'merchant-alice', merchant_name: 'Alice Store' },
  'token-bob':   { merchant_id: 'merchant-bob',   merchant_name: 'Bob Agency' },
};

const PORT = process.env.PORT || 8081;

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === 'POST' && req.url === '/api/sso/verify') {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try {
        const { auth_code } = JSON.parse(body);

        if (!auth_code) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing auth_code' }));
          return;
        }

        const preset = TOKENS[auth_code];
        const result = preset ?? {
          merchant_id: auth_code,
          merchant_name: `Merchant(${auth_code})`,
        };

        console.log(`[verify] auth_code="${auth_code}" → merchant_id="${result.merchant_id}"`);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`Mock SSO server listening on http://localhost:${PORT}`);
  console.log('Preset tokens:');
  Object.entries(TOKENS).forEach(([t, m]) =>
    console.log(`  ${t}  →  merchantId=${m.merchantId}  merchantName=${m.merchantName}`)
  );
  console.log('Any other token value is used as merchantId directly.');
});
