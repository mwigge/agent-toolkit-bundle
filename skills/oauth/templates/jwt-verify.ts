/**
 * jwt-verify.ts — JWT access token verification utility using the `jose` library.
 *
 * Verifies:
 *   - Signature against keys fetched from the JWKS URI
 *   - Algorithm (RS256 or ES256 only — HS256 rejected)
 *   - Expiry (exp)
 *   - Not-before (nbf)
 *   - Issuer (iss)
 *   - Audience (aud)
 *
 * Dependencies:
 *   pnpm add jose
 *   pnpm add -D @types/node
 *
 * Usage:
 *   import { verifyAccessToken, AuthError } from "./jwt-verify.js";
 *
 *   try {
 *     const payload = await verifyAccessToken(token, {
 *       jwksUri: "https://auth.example.com/.well-known/jwks.json",
 *       issuer: "https://auth.example.com",
 *       audience: "chaos-platform-api",
 *     });
 *     console.log(payload.sub); // user ID
 *   } catch (err) {
 *     if (err instanceof AuthError) {
 *       reply.code(401).send({ error: err.message, code: err.code });
 *     }
 *   }
 */

import { createRemoteJWKSet, jwtVerify, errors as joseErrors } from "jose";
import type { JWTPayload } from "jose";

// ─── Error type ───────────────────────────────────────────────────────────────

export type AuthErrorCode =
  | "TOKEN_EXPIRED"
  | "TOKEN_NOT_YET_VALID"
  | "INVALID_SIGNATURE"
  | "INVALID_ISSUER"
  | "INVALID_AUDIENCE"
  | "INVALID_ALGORITHM"
  | "MISSING_CLAIM"
  | "MALFORMED_TOKEN"
  | "JWKS_FETCH_FAILED";

export class AuthError extends Error {
  readonly code: AuthErrorCode;

  constructor(message: string, code: AuthErrorCode) {
    super(message);
    this.name = "AuthError";
    this.code = code;
  }
}

// ─── Token payload type ───────────────────────────────────────────────────────

export interface TokenPayload extends JWTPayload {
  /** Subject — the user ID (required) */
  sub: string;
  /** Issuer — the authorization server URL */
  iss: string;
  /** Audience — the resource server identifier */
  aud: string | string[];
  /** Expiry — Unix timestamp */
  exp: number;
  /** Issued at — Unix timestamp */
  iat: number;
  /** JWT ID — unique token identifier */
  jti?: string;
  /** OAuth scopes, space-separated string */
  scope?: string;
  /** OAuth scopes, array form (some servers use this instead of scope) */
  scp?: string[];
  /** GitHub login or similar user identifier */
  login?: string;
  /** User's email address (may be null) */
  email?: string | null;
}

// ─── Verification options ─────────────────────────────────────────────────────

export interface VerifyOptions {
  /** JWKS endpoint URI, e.g. https://auth.example.com/.well-known/jwks.json */
  jwksUri: string;
  /** Expected issuer — must match the 'iss' claim exactly */
  issuer: string;
  /** Expected audience — must be present in the 'aud' claim */
  audience: string;
  /**
   * Maximum time in seconds that the token can be in the future to account for clock skew.
   * Defaults to 30 seconds.
   */
  clockSkewSeconds?: number;
}

// ─── JWKS cache ───────────────────────────────────────────────────────────────

// Cache JWKS fetchers keyed by URI to avoid creating a new one per request.
// The `createRemoteJWKSet` function already handles key caching and rotation internally.
const jwksFetcherCache = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

function getJwksFetcher(uri: string): ReturnType<typeof createRemoteJWKSet> {
  const cached = jwksFetcherCache.get(uri);
  if (cached) return cached;

  const fetcher = createRemoteJWKSet(new URL(uri), {
    // Cache keys for 10 minutes; refresh when an unknown `kid` is encountered
    cacheMaxAge: 10 * 60 * 1000,
    // Allow up to 1 key refresh per 30 seconds per JWKS URI to prevent hammering the AS
    cooldownDuration: 30 * 1000,
  });
  jwksFetcherCache.set(uri, fetcher);
  return fetcher;
}

// ─── Main verification function ───────────────────────────────────────────────

/**
 * Verifies an access token and returns the decoded, validated payload.
 *
 * Performs full verification: signature, algorithm, expiry, nbf, iss, aud.
 * Rejects HS256 and `alg: none` regardless of what the token header claims.
 *
 * @param token - Raw JWT string (without "Bearer " prefix)
 * @param options - Verification options
 * @returns Verified and typed token payload
 * @throws {AuthError} If verification fails for any reason
 *
 * @example
 * const payload = await verifyAccessToken(
 *   request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "",
 *   {
 *     jwksUri: process.env.JWKS_URI!,
 *     issuer: process.env.JWT_ISSUER!,
 *     audience: "chaos-platform-api",
 *   }
 * );
 */
export async function verifyAccessToken(
  token: string,
  options: VerifyOptions,
): Promise<TokenPayload> {
  const { jwksUri, issuer, audience, clockSkewSeconds = 30 } = options;

  if (!token || token.trim() === "") {
    throw new AuthError("Access token is missing or empty", "MALFORMED_TOKEN");
  }

  // Reject HS256 and alg:none before attempting verification.
  // We check the unverified header to short-circuit on weak algorithms.
  const headerPart = token.split(".")[0];
  if (headerPart) {
    try {
      const padding = 4 - (headerPart.length % 4);
      const padded = padding !== 4 ? headerPart + "=".repeat(padding) : headerPart;
      const header = JSON.parse(Buffer.from(padded, "base64url").toString("utf-8")) as {
        alg?: string;
      };

      if (header.alg === "none") {
        throw new AuthError(
          "Token uses algorithm 'none' — signature verification is disabled. Token rejected.",
          "INVALID_ALGORITHM",
        );
      }

      if (header.alg === "HS256" || header.alg === "HS384" || header.alg === "HS512") {
        throw new AuthError(
          `Token uses symmetric algorithm ${header.alg}. Only RS256, RS384, RS512, ES256, ES384, ES512 are accepted.`,
          "INVALID_ALGORITHM",
        );
      }
    } catch (err) {
      if (err instanceof AuthError) throw err;
      // If we cannot parse the header, let jwtVerify produce a cleaner error
    }
  }

  const jwks = getJwksFetcher(jwksUri);

  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer,
      audience,
      clockTolerance: clockSkewSeconds,
      algorithms: ["RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "PS256", "PS384", "PS512"],
    });

    // Verify mandatory claims that jose does not check automatically
    if (!payload.sub) {
      throw new AuthError("Token is missing the 'sub' (subject) claim", "MISSING_CLAIM");
    }

    return payload as TokenPayload;
  } catch (err) {
    if (err instanceof AuthError) throw err;

    if (err instanceof joseErrors.JWTExpired) {
      throw new AuthError("Access token has expired", "TOKEN_EXPIRED");
    }
    if (err instanceof joseErrors.JWTClaimValidationFailed) {
      if (err.claim === "iss") throw new AuthError(`Invalid issuer: ${err.reason}`, "INVALID_ISSUER");
      if (err.claim === "aud") throw new AuthError(`Invalid audience: ${err.reason}`, "INVALID_AUDIENCE");
      if (err.claim === "nbf") throw new AuthError("Token is not yet valid", "TOKEN_NOT_YET_VALID");
      throw new AuthError(`Token claim validation failed (${err.claim}): ${err.reason}`, "MISSING_CLAIM");
    }
    if (err instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new AuthError("Token signature verification failed", "INVALID_SIGNATURE");
    }
    if (err instanceof joseErrors.JWSInvalid || err instanceof joseErrors.JWTInvalid) {
      throw new AuthError(`Malformed token: ${(err as Error).message}`, "MALFORMED_TOKEN");
    }
    if (err instanceof joseErrors.JWKSNoMatchingKey) {
      throw new AuthError("No matching key found in JWKS — key may have been rotated", "INVALID_SIGNATURE");
    }
    if ((err as Error).message?.includes("fetch") || (err as Error).message?.includes("ECONNREFUSED")) {
      throw new AuthError(`Failed to fetch JWKS from ${jwksUri}`, "JWKS_FETCH_FAILED");
    }

    // Re-throw unknown errors as a generic auth failure to avoid leaking internals
    throw new AuthError("Token verification failed", "INVALID_SIGNATURE");
  }
}

// ─── Scope utilities ──────────────────────────────────────────────────────────

/**
 * Returns the list of scopes from a verified token payload.
 *
 * Handles both `scope` (space-separated string) and `scp` (array) formats.
 */
export function extractScopes(payload: TokenPayload): string[] {
  if (Array.isArray(payload.scp)) return payload.scp;
  if (typeof payload.scope === "string") return payload.scope.split(" ").filter(Boolean);
  return [];
}

/**
 * Checks whether the token payload includes the required scope.
 *
 * @param payload - Verified token payload
 * @param requiredScope - The scope string to check for (e.g. "write:experiments")
 * @throws {AuthError} If the required scope is not present
 */
export function requireScope(payload: TokenPayload, requiredScope: string): void {
  const scopes = extractScopes(payload);
  if (!scopes.includes(requiredScope)) {
    throw new AuthError(
      `Insufficient scope. Required: ${requiredScope}. Got: ${scopes.join(", ") || "(none)"}`,
      "MISSING_CLAIM",
    );
  }
}

// ─── Fastify preHandler factory ───────────────────────────────────────────────

import type { FastifyRequest, FastifyReply } from "fastify";

/**
 * Creates a Fastify preHandler that verifies the Bearer token in the Authorization header.
 * Attaches the verified payload to `request.user`.
 *
 * @example
 * fastify.get(
 *   "/experiments",
 *   { preHandler: createAuthPreHandler(verifyOptions) },
 *   async (request) => {
 *     const { sub } = request.user;   // typed as TokenPayload
 *     // ...
 *   }
 * );
 */
export function createAuthPreHandler(options: VerifyOptions) {
  return async function authPreHandler(
    request: FastifyRequest & { user?: TokenPayload },
    reply: FastifyReply,
  ): Promise<void> {
    const authHeader = request.headers.authorization;
    if (!authHeader?.toLowerCase().startsWith("bearer ")) {
      return reply.code(401).send({
        error: "Unauthorised",
        message: "Authorization: Bearer <token> header is required",
      });
    }

    const token = authHeader.slice(7).trim();

    try {
      request.user = await verifyAccessToken(token, options);
    } catch (err) {
      if (err instanceof AuthError) {
        const statusCode = err.code === "TOKEN_EXPIRED" ? 401 : 401;
        return reply.code(statusCode).send({
          error: "Unauthorised",
          code: err.code,
          message: err.message,
        });
      }
      throw err; // Let Fastify's error handler deal with unexpected errors
    }
  };
}
