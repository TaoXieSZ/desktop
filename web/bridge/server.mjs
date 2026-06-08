import { spawn } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HOST = '127.0.0.1';
const PORT = Number.parseInt(process.env.AHAKEY_WEB_BRIDGE_PORT ?? '17341', 10);
const ALLOWED_ORIGINS = new Set([
  'http://127.0.0.1:5173',
  'http://localhost:5173',
]);

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');
const macosRoot = path.join(repoRoot, 'platforms', 'macos');
const defaultKeyProfile = [
  { mode: 1, keyIndex: 0, hidCodes: [0x6d], label: 'Doubao Fn' },
  { mode: 1, keyIndex: 1, hidCodes: [0x28], label: 'Approve' },
  { mode: 1, keyIndex: 2, hidCodes: [0x29], label: 'Deny' },
  { mode: 1, keyIndex: 3, hidCodes: [0x28], label: 'Enter' },
];

const server = http.createServer(async (req, res) => {
  try {
    addCors(req, res);

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url ?? '/', `http://${HOST}:${PORT}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      sendJSON(res, 200, {
        ok: true,
        name: 'ahakey-web-bridge',
        host: HOST,
        port: PORT,
        helper: 'AhaKeyWebBridgeHelper',
      });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/status') {
      const helper = await runHelper(['status', '--dry-run']);
      sendJSON(res, helper.ok ? 200 : 502, {
        ok: helper.ok,
        bridge: { host: HOST, port: PORT },
        helper,
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/remap/shortcut') {
      const body = await readJSONBody(req);
      const payload = validateShortcutPayload(body);
      const helper = await applyShortcut(payload);
      sendJSON(res, helper.ok ? 200 : 502, {
        ok: helper.ok,
        request: payload,
        helper,
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/remap/default-profile') {
      const body = await readJSONBody(req);
      const mode = valueOrDefaultMode(body.mode);
      const dryRun = dryRunOnly(body.dryRun);
      const requests = defaultKeyProfile.map((item) => ({ ...item, mode, dryRun }));
      const results = [];
      for (const request of requests) {
        const helper = await applyShortcut(request);
        results.push({ request, helper });
        if (!helper.ok) {
          break;
        }
      }

      const ok = results.length === requests.length && results.every((item) => item.helper.ok);
      sendJSON(res, ok ? 200 : 502, {
        ok,
        dryRun,
        mode,
        results,
      });
      return;
    }

    sendJSON(res, 404, { ok: false, error: 'not found' });
  } catch (error) {
    const status = error instanceof ClientError ? error.status : 500;
    sendJSON(res, status, {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`AhaKey web bridge listening on http://${HOST}:${PORT}`);
});

function addCors(req, res) {
  const origin = req.headers.origin;
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJSON(res, status, value) {
  const json = JSON.stringify(value);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(json),
  });
  res.end(json);
}

async function readJSONBody(req) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    bytes += chunk.byteLength;
    if (bytes > 32_768) {
      throw new ClientError(413, 'request body too large');
    }
    chunks.push(chunk);
  }

  const text = Buffer.concat(chunks).toString('utf8');
  if (!text.trim()) {
    throw new ClientError(400, 'missing JSON body');
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new ClientError(400, 'invalid JSON body');
  }
}

function validateShortcutPayload(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ClientError(400, 'body must be an object');
  }

  const mode = integerField(value, 'mode', 0, 2);
  const keyIndex = integerField(value, 'keyIndex', 0, 3);
  const hidCodes = arrayField(value, 'hidCodes');
  const label = typeof value.label === 'string' ? value.label.trim().slice(0, 20) : '';
  const dryRun = dryRunOnly(value.dryRun);

  return { mode, keyIndex, hidCodes, label, dryRun };
}

function valueOrDefaultMode(value) {
  if (value === undefined) {
    return 1;
  }
  if (!Number.isInteger(value) || value < 0 || value > 2) {
    throw new ClientError(400, 'mode must be an integer 0...2');
  }
  return value;
}

function dryRunOnly(value) {
  if (value === false) {
    throw new ClientError(403, 'legacy bridge is dry-run only; use ahakeyd for trusted apply flows');
  }
  return true;
}

function integerField(value, name, min, max) {
  const field = value[name];
  if (!Number.isInteger(field) || field < min || field > max) {
    throw new ClientError(400, `${name} must be an integer ${min}...${max}`);
  }
  return field;
}

function arrayField(value, name) {
  const field = value[name];
  if (!Array.isArray(field)) {
    throw new ClientError(400, `${name} must be an array`);
  }
  if (field.length > 98) {
    throw new ClientError(400, `${name} exceeds firmware limit`);
  }
  for (const item of field) {
    if (!Number.isInteger(item) || item < 0 || item > 255) {
      throw new ClientError(400, `${name} entries must be bytes`);
    }
  }
  return field;
}

function runHelper(args) {
  return new Promise((resolve) => {
    const child = spawn('swift', ['run', '--package-path', macosRoot, 'AhaKeyWebBridgeHelper', ...args], {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';
    const timeout = setTimeout(() => {
      child.kill('SIGTERM');
    }, 25_000);

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('close', (code, signal) => {
      clearTimeout(timeout);
      const parsed = parseHelperJSON(stdout);
      if (parsed) {
        resolve({
          ...parsed,
          exitCode: code,
          signal,
          stderr: stderr.trim(),
        });
        return;
      }

      resolve({
        ok: false,
        exitCode: code,
        signal,
        error: signal ? `helper terminated by ${signal}` : 'helper did not return JSON',
        stdout: stdout.trim(),
        stderr: stderr.trim(),
      });
    });
    child.on('error', (error) => {
      clearTimeout(timeout);
      resolve({
        ok: false,
        exitCode: null,
        error: error.message,
      });
    });
  });
}

function applyShortcut(payload) {
  const args = [
    'apply-shortcut',
    '--mode',
    String(payload.mode),
    '--key-index',
    String(payload.keyIndex),
    '--hid-codes',
    payload.hidCodes.join(','),
  ];

  if (payload.label) {
    args.push('--label', payload.label);
  }
  if (payload.dryRun) {
    args.push('--dry-run');
  }

  return runHelper(args);
}

function parseHelperJSON(stdout) {
  const line = stdout.trim().split('\n').findLast((item) => item.trim().startsWith('{'));
  if (!line) {
    return null;
  }
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

class ClientError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
