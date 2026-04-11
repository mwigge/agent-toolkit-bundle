import { createServer } from 'node:http';
import { AsyncLocalStorage } from 'node:async_hooks';
import { randomUUID } from 'node:crypto';

// ── Structured logger ─────────────────────────────────────────────────────────
// All log output is newline-delimited JSON. Never use console.log in library code.

/** @type {AsyncLocalStorage<{ traceId: string; requestId: string; userId?: string }>} */
const requestContext = new AsyncLocalStorage();

function log(level, data, msg) {
  const store = requestContext.getStore() ?? {};
  process.stdout.write(
    JSON.stringify({
      level,
      msg,
      time: Date.now(),
      ...store,
      ...data,
    }) + '\n'
  );
}

const logger = {
  info:  (data, msg) => log('info',  data, msg),
  warn:  (data, msg) => log('warn',  data, msg),
  error: (data, msg) => log('error', data, msg),
  debug: (data, msg) => log('debug', data, msg),
  fatal: (data, msg) => log('fatal', data, msg),
};

// ── Domain error classes ──────────────────────────────────────────────────────

export class AppError extends Error {
  /** @param {string} message @param {Record<string, unknown>} [context] */
  constructor(message, context = {}) {
    super(message);
    this.name = this.constructor.name;
    this.context = context;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class NotFoundError extends AppError {
  constructor(resource, id) {
    super(`${resource} not found`, { resource, id });
    this.statusCode = 404;
  }
}

export class ValidationError extends AppError {
  constructor(message, fields = {}) {
    super(message, { fields });
    this.statusCode = 400;
  }
}

// ── Request handler ───────────────────────────────────────────────────────────

/**
 * Minimal router — maps [method, path pattern] → handler function.
 * For production, replace with a trie-based router or Fastify.
 *
 * @type {Array<{ method: string; pattern: RegExp; keys: string[]; handler: Function }>}
 */
const routes = [];

/**
 * Register a route handler.
 * @param {'GET'|'POST'|'PUT'|'PATCH'|'DELETE'} method
 * @param {string} path  - Express-style: /users/:id
 * @param {(req: import('node:http').IncomingMessage & { params: Record<string,string>; body: unknown }, res: import('node:http').ServerResponse) => Promise<void>} handler
 */
export function route(method, path, handler) {
  const keys = [];
  const pattern = new RegExp(
    '^' + path.replace(/:([a-zA-Z]+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$'
  );
  routes.push({ method, pattern, keys, handler });
}

/**
 * Parse raw body as JSON. Returns null on empty body.
 * @param {import('node:http').IncomingMessage} req
 * @returns {Promise<unknown>}
 */
async function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    const MAX_BODY = 1_048_576; // 1 MiB

    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        req.destroy();
        return reject(new ValidationError('Request body too large'));
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve(null);
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new ValidationError('Invalid JSON body'));
      }
    });

    req.on('error', reject);
  });
}

/**
 * Send a JSON response.
 * @param {import('node:http').ServerResponse} res
 * @param {number} statusCode
 * @param {unknown} body
 */
function sendJson(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

/**
 * Main request handler — injected into node:http createServer.
 * Sets up AsyncLocalStorage context, routes the request, handles errors.
 *
 * @param {import('node:http').IncomingMessage} req
 * @param {import('node:http').ServerResponse} res
 */
async function handleRequest(req, res) {
  const start = Date.now();
  const traceId = req.headers['x-trace-id'] ?? randomUUID();
  const requestId = randomUUID();

  requestContext.run({ traceId, requestId }, async () => {
    logger.info({ method: req.method, url: req.url }, 'incoming request');

    try {
      // Parse body for mutating methods
      let body = null;
      if (['POST', 'PUT', 'PATCH'].includes(req.method ?? '')) {
        body = await parseBody(req);
      }

      // Route matching
      const matched = routes.find(
        (r) => r.method === req.method && r.pattern.test(req.url?.split('?')[0] ?? '/')
      );

      if (!matched) {
        sendJson(res, 404, { error: 'NotFound', message: `${req.method} ${req.url} not found` });
        return;
      }

      const match = matched.pattern.exec(req.url?.split('?')[0] ?? '/');
      const params = Object.fromEntries(
        matched.keys.map((k, i) => [k, decodeURIComponent(match?.[i + 1] ?? '')])
      );

      Object.assign(req, { params, body });
      await matched.handler(req, res);
    } catch (err) {
      if (err instanceof AppError) {
        sendJson(res, err.statusCode ?? 500, {
          error: err.name,
          message: err.message,
          ...err.context,
        });
        logger.warn({ err: { name: err.name, message: err.message, context: err.context } }, 'request error');
        return;
      }

      logger.error({ err: { name: err.name, message: err.message, stack: err.stack } }, 'unhandled error');
      sendJson(res, 500, { error: 'InternalServerError', message: 'An unexpected error occurred' });
    } finally {
      const store = requestContext.getStore() ?? {};
      logger.info(
        { method: req.method, url: req.url, statusCode: res.statusCode, durationMs: Date.now() - start },
        'request complete'
      );
    }
  });
}

// ── Example routes ─────────────────────────────────────────────────────────

route('GET', '/health', async (_req, res) => {
  sendJson(res, 200, { status: 'ok', uptime: process.uptime() });
});

route('GET', '/users/:id', async (req, res) => {
  const { id } = req.params;
  // Replace with actual data access
  if (id === 'not-found') throw new NotFoundError('User', id);
  sendJson(res, 200, { id, name: 'Alice', email: 'alice@example.com' });
});

route('POST', '/users', async (req, res) => {
  const body = req.body;
  if (!body?.email) throw new ValidationError('email is required', { email: 'missing' });
  const user = { id: randomUUID(), ...body, createdAt: new Date().toISOString() };
  sendJson(res, 201, user);
});

// ── Server lifecycle ──────────────────────────────────────────────────────────

const PORT = Number(process.env.PORT ?? 3000);
const HOST = process.env.HOST ?? '0.0.0.0';

const server = createServer((req, res) => {
  // Wrap in void to make the top-level async call explicit
  void handleRequest(req, res);
});

// Graceful shutdown — give in-flight requests time to complete
let isShuttingDown = false;

function gracefulShutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.info({ signal }, 'shutdown signal received — closing server');

  server.close((err) => {
    if (err) {
      logger.fatal({ err }, 'error closing HTTP server');
      process.exitCode = 1;
    } else {
      logger.info({}, 'server closed cleanly');
    }
    // Allow any async cleanup (DB connections etc.) to run before exit
    setTimeout(() => process.exit(process.exitCode ?? 0), 50);
  });

  // Force-kill if graceful shutdown takes too long
  setTimeout(() => {
    logger.fatal({}, 'graceful shutdown timed out — forcing exit');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT',  () => gracefulShutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'unhandled promise rejection');
  process.exitCode = 1;
  gracefulShutdown('unhandledRejection');
});

process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'uncaught exception');
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  logger.info({ port: PORT, host: HOST }, 'server started');
});

export { server, logger, requestContext, sendJson };
