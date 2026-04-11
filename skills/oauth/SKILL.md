---
name: oauth
description: OAuth 2.1 and OpenID Connect patterns: authorization code with PKCE, token handling, refresh flows, JWT validation, and session management. Use when implementing authentication.
---

# Skill: OAuth 2.1 and JWT Authentication

## OAuth 2.1 (RFC 9207)

OAuth 2.1 consolidates OAuth 2.0 best current practices into a single specification. Key changes from 2.0:

| Change | Detail |
|--------|--------|
| PKCE is mandatory for all public clients | Protects against authorisation code interception attacks |
| Implicit flow removed | Was vulnerable to token leakage via URL fragments and browser history |
| Resource Owner Password Credentials (ROPC) flow removed | Credentials go directly to the client — defeats the purpose of delegated auth |
| `redirect_uri` exact matching required | Prevents open redirect attacks |
| Refresh tokens for public clients must be sender-constrained or rotate | Limits the blast radius of a stolen refresh token |

---

## PKCE Flow (RFC 7636)

PKCE (Proof Key for Code Exchange) must be used for all public clients (SPAs, mobile apps) and is recommended for confidential clients.

### Step-by-step

```
Client                                  Authorization Server
  │                                            │
  │  1. Generate code_verifier                 │
  │     (cryptographically random, 43–128 chars ASCII)
  │                                            │
  │  2. code_challenge = BASE64URL(SHA256(code_verifier))
  │  3. state = random string (CSRF protection)
  │  4. nonce = random string (replay attack protection)
  │                                            │
  │──── GET /authorize ──────────────────────>│
  │     ?response_type=code                   │
  │     &client_id=...                        │
  │     &redirect_uri=... (exact match)       │
  │     &scope=read:metrics openid            │
  │     &code_challenge=<hash>                │
  │     &code_challenge_method=S256           │
  │     &state=<random>                       │
  │     &nonce=<random>                       │
  │                                            │
  │<─── 302 redirect to redirect_uri ─────────│
  │     ?code=<authz_code>                    │
  │     &state=<echo>                         │
  │                                            │
  │  5. Verify state matches stored state      │
  │                                            │
  │──── POST /token ─────────────────────────>│
  │     grant_type=authorization_code         │
  │     &code=<authz_code>                    │
  │     &redirect_uri=... (must match exactly)│
  │     &code_verifier=<original verifier>    │
  │     &client_id=...                        │
  │                                            │
  │<─── 200 OK ───────────────────────────────│
  │     {access_token, refresh_token, id_token}
```

### Code verifier requirements

```python
import secrets, base64, hashlib

# Generate a cryptographically random verifier (43–128 unreserved ASCII chars)
code_verifier = secrets.token_urlsafe(96)  # 128 chars base64url

# Derive the challenge: S256 method (required; plain is not acceptable)
digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
code_challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
```

### State parameter

- Generate a cryptographically random state value for every authorisation request
- Store in session (server-side) or `sessionStorage` (browser) — never `localStorage`
- Verify on callback: if state does not match, abort and display an error
- State prevents CSRF attacks against the OAuth callback

---

## JWT Structure and Verification (RFC 7519)

A JWT is: `BASE64URL(header).BASE64URL(payload).signature`

### Header

```json
{
  "alg": "RS256",   // MUST use RS256 or ES256 — never HS256 for server verification
  "typ": "JWT",
  "kid": "2026-04-key-1"   // Key ID — used to look up the public key from JWKS endpoint
}
```

### Payload — mandatory claims to verify

| Claim | Description | Verification |
|-------|-------------|-------------|
| `exp` | Expiry time (Unix timestamp) | Current time must be before `exp`; reject if expired |
| `nbf` | Not-before time | Current time must be after `nbf`; reject if in future |
| `iss` | Issuer | Must match your expected issuer URL exactly |
| `aud` | Audience | Must contain your client ID / resource server identifier |
| `sub` | Subject (user ID) | Present and non-empty |
| `jti` | JWT ID | Optional but required if implementing token revocation |

### Why not HS256

- HS256 uses a symmetric key — the same secret signs and verifies
- If your client receives HS256 tokens, an attacker who knows your verification key can forge tokens
- RS256 (RSA) and ES256 (ECDSA P-256) use asymmetric keys: the server signs with a private key, clients verify with the public key (available from the JWKS endpoint)
- Never accept `alg: none` — this disables signature verification entirely

### JWKS endpoint flow

```typescript
// Client fetches public keys from the JWKS endpoint and caches them
// keyed by kid. On verification failure with "unknown kid", refresh cache once.
GET /.well-known/jwks.json
→ { "keys": [{ "kty": "RSA", "kid": "2026-04-key-1", "n": "...", "e": "..." }] }
```

---

## Token Storage

| Token type | Storage location | Rationale |
|-----------|-----------------|-----------|
| Access token | JavaScript memory (variable) | Short-lived; memory is not persisted across page loads; not accessible to XSS via `document.cookie` or `localStorage` |
| Refresh token | `httpOnly` cookie with `Secure`, `SameSite=Strict` | `httpOnly` prevents JavaScript access; `Secure` requires HTTPS; `SameSite=Strict` prevents CSRF |
| ID token | Memory (for claims) or discard after extraction | Do not store raw ID token; extract needed claims |

**Never store tokens in `localStorage` or `sessionStorage`** — both are accessible to any JavaScript on the page and thus vulnerable to XSS.

---

## Scope Design

- **Least privilege**: request only the scopes needed for the current operation
- **Resource-based scopes**: `read:metrics`, `write:experiments`, `admin:users` — not generic `api:all`
- **Audience restriction**: access tokens must include an `aud` claim identifying the target resource server
- **Scope documentation**: document all scopes in your OpenAPI spec; each scope maps to specific endpoints

Example scope taxonomy for a chaos platform:

```
read:experiments      — list and view experiments
write:experiments     — create and update experiments
execute:experiments   — trigger experiment runs
read:metrics          — read resilience scores and SLO data
admin:platform        — manage users, orgs, and platform config
```

---

## Fastify Integration

### @fastify/oauth2

Plugin for the authorisation code flow with PKCE:

```typescript
import oauth2Plugin from "@fastify/oauth2";
fastify.register(oauth2Plugin, {
  name: "githubOAuth2",
  scope: ["read:user", "user:email"],
  credentials: {
    client: { id: process.env.GITHUB_CLIENT_ID!, secret: process.env.GITHUB_CLIENT_SECRET! },
    auth: oauth2Plugin.GITHUB_CONFIGURATION,
  },
  startRedirectPath: "/auth/github",
  callbackUri: "https://app.example.com/auth/github/callback",
  pkce: "S256",
  generateStateFunction: () => crypto.randomUUID(),
  checkStateFunction: (returnedState, storedState, done) => {
    if (returnedState !== storedState) return done(new Error("State mismatch — possible CSRF"));
    done();
  },
});
```

### @fastify/jwt

Plugin for verifying JWTs in API requests:

```typescript
import jwtPlugin from "@fastify/jwt";
fastify.register(jwtPlugin, {
  secret: { public: publicKey },  // RS256 / ES256 — never a symmetric secret here
  verify: { algorithms: ["RS256"], audience: "chaos-platform-api", issuer: process.env.JWT_ISSUER! },
});

// Protect routes with a preHandler
fastify.addHook("preHandler", async (request, reply) => {
  try {
    await request.jwtVerify();
  } catch {
    reply.code(401).send({ error: "Unauthorised" });
  }
});
```

---

## Common Vulnerabilities

| Vulnerability | Description | Mitigation |
|--------------|-------------|----------|
| Open redirect in `redirect_uri` | Attacker registers a URI that redirects to their server | Enforce exact URI matching; reject wildcards or pattern matching |
| CSRF via missing `state` | Attacker tricks user's browser into completing an OAuth flow | Always generate and verify a `state` parameter |
| Token leakage via `Referer` header | Tokens in URL fragments end up in Referer headers on navigation | Use PKCE; use `state` in POST body, not URL; use `Referrer-Policy: no-referrer` |
| Mix-up attacks | Client receives tokens from a different AS than intended | Bind the authorisation request to a specific AS; verify `iss` claim |
| `alg: none` attack | Attacker strips signature and sets alg to none | Hard-code the expected algorithm; never read `alg` from the token header |
| Stolen refresh token | Attacker reuses an old refresh token | Implement refresh token rotation with reuse detection |
| JWT without `aud` check | Token intended for service A is accepted by service B | Always verify `aud` matches the current service's identifier |

---

## Token Introspection vs Local JWT Verification

| Approach | Pros | Cons |
|----------|------|------|
| **Local JWT verification** | No network call; fast; works offline; no dependency on auth server | Cannot detect revoked tokens until `exp`; requires JWKS cache refresh on key rotation |
| **Token introspection (RFC 7662)** | Detects revoked tokens immediately; always authoritative | Network call on every request; auth server is on the hot path; higher latency |

**Recommendation**: use local JWT verification for normal API calls with short-lived access tokens (5–15 min `exp`). Use token introspection for high-value operations (admin actions, financial transactions) where immediate revocation matters.

---

## Refresh Token Rotation

On every refresh token use:

1. Issue a new access token
2. Issue a new refresh token
3. Invalidate the used refresh token immediately
4. Store a record of the old refresh token (for reuse detection)

**Reuse detection**: if a refresh token that was already used is presented again, this indicates the token was stolen. Revoke the entire token family (all tokens derived from the original grant).

```
Initial grant:
  RT1 → (refresh) → AT2 + RT2
  RT2 → (refresh) → AT3 + RT3
  RT1 → (presented again) → REUSE DETECTED → revoke RT1, RT2, RT3, all active sessions
```
