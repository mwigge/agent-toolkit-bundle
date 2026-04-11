#!/usr/bin/env bash
# scripts/scaffold.sh — Fastify plugin scaffold generator
# Creates a typed Fastify plugin with routes, schemas, and tests.
#
# Usage: bash scripts/scaffold.sh <plugin-name> [target-src-dir]
#
# Example:
#   bash scripts/scaffold.sh payments
#   → src/plugins/payments.ts
#   → src/routes/payments.ts
#   → src/schemas/payments.ts
#   → src/routes/payments.test.ts

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf "${GREEN}[scaffold]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}    %s\n" "$*"; }
error() { printf "${RED}[error]${NC}   %s\n" "$*" >&2; }

# ── Arguments ────────────────────────────────────────────────────────────────
PLUGIN_NAME="${1:-}"
SRC_DIR="${2:-src}"

if [[ -z "$PLUGIN_NAME" ]]; then
  error "Plugin name is required"
  echo "Usage: bash scripts/scaffold.sh <plugin-name> [src-dir]"
  exit 1
fi

# Normalise: lowercase, replace spaces/underscores with hyphens
PLUGIN_NAME_KEBAB=$(echo "$PLUGIN_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '-')
# PascalCase for type names
PLUGIN_NAME_PASCAL=$(echo "$PLUGIN_NAME_KEBAB" | sed 's/-\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/')

info "Scaffolding plugin: $PLUGIN_NAME_KEBAB (types: ${PLUGIN_NAME_PASCAL})"

# ── Directory setup ───────────────────────────────────────────────────────────
PLUGINS_DIR="$SRC_DIR/plugins"
ROUTES_DIR="$SRC_DIR/routes"
SCHEMAS_DIR="$SRC_DIR/schemas"

mkdir -p "$PLUGINS_DIR" "$ROUTES_DIR" "$SCHEMAS_DIR"

PLUGIN_FILE="$PLUGINS_DIR/${PLUGIN_NAME_KEBAB}.ts"
ROUTES_FILE="$ROUTES_DIR/${PLUGIN_NAME_KEBAB}.ts"
SCHEMAS_FILE="$SCHEMAS_DIR/${PLUGIN_NAME_KEBAB}.ts"
TEST_FILE="$ROUTES_DIR/${PLUGIN_NAME_KEBAB}.test.ts"

check_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    warn "File already exists, skipping: $file"
    return 1
  fi
  return 0
}

# ── schemas/<name>.ts ─────────────────────────────────────────────────────────
if check_exists "$SCHEMAS_FILE"; then
  info "Writing $SCHEMAS_FILE"
  cat > "$SCHEMAS_FILE" <<SCHEMA_EOF
import { Type, type Static } from '@sinclair/typebox';

// ── Resource response ─────────────────────────────────────────────────────
export const ${PLUGIN_NAME_PASCAL}Response = Type.Object({
  id: Type.String({ format: 'uuid' }),
  createdAt: Type.String({ format: 'date-time' }),
  updatedAt: Type.String({ format: 'date-time' }),
});

export type ${PLUGIN_NAME_PASCAL}ResponseType = Static<typeof ${PLUGIN_NAME_PASCAL}Response>;

// ── Create request body ───────────────────────────────────────────────────
export const Create${PLUGIN_NAME_PASCAL}Body = Type.Object(
  {
    // Add your fields here
    name: Type.String({ minLength: 1, maxLength: 200 }),
  },
  { additionalProperties: false }
);

export type Create${PLUGIN_NAME_PASCAL}BodyType = Static<typeof Create${PLUGIN_NAME_PASCAL}Body>;

// ── Update request body ───────────────────────────────────────────────────
export const Update${PLUGIN_NAME_PASCAL}Body = Type.Partial(Create${PLUGIN_NAME_PASCAL}Body, {
  additionalProperties: false,
});

export type Update${PLUGIN_NAME_PASCAL}BodyType = Static<typeof Update${PLUGIN_NAME_PASCAL}Body>;

// ── Path params ───────────────────────────────────────────────────────────
export const ${PLUGIN_NAME_PASCAL}Params = Type.Object({
  id: Type.String({ format: 'uuid' }),
});

export type ${PLUGIN_NAME_PASCAL}ParamsType = Static<typeof ${PLUGIN_NAME_PASCAL}Params>;

// ── List query string ─────────────────────────────────────────────────────
export const List${PLUGIN_NAME_PASCAL}Query = Type.Object(
  {
    page: Type.Optional(Type.Integer({ minimum: 1, default: 1 })),
    limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, default: 20 })),
  },
  { additionalProperties: false }
);

export type List${PLUGIN_NAME_PASCAL}QueryType = Static<typeof List${PLUGIN_NAME_PASCAL}Query>;

export const ${PLUGIN_NAME_PASCAL}ListResponse = Type.Object({
  items: Type.Array(${PLUGIN_NAME_PASCAL}Response),
  total: Type.Integer(),
  page: Type.Integer(),
  limit: Type.Integer(),
});
SCHEMA_EOF
fi

# ── plugins/<name>.ts ─────────────────────────────────────────────────────────
if check_exists "$PLUGIN_FILE"; then
  info "Writing $PLUGIN_FILE"
  cat > "$PLUGIN_FILE" <<PLUGIN_EOF
import fp from 'fastify-plugin';
import type { FastifyPluginAsync } from 'fastify';

// Extend FastifyInstance to add ${PLUGIN_NAME_PASCAL}Service
declare module 'fastify' {
  interface FastifyInstance {
    ${PLUGIN_NAME_KEBAB//-/}Service: ${PLUGIN_NAME_PASCAL}Service;
  }
}

export interface ${PLUGIN_NAME_PASCAL}Service {
  findAll(page: number, limit: number): Promise<{ items: unknown[]; total: number }>;
  findById(id: string): Promise<unknown>;
  create(data: Record<string, unknown>): Promise<unknown>;
  update(id: string, data: Record<string, unknown>): Promise<unknown>;
  delete(id: string): Promise<void>;
}

const ${PLUGIN_NAME_KEBAB//-/}Plugin: FastifyPluginAsync = async (fastify) => {
  // Replace with your actual service implementation or inject via fp() dependencies.
  const service: ${PLUGIN_NAME_PASCAL}Service = {
    async findAll(page, limit) {
      // TODO: implement with fastify.db or PrismaService
      return { items: [], total: 0 };
    },
    async findById(id) {
      // TODO: implement
      return null;
    },
    async create(data) {
      // TODO: implement
      return { id: crypto.randomUUID(), ...data, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    },
    async update(id, data) {
      // TODO: implement
      return { id, ...data, updatedAt: new Date().toISOString() };
    },
    async delete(id) {
      // TODO: implement
    },
  };

  fastify.decorate('${PLUGIN_NAME_KEBAB//-/}Service', service);
};

export default fp(${PLUGIN_NAME_KEBAB//-/}Plugin, {
  name: '${PLUGIN_NAME_KEBAB}',
  dependencies: [], // add 'db', 'config' etc. as needed
});
PLUGIN_EOF
fi

# ── routes/<name>.ts ──────────────────────────────────────────────────────────
if check_exists "$ROUTES_FILE"; then
  info "Writing $ROUTES_FILE"
  cat > "$ROUTES_FILE" <<ROUTES_EOF
import { type FastifyPluginAsyncTypebox } from '@fastify/type-provider-typebox';
import fp from 'fastify-plugin';
import createHttpError from '@fastify/error';
import {
  ${PLUGIN_NAME_PASCAL}Response,
  ${PLUGIN_NAME_PASCAL}ListResponse,
  ${PLUGIN_NAME_PASCAL}Params,
  Create${PLUGIN_NAME_PASCAL}Body,
  Update${PLUGIN_NAME_PASCAL}Body,
  List${PLUGIN_NAME_PASCAL}Query,
} from '../schemas/${PLUGIN_NAME_KEBAB}.js';

const NotFoundError = createHttpError('NOT_FOUND', '%s not found', 404);

const ${PLUGIN_NAME_KEBAB//-/}Routes: FastifyPluginAsyncTypebox = async (fastify) => {
  const svc = fastify.${PLUGIN_NAME_KEBAB//-/}Service;
  const log = fastify.log.child({ plugin: '${PLUGIN_NAME_KEBAB}' });

  // ── GET /  — list ─────────────────────────────────────────────────────────
  fastify.get('/', {
    schema: {
      querystring: List${PLUGIN_NAME_PASCAL}Query,
      response: { 200: ${PLUGIN_NAME_PASCAL}ListResponse },
    },
  }, async (request, reply) => {
    const { page = 1, limit = 20 } = request.query;
    const result = await svc.findAll(page, limit);
    return reply.send({ ...result, page, limit });
  });

  // ── GET /:id — get one ────────────────────────────────────────────────────
  fastify.get('/:id', {
    schema: {
      params: ${PLUGIN_NAME_PASCAL}Params,
      response: { 200: ${PLUGIN_NAME_PASCAL}Response },
    },
  }, async (request, reply) => {
    const item = await svc.findById(request.params.id);
    if (!item) throw new NotFoundError('${PLUGIN_NAME_PASCAL}');
    return reply.send(item);
  });

  // ── POST / — create ───────────────────────────────────────────────────────
  fastify.post('/', {
    schema: {
      body: Create${PLUGIN_NAME_PASCAL}Body,
      response: { 201: ${PLUGIN_NAME_PASCAL}Response },
    },
  }, async (request, reply) => {
    log.info({ body: request.body }, 'creating ${PLUGIN_NAME_KEBAB}');
    const item = await svc.create(request.body as Record<string, unknown>);
    return reply.code(201).send(item);
  });

  // ── PATCH /:id — update ───────────────────────────────────────────────────
  fastify.patch('/:id', {
    schema: {
      params: ${PLUGIN_NAME_PASCAL}Params,
      body: Update${PLUGIN_NAME_PASCAL}Body,
      response: { 200: ${PLUGIN_NAME_PASCAL}Response },
    },
  }, async (request, reply) => {
    const item = await svc.findById(request.params.id);
    if (!item) throw new NotFoundError('${PLUGIN_NAME_PASCAL}');
    const updated = await svc.update(request.params.id, request.body as Record<string, unknown>);
    return reply.send(updated);
  });

  // ── DELETE /:id — delete ──────────────────────────────────────────────────
  fastify.delete('/:id', {
    schema: {
      params: ${PLUGIN_NAME_PASCAL}Params,
      response: { 204: { type: 'null' } },
    },
  }, async (request, reply) => {
    const item = await svc.findById(request.params.id);
    if (!item) throw new NotFoundError('${PLUGIN_NAME_PASCAL}');
    await svc.delete(request.params.id);
    return reply.code(204).send();
  });
};

export default fp(${PLUGIN_NAME_KEBAB//-/}Routes, { name: '${PLUGIN_NAME_KEBAB}-routes', dependencies: ['${PLUGIN_NAME_KEBAB}'] });
ROUTES_EOF
fi

# ── routes/<name>.test.ts ─────────────────────────────────────────────────────
if check_exists "$TEST_FILE"; then
  info "Writing $TEST_FILE"
  cat > "$TEST_FILE" <<TEST_EOF
import { describe, it, before, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import Fastify from 'fastify';
import ${PLUGIN_NAME_KEBAB//-/}Plugin, { type ${PLUGIN_NAME_PASCAL}Service } from '../plugins/${PLUGIN_NAME_KEBAB}.js';
import ${PLUGIN_NAME_KEBAB//-/}Routes from './${PLUGIN_NAME_KEBAB}.js';

function buildTestApp(overrides: Partial<${PLUGIN_NAME_PASCAL}Service> = {}) {
  const app = Fastify({ logger: false });

  const mockService: ${PLUGIN_NAME_PASCAL}Service = {
    findAll: mock.fn(async () => ({ items: [], total: 0 })),
    findById: mock.fn(async () => null),
    create: mock.fn(async (data) => ({ id: 'test-uuid', ...data, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() })),
    update: mock.fn(async (id, data) => ({ id, ...data, updatedAt: new Date().toISOString() })),
    delete: mock.fn(async () => undefined),
    ...overrides,
  };

  // Override the decorated service after plugin registers it
  app.register(${PLUGIN_NAME_KEBAB//-/}Plugin);
  app.addHook('onReady', async () => {
    (app as unknown as { ${PLUGIN_NAME_KEBAB//-/}Service: ${PLUGIN_NAME_PASCAL}Service }).${PLUGIN_NAME_KEBAB//-/}Service = mockService;
  });

  app.register(${PLUGIN_NAME_KEBAB//-/}Routes, { prefix: '/${PLUGIN_NAME_KEBAB}' });

  return { app, mockService };
}

describe('${PLUGIN_NAME_PASCAL} routes', () => {
  describe('GET /${PLUGIN_NAME_KEBAB}', () => {
    it('returns 200 with empty list when no items', async () => {
      const { app } = buildTestApp();
      await app.ready();

      const res = await app.inject({ method: 'GET', url: '/${PLUGIN_NAME_KEBAB}' });
      assert.equal(res.statusCode, 200);
      const body = res.json();
      assert.deepEqual(body.items, []);
      assert.equal(body.total, 0);
    });
  });

  describe('GET /${PLUGIN_NAME_KEBAB}/:id', () => {
    it('returns 404 when item does not exist', async () => {
      const { app } = buildTestApp({ findById: mock.fn(async () => null) });
      await app.ready();

      const res = await app.inject({
        method: 'GET',
        url: \`/${PLUGIN_NAME_KEBAB}/\${crypto.randomUUID()}\`,
      });
      assert.equal(res.statusCode, 404);
    });

    it('returns 200 with item when found', async () => {
      const item = { id: 'abc-123', name: 'test', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      const { app } = buildTestApp({ findById: mock.fn(async () => item) });
      await app.ready();

      const res = await app.inject({ method: 'GET', url: '/${PLUGIN_NAME_KEBAB}/abc-123' });
      assert.equal(res.statusCode, 200);
      assert.deepEqual(res.json(), item);
    });
  });

  describe('POST /${PLUGIN_NAME_KEBAB}', () => {
    it('returns 400 when name is missing', async () => {
      const { app } = buildTestApp();
      await app.ready();

      const res = await app.inject({
        method: 'POST',
        url: '/${PLUGIN_NAME_KEBAB}',
        payload: {},
      });
      assert.equal(res.statusCode, 400);
    });

    it('returns 201 with created item', async () => {
      const { app } = buildTestApp();
      await app.ready();

      const res = await app.inject({
        method: 'POST',
        url: '/${PLUGIN_NAME_KEBAB}',
        payload: { name: 'My ${PLUGIN_NAME_PASCAL}' },
      });
      assert.equal(res.statusCode, 201);
      assert.ok(res.json().id);
    });
  });
});
TEST_EOF
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "Scaffold complete for plugin: ${PLUGIN_NAME_KEBAB}"
echo ""
echo "  Files created:"
echo "    $SCHEMAS_FILE"
echo "    $PLUGIN_FILE"
echo "    $ROUTES_FILE"
echo "    $TEST_FILE"
echo ""
echo "  Next steps:"
echo "    1. Register the plugin in your app.ts:"
echo "       await app.register(import('./${PLUGIN_FILE}'));"
echo "       await app.register(import('./${ROUTES_FILE}'), { prefix: '/api/v1/${PLUGIN_NAME_KEBAB}' });"
echo "    2. Implement service methods in $PLUGIN_FILE"
echo "    3. Run tests: node --test $TEST_FILE"
