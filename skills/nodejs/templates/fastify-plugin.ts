import { Type, type Static } from '@sinclair/typebox';
import { FastifyPluginAsyncTypebox } from '@fastify/type-provider-typebox';
import fp from 'fastify-plugin';
import createError from '@fastify/error';

// ── Schemas ───────────────────────────────────────────────────────────────────
// TypeBox gives us JSON Schema (used by Fastify for validation + serialisation)
// and TypeScript types (used by handlers) from a single source of truth.

const WidgetParams = Type.Object({
  id: Type.String({ format: 'uuid' }),
});

const CreateWidgetBody = Type.Object(
  {
    name: Type.String({ minLength: 1, maxLength: 200 }),
    description: Type.Optional(Type.String({ maxLength: 1000 })),
    active: Type.Optional(Type.Boolean({ default: true })),
  },
  { additionalProperties: false }
);

const UpdateWidgetBody = Type.Partial(CreateWidgetBody, { additionalProperties: false });

const WidgetResponse = Type.Object({
  id: Type.String({ format: 'uuid' }),
  name: Type.String(),
  description: Type.Union([Type.String(), Type.Null()]),
  active: Type.Boolean(),
  createdAt: Type.String({ format: 'date-time' }),
  updatedAt: Type.String({ format: 'date-time' }),
});

const WidgetListResponse = Type.Object({
  items: Type.Array(WidgetResponse),
  total: Type.Integer({ minimum: 0 }),
  page: Type.Integer({ minimum: 1 }),
  limit: Type.Integer({ minimum: 1 }),
});

const ListWidgetsQuery = Type.Object(
  {
    page: Type.Optional(Type.Integer({ minimum: 1, default: 1 })),
    limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, default: 20 })),
  },
  { additionalProperties: false }
);

type CreateWidgetBodyType = Static<typeof CreateWidgetBody>;
type UpdateWidgetBodyType = Static<typeof UpdateWidgetBody>;
type WidgetParamsType = Static<typeof WidgetParams>;
type WidgetResponseType = Static<typeof WidgetResponse>;

// ── Custom HTTP errors ────────────────────────────────────────────────────────
const WidgetNotFoundError = createError('WIDGET_NOT_FOUND', 'Widget %s not found', 404);
const WidgetConflictError = createError('WIDGET_CONFLICT', 'Widget with name "%s" already exists', 409);

// ── Service interface ─────────────────────────────────────────────────────────
// Define the contract here; implement it in a separate service file.
// This keeps the plugin testable: inject a mock service in tests.

export interface WidgetService {
  findAll(page: number, limit: number): Promise<{ items: WidgetResponseType[]; total: number }>;
  findById(id: string): Promise<WidgetResponseType | null>;
  create(data: CreateWidgetBodyType): Promise<WidgetResponseType>;
  update(id: string, data: UpdateWidgetBodyType): Promise<WidgetResponseType | null>;
  delete(id: string): Promise<boolean>;
}

// ── Fastify instance augmentation ─────────────────────────────────────────────
declare module 'fastify' {
  interface FastifyInstance {
    widgetService: WidgetService;
  }
}

// ── Plugin ────────────────────────────────────────────────────────────────────
const widgetsPlugin: FastifyPluginAsyncTypebox = async (fastify) => {
  // Each route gets a child logger scoped to this plugin — traceId/reqId are
  // automatically included in every log line via Pino's built-in correlation.
  const log = fastify.log.child({ plugin: 'widgets' });

  // ── GET / — list ──────────────────────────────────────────────────────────
  fastify.get(
    '/',
    {
      schema: {
        querystring: ListWidgetsQuery,
        response: { 200: WidgetListResponse },
      },
    },
    async (request, reply) => {
      const page = request.query.page ?? 1;
      const limit = request.query.limit ?? 20;

      const result = await fastify.widgetService.findAll(page, limit);

      return reply.send({ ...result, page, limit });
    }
  );

  // ── GET /:id — get one ────────────────────────────────────────────────────
  fastify.get(
    '/:id',
    {
      schema: {
        params: WidgetParams,
        response: { 200: WidgetResponse },
      },
    },
    async (request, reply) => {
      const widget = await fastify.widgetService.findById(request.params.id);
      if (!widget) throw new WidgetNotFoundError(request.params.id);
      return reply.send(widget);
    }
  );

  // ── POST / — create ───────────────────────────────────────────────────────
  fastify.post(
    '/',
    {
      schema: {
        body: CreateWidgetBody,
        response: { 201: WidgetResponse },
      },
    },
    async (request, reply) => {
      log.info({ name: request.body.name }, 'creating widget');
      const widget = await fastify.widgetService.create(request.body);
      return reply.code(201).send(widget);
    }
  );

  // ── PATCH /:id — update ───────────────────────────────────────────────────
  fastify.patch(
    '/:id',
    {
      schema: {
        params: WidgetParams,
        body: UpdateWidgetBody,
        response: { 200: WidgetResponse },
      },
    },
    async (request, reply) => {
      const existing = await fastify.widgetService.findById(request.params.id);
      if (!existing) throw new WidgetNotFoundError(request.params.id);

      const updated = await fastify.widgetService.update(request.params.id, request.body);
      if (!updated) throw new WidgetNotFoundError(request.params.id);

      return reply.send(updated);
    }
  );

  // ── DELETE /:id — delete ──────────────────────────────────────────────────
  fastify.delete(
    '/:id',
    {
      schema: {
        params: WidgetParams,
        response: { 204: { type: 'null' as const } },
      },
    },
    async (request, reply) => {
      const deleted = await fastify.widgetService.delete(request.params.id);
      if (!deleted) throw new WidgetNotFoundError(request.params.id);
      return reply.code(204).send();
    }
  );

  // ── Error handler — normalise all errors to consistent shape ──────────────
  fastify.setErrorHandler((error, request, reply) => {
    request.log.error({ err: error }, 'request failed');

    // Fastify HTTP errors (from @fastify/error, createError, or fastify itself)
    if ('statusCode' in error && typeof error.statusCode === 'number') {
      return reply.code(error.statusCode).send({
        error: error.name,
        message: error.message,
        statusCode: error.statusCode,
      });
    }

    // Ajv validation errors
    if (error.validation) {
      return reply.code(400).send({
        error: 'ValidationError',
        message: 'Request validation failed',
        statusCode: 400,
        details: error.validation,
      });
    }

    // Unknown — do not leak internals
    return reply.code(500).send({
      error: 'InternalServerError',
      message: 'An unexpected error occurred',
      statusCode: 500,
    });
  });
};

// fp() breaks encapsulation so decorations (widgetService) are visible app-wide.
export default fp(widgetsPlugin, {
  name: 'widgets',
  dependencies: ['widget-service'], // ensures widgetService is decorated before routes run
});
