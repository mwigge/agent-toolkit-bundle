---
name: nextjs
description: MUST be used for Next.js tasks. Covers the App Router, React Server Components, Server Actions, data fetching and caching, rendering strategies (SSG/SSR/ISR/streaming), routing conventions, and deployment. Load for any Next.js, App Router, `app/` directory, server component, or `next/*` work. Default to the App Router for new work.
---

# Next.js Best Practices

Use this skill as an instruction set. Default to the **App Router** (`app/` directory) for all new work; treat the Pages Router (`pages/`) as legacy. For general React/hooks/component guidance load `/react` alongside this.

## Mental Model: Server Components by Default

In the App Router, every component is a **React Server Component (RSC)** unless you opt into the client with `"use client"`. This is the single most important thing to internalise:

- **Server Components** run only on the server. They can be `async`, `await` data directly, read secrets/env, and access the database — their code never ships to the browser. They cannot use state, effects, event handlers, or browser APIs.
- **Client Components** (`"use client"` at the top of the file) run on server (for SSR) and client. They can use `useState`, `useEffect`, event handlers, and browser APIs — but their code ships to the browser.

**Push `"use client"` to the leaves.** Keep pages and layouts as server components; make only the small interactive pieces (a form, a toggle, a chart) client components. Server components can *render* client components; client components can only receive server components as `children`/props, not import them.

## 1) Routing (App Router file conventions)

Routing is defined by folders under `app/`. Special files:

| File | Role |
|------|------|
| `page.tsx` | The route's UI (makes the segment publicly routable) |
| `layout.tsx` | Shared shell wrapping children; persists across navigation; root layout is required |
| `loading.tsx` | Suspense fallback shown while the segment loads (enables streaming) |
| `error.tsx` | Error boundary for the segment (must be a client component) |
| `not-found.tsx` | UI for `notFound()` and unmatched routes |
| `route.ts` | Route Handler — an API endpoint (`GET`, `POST`, …) |
| `template.tsx` | Like layout but remounts on navigation |

- Dynamic segments: `app/blog/[slug]/page.tsx` -> `params.slug`. Catch-all: `[...slug]`. Optional: `[[...slug]]`.
- **Route Groups** `(marketing)` organise folders without affecting the URL. **Private folders** `_components` are excluded from routing.
- **Parallel** `@slot` and **Intercepting** `(.)` routes handle dashboards and modal-over-page patterns.
- Navigate with `<Link href>` (prefetches by default) and the `useRouter()` hook from `next/navigation` (not `next/router`).

## 2) Data Fetching

**Fetch in Server Components — just `await`.** No `getServerSideProps`/`getStaticProps` in the App Router.

```tsx
// app/products/page.tsx  (Server Component)
export default async function ProductsPage() {
  const res = await fetch("https://api.example.com/products", {
    next: { revalidate: 3600 },   // ISR: cache, revalidate hourly
  });
  const products = await res.json();
  return <ProductList products={products} />;
}
```

- The App Router **deduplicates** identical `fetch` calls within one render, so fetch data where it is used instead of prop-drilling.
- `cache: "force-cache"` (default in older versions) caches indefinitely; `cache: "no-store"` opts out (dynamic); `next: { revalidate: N }` sets ISR. In Next 15+ fetches are **uncached by default** — set caching explicitly.
- `next: { tags: [...] }` enables on-demand invalidation via `revalidateTag()`.
- For client-side/interactive data (mutations, polling, infinite scroll), use React Query or SWR inside client components.
- Fetch in parallel with `Promise.all` to avoid request waterfalls; use `<Suspense>` + `loading.tsx` to stream slow parts without blocking the whole page.

## 3) Mutations with Server Actions

Server Actions are `async` functions marked `"use server"` that run on the server and can be called from client or server components — no hand-written API route needed for form/mutations.

```tsx
// app/actions.ts
"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

export async function createPost(formData: FormData) {
  const title = String(formData.get("title"));
  await db.post.create({ data: { title } });
  revalidatePath("/posts");        // refresh the cached list
  redirect("/posts");
}
```

```tsx
// Used directly as a form action (progressive enhancement — works without JS)
<form action={createPost}>
  <input name="title" />
  <button type="submit">Create</button>
</form>
```

- **Always validate and authorise inside the action** — it is a public server endpoint. Treat every argument as untrusted; check the session/permissions before writing.
- Use `useActionState` (React 19) / `useFormStatus` for pending and error UI.
- Call `revalidatePath` / `revalidateTag` after a mutation so cached reads reflect the change.

## 4) Rendering Strategies

| Strategy | How to get it | Use for |
|----------|---------------|---------|
| **Static (SSG)** | Default when no dynamic data/APIs used | Marketing, docs, content that rarely changes |
| **ISR** | `fetch(..., { next: { revalidate: N } })` or `export const revalidate = N` | Content that updates periodically |
| **Dynamic (SSR)** | `cache: "no-store"`, `cookies()`/`headers()`, or `export const dynamic = "force-dynamic"` | Per-request/personalised pages |
| **Streaming** | `<Suspense>` + `loading.tsx` | Show shell fast, stream slow data in |
| **Client (CSR)** | `"use client"` + client data lib | Highly interactive widgets |

Reading `cookies()`, `headers()`, or `searchParams` opts a route into dynamic rendering. `generateStaticParams` pre-renders dynamic routes at build time.

## 5) Project Structure & Conventions

- Co-locate route-only components in `_components` inside the segment; put shared UI in a top-level `components/`; shared logic in `lib/`.
- `app/api/*/route.ts` for API endpoints; return `Response`/`NextResponse`. Use these for webhooks and third-party callbacks — prefer Server Actions for your own app's mutations.
- **Metadata**: export a `metadata` object or `generateMetadata()` from `layout.tsx`/`page.tsx` for SEO — no `<Head>`.
- **Images**: `next/image` (automatic resizing, lazy load, layout-shift prevention). **Fonts**: `next/font` (self-hosted, zero layout shift). **Scripts**: `next/script`.
- **Env vars**: only `NEXT_PUBLIC_*` are exposed to the browser; everything else is server-only. Never read a secret in a client component.
- **Middleware** (`middleware.ts`) runs on the edge before a request completes — use for auth redirects, rewrites, and geo/AB routing; keep it lightweight.

## 6) Deployment

- Vercel is the first-party target (zero-config, edge network, ISR, image optimisation). Self-host with `next build && next start` (Node) or `output: "standalone"` for a minimal container image.
- `output: "export"` produces a fully static site (no server features — no Server Actions, no dynamic routes without `generateStaticParams`, no image optimisation server).
- Set `revalidate`/caching deliberately for production; verify with `next build` output which routes are Static (○), Dynamic (ƒ), or ISR.

## Gotchas & Anti-Patterns

- Importing a server-only module (db client, secret) into a client component — it will either error or leak. Keep them in server components / `server-only`-guarded modules.
- `"use client"` on a top-level layout/page — it turns the whole subtree into client-rendered code and forfeits RSC benefits. Push the boundary down.
- Using `useEffect` to fetch initial page data in the App Router — fetch in the server component instead.
- Forgetting to `revalidatePath`/`revalidateTag` after a Server Action — the UI shows stale cached data.
- Not validating/authorising inside a Server Action or Route Handler — both are public endpoints.
- Using `next/router` (Pages Router) in App Router code — use `next/navigation`.
- Assuming fetches are cached — verify per Next.js version; be explicit.
