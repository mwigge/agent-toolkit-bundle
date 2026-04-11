import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Build and configure the Fastify application.
 *
 * Returns a configured but not-yet-listening FastifyInstance.
 * This separation makes the app trivially testable via fastify.inject()
 * without binding to any port.
 *
 * @param opts - Override Fastify options (e.g. { logger: false } in tests)
 */
export async function buildApp(
  opts: Parameters<typeof Fastify>[0] = {}
): Promise<FastifyInstance> {
  const fastify = Fastify({
    logger: {
      level: process.env.LOG_LEVEL ?? 'info',
      redact: {
        paths: [
          'req.headers.authorization',
          'req.headers.cookie',
          'req.headers["x-api-key"]',
          'body.password',
          'body.token',
          'body.secret',
        ],
        censor: '[REDACTED]',
      },
      serializers: {
        req(request) {
          return {
            method: request.method,
            url: request.url,
            remoteAddress: request.ip,
            userAgent: request.headers['user-agent'],
          };
        },
        res(reply) {
          return { statusCode: reply.statusCode };
        },
      },
    },
    ajv: {
      customOptions: {
        strict: true,
        allErrors: false,
        coerceTypes: false,
        useDefaults: true,
      },
    },
    trustProxy: true,
    ...opts,
  });

  // ── Security plugins ───────────────────────────────────────────────────────
  await fastify.register(import('@fastify/helmet'), {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        objectSrc: ["'none'"],
        upgradeInsecureRequests: [],
      },
    },
  });

  await fastify.register(import('@fastify/cors'), {
    origin: process.env.ALLOWED_ORIGINS?.split(',').map((o) => o.trim()) ?? false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
  });

  await fastify.register(import('@fastify/rate-limit'), {
    max: Number(process.env.RATE_LIMIT_MAX ?? 100),
    timeWindow: process.env.RATE_LIMIT_WINDOW ?? '1 minute',
    // Use authenticated user ID when available, fall back to IP
    keyGenerator: (request) =>
      (request as typeof request & { user?: { id: string } }).user?.id ?? request.ip,
    errorResponseBuilder: (_request, context) => ({
      error: 'TooManyRequests',
      message: `Rate limit exceeded. Retry after ${context.after}`,
      statusCode: 429,
    }),
  });

  // ── Config plugin (register first — others depend on it) ──────────────────
  await fastify.register(import('./plugins/config.js'));

  // ── Auth plugin ────────────────────────────────────────────────────────────
  await fastify.register(import('@fastify/jwt'), {
    secret: process.env.JWT_SECRET ?? (() => { throw new Error('JWT_SECRET is required'); })(),
    sign: { expiresIn: '15m' },
    verify: { algorithms: ['HS256'] },
  });

  // Decorate with authenticate helper used in route preHandler hooks
  fastify.decorate(
    'authenticate',
    async function authenticate(request: Parameters<typeof fastify.inject>[0] extends infer R ? R : never, reply: unknown) {
      // @ts-expect-error — request type varies; jwtVerify is injected by @fastify/jwt
      await request.jwtVerify();
    }
  );

  // ── Application routes ─────────────────────────────────────────────────────
  // Health check — no auth required; used by load balancer / k8s probes
  fastify.get(
    '/health',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string' },
              uptime: { type: 'number' },
              timestamp: { type: 'string' },
            },
          },
        },
      },
    },
    async (_request, reply) => {
      return reply.send({
        status: 'ok',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
      });
    }
  );

  fastify.get(
    '/ready',
    {
      schema: { response: { 200: { type: 'object', properties: { status: { type: 'string' } } } } },
    },
    async (_request, reply) => {
      // Add readiness checks here (DB ping, cache ping etc.)
      return reply.send({ status: 'ready' });
    }
  );

  // Domain routes — register with prefix
  await fastify.register(import('./routes/widgets.js'), { prefix: '/api/v1/widgets' });

  // ── Global error handler ───────────────────────────────────────────────────
  fastify.setErrorHandler((error, request, reply) => {
    request.log.error({ err: error }, 'unhandled request error');

    if ('statusCode' in error && typeof error.statusCode === 'number') {
      return reply.code(error.statusCode).send({
        error: error.name,
        message: error.message,
        statusCode: error.statusCode,
      });
    }

    if (error.validation) {
      return reply.code(400).send({
        error: 'ValidationError',
        message: 'Request validation failed',
        statusCode: 400,
        details: error.validation,
      });
    }

    return reply.code(500).send({
      error: 'InternalServerError',
      message: 'An unexpected error occurred',
      statusCode: 500,
    });
  });

  fastify.setNotFoundHandler((request, reply) => {
    reply.code(404).send({
      error: 'NotFound',
      message: `Route ${request.method} ${request.url} not found`,
      statusCode: 404,
    });
  });

  return fastify;
}

// ── Application entry point ────────────────────────────────────────────────────
// Only runs when this file is executed directly (not when imported in tests).

const isMain = process.argv[1] === new URL(import.meta.url).pathname;

if (isMain) {
  const PORT = Number(process.env.PORT ?? 3000);
  const HOST = process.env.HOST ?? '0.0.0.0';

  const app = await buildApp();

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'shutdown signal received');
    try {
      await app.close();
      app.log.info({}, 'server closed cleanly');
      process.exit(0);
    } catch (err) {
      app.log.fatal({ err }, 'error during shutdown');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT',  () => void shutdown('SIGINT'));

  process.on('unhandledRejection', (reason) => {
    app.log.fatal({ err: reason }, 'unhandled rejection — shutting down');
    void shutdown('unhandledRejection');
  });

  await app.listen({ port: PORT, host: HOST });
}
