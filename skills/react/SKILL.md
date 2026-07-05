---
name: react
description: MUST be used for React tasks. Covers React 18/19 with function components and hooks, TypeScript, component and state patterns, performance (memo/useMemo/useCallback), and testing (React Testing Library + Vitest). Load for any React, JSX/TSX, hooks, or component work. ALWAYS use function components and hooks — never write new class components.
---

# React Best Practices

Use this skill as an instruction set. Default stack: **React 18/19 + function components + hooks + TypeScript (`.tsx`)**. Never write new class components. For Next.js-specific concerns (App Router, server components, data fetching, rendering) load `/nextjs`.

## Core Principles

- **Derive, don't duplicate.** Anything computable from props or existing state is not state — compute it during render. Duplicated state drifts.
- **One source of truth.** Each piece of state lives in exactly one place; lift it to the lowest common ancestor that needs it.
- **Props down, events up.** Data flows down; children signal up through callbacks. Reach for context/stores only when prop-drilling becomes painful.
- **Components are pure functions of props + state.** No side effects during render. Effects go in `useEffect`; event logic goes in handlers.
- **Small, focused components.** One responsibility each — easier to test, memoise, and reuse.

## 1) Component Design

- Function components only. Type props with an explicit `interface`/`type`; avoid `React.FC` (it complicates generics and implicit `children`).
- Destructure props in the signature. Give required props no default; give optional props a sensible default.
- Keep components presentational where possible; push data-fetching and orchestration to the edges (route/page/container).
- Prefer composition over configuration: pass `children` and render props instead of growing a dozen boolean flags.

```tsx
interface ButtonProps {
  variant?: "primary" | "ghost";
  onClick: () => void;
  children: React.ReactNode;
}

export function Button({ variant = "primary", onClick, children }: ButtonProps) {
  return <button className={variant} onClick={onClick}>{children}</button>;
}
```

## 2) Hooks — the Rules and the Core Set

**Rules of Hooks (non-negotiable):** call hooks only at the top level of a component or a custom hook — never in loops, conditions, or nested functions — and only from React functions. Enforce with `eslint-plugin-react-hooks` (`rules-of-hooks` + `exhaustive-deps`).

| Hook | Use for |
|------|---------|
| `useState` | Local component state |
| `useReducer` | Complex state with multiple sub-values or interdependent transitions |
| `useEffect` | Synchronising with external systems (subscriptions, DOM, non-React libs) |
| `useRef` | Mutable value that must not trigger re-render; DOM node access |
| `useContext` | Reading context without prop-drilling |
| `useMemo` / `useCallback` | Referential stability (see Performance) |
| `useId` | Stable SSR-safe ids for a11y attributes |

- **Custom hooks** extract reusable stateful logic. Name them `use*`; they compose other hooks and return values/handlers. This is the primary reuse mechanism in React — prefer a custom hook over a wrapper component when the logic is behaviour, not UI.
- Keep the `useEffect` dependency array complete and accurate — do not silence `exhaustive-deps`. If a dep causes loops, fix the source (memoise it, move it into the effect, or use a ref) rather than lying to the linter.

## 3) `useEffect` — Use It Less Than You Think

Most code does not need an effect. Before reaching for `useEffect`, check:

- **Transforming data for render?** Compute it during render (optionally `useMemo`) — no effect.
- **Responding to a user event?** Do it in the event handler — no effect.
- **Resetting state when a prop changes?** Prefer a `key` prop to remount, or compute during render.
- **Fetching data?** In an app framework, use its data layer (`/nextjs`, React Query/SWR). A raw fetch-in-effect needs cleanup + race-condition guarding.

Legitimate effects synchronise with something *outside* React: subscriptions, timers, manual DOM, third-party widgets. Always return a cleanup function for subscriptions/timers.

```tsx
useEffect(() => {
  const ctrl = new AbortController();
  fetch(`/api/user/${id}`, { signal: ctrl.signal })
    .then((r) => r.json())
    .then(setUser);
  return () => ctrl.abort();   // prevents setting state after unmount / stale response
}, [id]);
```

## 4) State Management — Choose the Smallest Tool

1. **Local `useState`/`useReducer`** — default for state owned by one subtree.
2. **Lift state up** — when siblings must share it.
3. **`useContext`** — for low-frequency, widely-read values (theme, auth, locale). Context re-renders all consumers on change; do not put fast-changing state in a single context.
4. **A store (Zustand, Redux Toolkit, Jotai)** — for app-wide, frequently-updated, or complex state. Prefer Zustand/Jotai for simplicity; Redux Toolkit when you need its devtools/middleware ecosystem.
5. **Server state ≠ client state.** Data from an API is server state — manage it with **React Query (TanStack Query)** or **SWR** (caching, revalidation, dedup), not by hand in `useState` + `useEffect`.

Split contexts by update frequency, and memoise the context `value` object so consumers don't re-render on every parent render.

## 5) Performance

Optimise only after measuring with the React DevTools Profiler. Premature memoisation adds complexity and its own cost.

- **`React.memo`** — skip re-render of a component when its props are shallowly equal. Only helps if the component is expensive *and* its parent re-renders often with the same props.
- **`useMemo`** — cache an expensive computation *or* stabilise a referential value (object/array) passed to a memoised child or a dependency array. Not for cheap scalars.
- **`useCallback`** — stabilise a function identity passed to a memoised child or an effect dep. `useCallback(fn, deps)` is `useMemo(() => fn, deps)`.
- **Keys**: give list items stable, unique keys from data (an id) — never the array index for reorderable/insertable lists (it corrupts state and animations).
- **Code-split** heavy or rarely-used subtrees with `React.lazy` + `<Suspense>`.
- **React Compiler** (React 19): when adopted, it auto-memoises — you then write plain code and remove most manual `useMemo`/`useCallback`. Check whether the project uses it before hand-memoising.

Common wins that beat memoisation: don't lift state higher than needed; move state down to the component that uses it; pass `children` through so the expensive subtree doesn't re-render with the stateful parent.

## 6) TypeScript

- Type props and state explicitly; let inference handle local variables.
- Events: `React.ChangeEvent<HTMLInputElement>`, `React.FormEvent`, `React.MouseEvent`. Refs: `useRef<HTMLDivElement>(null)`.
- Children: `React.ReactNode` (anything renderable) — not `JSX.Element`.
- Discriminated unions for variant props beat many optional booleans and make impossible states unrepresentable.
- Avoid `any`; use `unknown` at boundaries and narrow. No `@ts-ignore` without a justification comment.

## 7) Testing (React Testing Library + Vitest)

- **Test behaviour, not implementation.** Query by accessible role/label/text (`getByRole`, `getByLabelText`), never by class name or component internals.
- Interact via `@testing-library/user-event` (realistic events), assert on what the user sees.
- Use `findBy*` / `waitFor` for async UI; do not assert on internal state or call instance methods.
- Mock at the network boundary (MSW) rather than mocking child components.
- A component test that breaks on a refactor but not a behaviour change is testing the wrong thing.

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

test("submits the entered name", async () => {
  const onSubmit = vi.fn();
  render(<NameForm onSubmit={onSubmit} />);
  await userEvent.type(screen.getByLabelText(/name/i), "Ada");
  await userEvent.click(screen.getByRole("button", { name: /submit/i }));
  expect(onSubmit).toHaveBeenCalledWith("Ada");
});
```

## Anti-Patterns

- Class components in new code; lifecycle methods where a hook fits.
- State that mirrors props, or state derivable from other state.
- `useEffect` for data transforms, event responses, or "when X changes do Y" that belongs in a handler.
- Array index as `key` for dynamic lists.
- Mutating state directly (`state.push(...)`) — always produce new references (`setItems([...items, x])`).
- Silencing `exhaustive-deps` instead of fixing the dependency.
- Memoising everything by reflex without profiling.
- One giant context holding all app state.
