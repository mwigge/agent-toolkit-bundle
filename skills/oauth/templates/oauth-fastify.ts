/**
 * oauth-fastify.ts — Fastify plugin wiring @fastify/oauth2 with GitHub as the provider.
 *
 * Features:
 *   - PKCE (S256) flow via @fastify/oauth2
 *   - Secure httpOnly refresh token cookie
 *   - Access token issued as a signed JWT on successful GitHub callback
 *   - Token refresh endpoint using the stored refresh token cookie
 *
 * Dependencies:
 *   pnpm add @fastify/oauth2 @fastify/jwt @fastify/cookie fastify
 *   pnpm add -D @types/node
 *
 * Required environment variables:
 *   GITHUB_CLIENT_ID         — GitHub OAuth App client ID
 *   GITHUB_CLIENT_SECRET     — GitHub OAuth App client secret
 *   JWT_SIGNING_SECRET       — Secret for signing access JWTs (use RS256 in production)
 *   APP_BASE_URL             — e.g. https://app.example.com
 *   COOKIE_SECRET            — At least 32 random bytes (hex or base64)
 */

import type { FastifyInstance, FastifyPluginAsync, FastifyRequest, FastifyReply } from "fastify";
import fp from "fastify-plugin";
import oauthPlugin from "@fastify/oauth2";
import jwtPlugin from "@fastify/jwt";
import cookiePlugin from "@fastify/cookie";
import crypto from "node:crypto";

// ─── Types ────────────────────────────────────────────────────────────────────

interface GitHubUserResponse {
  id: number;
  login: string;
  email: string | null;
  name: string | null;
  avatar_url: string;
}

interface AccessTokenPayload {
  sub: string;            // GitHub user ID (as string)
  login: string;          // GitHub username
  email: string | null;
  iss: string;
  aud: string;
  iat: number;
  exp: number;
  jti: string;
}

// ─── Configuration ────────────────────────────────────────────────────────────

const REQUIRED_ENV_VARS = [
  "GITHUB_CLIENT_ID",
  "GITHUB_CLIENT_SECRET",
  "JWT_SIGNING_SECRET",
  "APP_BASE_URL",
  "COOKIE_SECRET",
] as const;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;     // 15 minutes
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const REFRESH_COOKIE_NAME = "__Host-refresh_token";

// ─── State store (replace with Redis / DB in production) ─────────────────────

// In production, persist state → { codeVerifier, nonce, createdAt } in Redis with
// a short TTL (5 minutes). The in-memory map below is only suitable for a single instance.
const pendingStates = new Map<string, { codeVerifier: string; nonce: string }>();

// ─── Token issuance helper ────────────────────────────────────────────────────

function issueAccessToken(
  fastify: FastifyInstance,
  user: GitHubUserResponse,
): string {
  const now = Math.floor(Date.now() / 1000);
  const payload: AccessTokenPayload = {
    sub: String(user.id),
    login: user.login,
    email: user.email,
    iss: requireEnv("APP_BASE_URL"),
    aud: "chaos-platform-api",
    iat: now,
    exp: now + ACCESS_TOKEN_TTL_SECONDS,
    jti: crypto.randomUUID(),
  };
  return fastify.jwt.sign(payload as Record<string, unknown>);
}

// ─── Plugin ───────────────────────────────────────────────────────────────────

const oauthFastifyPlugin: FastifyPluginAsync = async (fastify) => {
  // Validate environment before registering anything
  for (const varName of REQUIRED_ENV_VARS) {
    requireEnv(varName);
  }

  // Cookie plugin (needed for httpOnly refresh token)
  await fastify.register(cookiePlugin, {
    secret: requireEnv("COOKIE_SECRET"),
    parseOptions: {},
  });

  // JWT plugin — sign access tokens
  // In production, use RS256 with a private key:
  //   secret: { private: fs.readFileSync("private.pem"), public: fs.readFileSync("public.pem") }
  //   sign: { algorithm: "RS256" }
  await fastify.register(jwtPlugin, {
    secret: requireEnv("JWT_SIGNING_SECRET"),
    sign: {
      algorithm: "HS256",   // Replace with RS256 for production
      issuer: requireEnv("APP_BASE_URL"),
      audience: "chaos-platform-api",
    },
    verify: {
      algorithms: ["HS256"],
      issuer: requireEnv("APP_BASE_URL"),
      audience: "chaos-platform-api",
    },
  });

  // OAuth2 plugin — GitHub provider with PKCE
  await fastify.register(oauthPlugin, {
    name: "githubOAuth2",
    scope: ["read:user", "user:email"],
    credentials: {
      client: {
        id: requireEnv("GITHUB_CLIENT_ID"),
        secret: requireEnv("GITHUB_CLIENT_SECRET"),
      },
      auth: oauthPlugin.GITHUB_CONFIGURATION,
    },
    startRedirectPath: "/auth/github",
    callbackUri: `${requireEnv("APP_BASE_URL")}/auth/github/callback`,
    pkce: "S256",

    // Generate a cryptographically random state value; store it with the verifier
    generateStateFunction: (request: FastifyRequest) => {
      const state = crypto.randomBytes(32).toString("hex");
      const nonce = crypto.randomBytes(16).toString("hex");
      // @ts-expect-error — codeVerifier is added by the plugin at request time
      const codeVerifier: string = request.codeVerifier ?? "";
      pendingStates.set(state, { codeVerifier, nonce });
      // Expire after 5 minutes to prevent unbounded growth
      setTimeout(() => pendingStates.delete(state), 5 * 60 * 1000);
      return state;
    },

    // Verify the returned state matches what we stored
    checkStateFunction: (
      returnedState: string,
      _storedState: string,
      done: (err?: Error) => void,
    ) => {
      if (!pendingStates.has(returnedState)) {
        return done(new Error("Invalid or expired state parameter — possible CSRF attack"));
      }
      done();
    },
  });

  // ─── OAuth callback handler ────────────────────────────────────────────────

  fastify.get(
    "/auth/github/callback",
    async (request: FastifyRequest, reply: FastifyReply) => {
      const query = request.query as Record<string, string>;
      const state = query.state;

      const pending = pendingStates.get(state);
      if (!pending) {
        return reply.code(400).send({ error: "Invalid or expired state" });
      }
      pendingStates.delete(state);

      let token: Awaited<ReturnType<(typeof fastify)["githubOAuth2"]["getAccessTokenFromAuthorizationCodeFlow"]>>;
      try {
        token = await (fastify as FastifyInstance & {
          githubOAuth2: {
            getAccessTokenFromAuthorizationCodeFlow: (
              req: FastifyRequest,
            ) => Promise<{ token: { access_token: string; refresh_token?: string } }>;
          };
        }).githubOAuth2.getAccessTokenFromAuthorizationCodeFlow(request);
      } catch (err) {
        fastify.log.error({ err }, "OAuth token exchange failed");
        return reply.code(400).send({ error: "Token exchange failed" });
      }

      // Fetch GitHub user profile
      let githubUser: GitHubUserResponse;
      try {
        const userResponse = await fetch("https://api.github.com/user", {
          headers: {
            Authorization: `Bearer ${token.token.access_token}`,
            Accept: "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
          },
        });
        if (!userResponse.ok) {
          throw new Error(`GitHub API responded with ${userResponse.status}`);
        }
        githubUser = (await userResponse.json()) as GitHubUserResponse;
      } catch (err) {
        fastify.log.error({ err }, "Failed to fetch GitHub user profile");
        return reply.code(502).send({ error: "Failed to retrieve user profile" });
      }

      // Issue our own access token
      const accessToken = issueAccessToken(fastify, githubUser);

      // Set the GitHub OAuth refresh token (or our own RT) as an httpOnly cookie
      const refreshToken = token.token.refresh_token ?? crypto.randomBytes(32).toString("hex");
      reply.setCookie(REFRESH_COOKIE_NAME, refreshToken, {
        httpOnly: true,
        secure: true,
        sameSite: "strict",
        path: "/auth/refresh",  // Restrict cookie to the refresh endpoint only
        maxAge: REFRESH_TOKEN_TTL_SECONDS,
      });

      // Return the access token in the response body (client stores in memory)
      return reply.code(200).send({
        access_token: accessToken,
        token_type: "Bearer",
        expires_in: ACCESS_TOKEN_TTL_SECONDS,
      });
    },
  );

  // ─── Token refresh endpoint ────────────────────────────────────────────────

  fastify.post(
    "/auth/refresh",
    async (request: FastifyRequest, reply: FastifyReply) => {
      const refreshToken = request.cookies[REFRESH_COOKIE_NAME];
      if (!refreshToken) {
        return reply.code(401).send({ error: "No refresh token" });
      }

      // In production: look up the refresh token in the database, verify it hasn't
      // been used (rotation), verify it hasn't expired, then issue new tokens.
      // For this template: simulate a token validation step.
      const isValid = refreshToken.length >= 32; // Replace with real DB lookup
      if (!isValid) {
        reply.clearCookie(REFRESH_COOKIE_NAME, { path: "/auth/refresh" });
        return reply.code(401).send({ error: "Invalid or expired refresh token" });
      }

      // Re-fetch user or read from DB
      // For this template, decode the existing access token from the Authorization header
      let subject: string;
      try {
        const authHeader = request.headers.authorization ?? "";
        const oldToken = authHeader.replace(/^Bearer\s+/i, "");
        const decoded = fastify.jwt.decode<AccessTokenPayload>(oldToken);
        if (!decoded?.sub) throw new Error("Cannot determine subject");
        subject = decoded.sub;
      } catch {
        return reply.code(401).send({ error: "Cannot identify subject for refresh" });
      }

      // Issue new access token (minimal payload — expand with real user lookup)
      const now = Math.floor(Date.now() / 1000);
      const newAccessToken = fastify.jwt.sign({
        sub: subject,
        iss: requireEnv("APP_BASE_URL"),
        aud: "chaos-platform-api",
        iat: now,
        exp: now + ACCESS_TOKEN_TTL_SECONDS,
        jti: crypto.randomUUID(),
      });

      // Rotate the refresh token (issue new, invalidate old)
      const newRefreshToken = crypto.randomBytes(32).toString("hex");
      // TODO: CLS-XXX — persist newRefreshToken in DB, mark old token as used
      reply.setCookie(REFRESH_COOKIE_NAME, newRefreshToken, {
        httpOnly: true,
        secure: true,
        sameSite: "strict",
        path: "/auth/refresh",
        maxAge: REFRESH_TOKEN_TTL_SECONDS,
      });

      return reply.code(200).send({
        access_token: newAccessToken,
        token_type: "Bearer",
        expires_in: ACCESS_TOKEN_TTL_SECONDS,
      });
    },
  );

  // ─── Logout endpoint ───────────────────────────────────────────────────────

  fastify.post("/auth/logout", async (_request: FastifyRequest, reply: FastifyReply) => {
    // TODO: CLS-XXX — revoke refresh token in DB
    reply.clearCookie(REFRESH_COOKIE_NAME, {
      path: "/auth/refresh",
      httpOnly: true,
      secure: true,
      sameSite: "strict",
    });
    return reply.code(204).send();
  });
};

export default fp(oauthFastifyPlugin, {
  name: "oauth-fastify",
  fastify: "5.x",
});
