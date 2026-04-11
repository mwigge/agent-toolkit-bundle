---
name: multi-tenancy
description: Build SaaS apps that serve multiple organizations securely. Covers isolation models (shared schema, schema-per-tenant, DB-per-tenant), tenant context propagation, RLS, query scoping, and Python/TypeScript implementation patterns.
---

# Multi-Tenancy

Build SaaS apps that serve multiple organizations securely.

## When to Use This Skill

- B2B SaaS applications
- White-label platforms
- Enterprise software
- Any app serving multiple organizations

---

## Isolation Models

### 1. Shared Database, Shared Schema (Recommended for most)

```
┌─────────────────────────────────────────────────────┐
│                   Database                           │
│                                                     │
│  users: id, tenant_id, email, ...                   │
│  orders: id, tenant_id, user_id, ...                │
│  products: id, tenant_id, name, ...                 │
│                                                     │
│  All tables have tenant_id column                   │
└─────────────────────────────────────────────────────┘
```

### 2. Shared Database, Schema per Tenant

```
┌─────────────────────────────────────────────────────┐
│                   Database                           │
│                                                     │
│  tenant_acme.users                                  │
│  tenant_acme.orders                                 │
│  tenant_globex.users                                │
│  tenant_globex.orders                               │
└─────────────────────────────────────────────────────┘
```

### 3. Database per Tenant (Enterprise)

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  acme_db     │  │  globex_db   │  │  initech_db  │
│              │  │              │  │              │
│  users       │  │  users       │  │  users       │
│  orders      │  │  orders      │  │  orders      │
└──────────────┘  └──────────────┘  └──────────────┘
```

---

## Database Schema

```sql
-- Tenants table
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  plan VARCHAR(50) DEFAULT 'free',
  features TEXT[] DEFAULT '{}',
  config JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW()
);

-- Users belong to tenants via memberships
CREATE TABLE tenant_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  role VARCHAR(50) DEFAULT 'member',
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, tenant_id)
);

-- All data tables have tenant_id
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id),
  user_id UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index for tenant queries (mandatory on every tenant-scoped table)
CREATE INDEX idx_orders_tenant ON orders(tenant_id);

-- Row Level Security (belt-and-suspenders — add alongside app-level filtering)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.current_tenant')::uuid);
```

---

## Python Implementation

### Tenant Context (ContextVar — async-safe)

```python
# tenant_context.py
from contextvars import ContextVar
from dataclasses import dataclass

@dataclass
class TenantContext:
    tenant_id: str
    tenant_slug: str
    plan: str
    features: list[str]

_tenant_context: ContextVar[TenantContext | None] = ContextVar(
    "tenant_context", default=None
)

def get_tenant() -> TenantContext:
    tenant = _tenant_context.get()
    if not tenant:
        raise RuntimeError("No tenant context")
    return tenant

def set_tenant(tenant: TenantContext):
    return _tenant_context.set(tenant)
```

### FastAPI Middleware

```python
# tenant_middleware.py
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

class TenantMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        tenant_id = request.headers.get("x-tenant-id")

        if not tenant_id:
            host = request.headers.get("host", "")
            subdomain = host.split(".")[0]
            if subdomain not in ["www", "app", "api"]:
                tenant_id = subdomain

        if not tenant_id:
            raise HTTPException(400, "Tenant not specified")

        tenant = await db.tenants.find_unique(where={"id": tenant_id})
        if not tenant:
            raise HTTPException(404, "Tenant not found")

        token = set_tenant(TenantContext(
            tenant_id=tenant.id,
            tenant_slug=tenant.slug,
            plan=tenant.plan,
            features=tenant.features,
        ))
        try:
            response = await call_next(request)
            return response
        finally:
            _tenant_context.reset(token)
```

### RLS Session Variable Injection (when using PostgreSQL RLS)

```python
# Set after resolving tenant, before any query
await conn.execute(
    "SET session.organization_id = %s", [tenant_id]
)

# Safe pool reset callback (psycopg3 ConnectionPool)
def reset_connection(conn):
    conn.execute("RESET session.organization_id")
```

---

## TypeScript Implementation

### Tenant Context (AsyncLocalStorage)

```typescript
// tenant-context.ts
import { AsyncLocalStorage } from 'async_hooks';

interface TenantContext {
  tenantId: string;
  tenantSlug: string;
  plan: 'free' | 'pro' | 'enterprise';
  features: string[];
}

const tenantStorage = new AsyncLocalStorage<TenantContext>();

export function getTenant(): TenantContext {
  const tenant = tenantStorage.getStore();
  if (!tenant) throw new Error('No tenant context available');
  return tenant;
}

export function runWithTenant<T>(tenant: TenantContext, fn: () => T): T {
  return tenantStorage.run(tenant, fn);
}
```

### Tenant Middleware (Express)

```typescript
// tenant-middleware.ts
export function tenantMiddleware(options = {}) {
  const { headerName = 'x-tenant-id', subdomainExtract = true } = options;

  return async (req: Request, res: Response, next: NextFunction) => {
    let tenantId = req.headers[headerName.toLowerCase()] as string;

    if (!tenantId && subdomainExtract) {
      const subdomain = req.hostname.split('.')[0];
      if (subdomain && !['www', 'app'].includes(subdomain)) {
        tenantId = subdomain;
      }
    }

    if (!tenantId) return res.status(400).json({ error: 'Tenant not specified' });

    const tenant = await db.tenants.findUnique({ where: { id: tenantId } });
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' });

    if (req.user) {
      const membership = await db.tenantMemberships.findFirst({
        where: { userId: req.user.id, tenantId: tenant.id },
      });
      if (!membership) return res.status(403).json({ error: 'Access denied' });
      req.userRole = membership.role;
    }

    runWithTenant(
      { tenantId: tenant.id, tenantSlug: tenant.slug, plan: tenant.plan, features: tenant.features },
      () => next()
    );
  };
}
```

### Tenant-Scoped Prisma Client

```typescript
// tenant-prisma.ts
export function createTenantPrisma(prisma: PrismaClient) {
  return prisma.$extends({
    query: {
      $allModels: {
        async findMany({ args, query }) {
          args.where = { ...args.where, tenantId: getTenant().tenantId };
          return query(args);
        },
        async create({ args, query }) {
          args.data = { ...args.data, tenantId: getTenant().tenantId };
          return query(args);
        },
        async update({ args, query }) {
          args.where = { ...args.where, tenantId: getTenant().tenantId };
          return query(args);
        },
        async delete({ args, query }) {
          args.where = { ...args.where, tenantId: getTenant().tenantId };
          return query(args);
        },
      },
    },
  });
}
```

---

## Best Practices

- **Always filter by tenant_id** — never trust client-provided IDs alone
- **Use middleware** — centralise tenant resolution; never resolve in route handlers
- **Index tenant_id** — every tenant-scoped table needs `idx_<table>_tenant`
- **Add RLS as backstop** — app-level filtering + RLS = two failures required for a breach
- **Cache tenant config** — avoid repeated DB lookups per request
- **Use ContextVar / AsyncLocalStorage** — not request objects; these are async-safe
- **Per-request connections without pooling**: SET session variable is safe (no reuse risk)
- **With connection pool**: use session-mode pooling + reset callback to clear session vars

## Common Mistakes

- Forgetting tenant filter on a single query (data leak — entire tenant population exposed)
- Not validating user's membership in the requested tenant
- Hardcoding tenant-specific logic in shared code paths
- Missing index on `tenant_id` (full table scan at scale)
- Using transaction-mode PgBouncer with RLS (session variables don't persist → policy bypass)
- Allowing cross-tenant foreign key references

## Isolation Model Decision Guide

| Situation | Model |
|---|---|
| Early stage, cost-sensitive, low risk | Shared schema + app filtering |
| B2B SaaS, compliance required (GDPR, DORA) | Shared schema + app filtering + RLS |
| 10–500 tenants, per-tenant customisation | Schema-per-tenant |
| Enterprise, data residency, small customer base | Database-per-tenant |
