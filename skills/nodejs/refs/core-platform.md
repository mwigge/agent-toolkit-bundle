# Node.js (Core Platform) — Detailed Reference

**Runtime**: Node 22 LTS | **Modules**: ES Modules only | **Test runner**: node:test (built-in)

---

## 1. Node 22 LTS Essentials

### Environment & Configuration

Use `--env-file` to load environment variables from a file without `dotenv`:

```bash
node --env-file=.env src/index.js
```

Never access `process.env` directly in library code — inject config through constructor parameters or a typed config object.

### Built-in Fetch

Node 22 ships `fetch` globally. No `node-fetch` or `axios` needed for simple HTTP:

```js
const response = await fetch('https://api.example.com/data', {
  signal: AbortSignal.timeout(5000),
  headers: { 'Content-Type': 'application/json' },
});
if (!response.ok) {
  throw new HttpError(response.status, await response.text());
}
const data = await response.json();
```

### WebStreams

`ReadableStream`, `WritableStream`, `TransformStream` are available globally. Interop with Node streams via `Readable.fromWeb()` / `Readable.toWeb()`:

```js
import { Readable } from 'node:stream';

const webStream = new ReadableStream({
  async start(controller) {
    for await (const chunk of someAsyncSource()) {
      controller.enqueue(chunk);
    }
    controller.close();
  },
});

const nodeReadable = Readable.fromWeb(webStream);
```

### Built-in Test Runner (`node:test`)

No Jest, no Mocha. Use `node:test` + `node:assert`:

```js
import { describe, it, before, after, mock } from 'node:test';
import assert from 'node:assert/strict';

describe('UserService', () => {
  let service;

  before(() => {
    service = new UserService({ db: mockDb() });
  });

  it('returns user by id', async () => {
    const user = await service.findById('user-1');
    assert.deepEqual(user, { id: 'user-1', name: 'Alice' });
  });

  it('throws NotFoundError when user is missing', async () => {
    await assert.rejects(
      () => service.findById('missing'),
      { name: 'NotFoundError' }
    );
  });
});
```

Run with coverage:

```bash
node --test --experimental-test-coverage src/**/*.test.js
```

---

## 2. Event Loop Phases

The event loop processes callbacks in this strict order per iteration (tick):

```
timers          -> setTimeout / setInterval callbacks
pending I/O     -> deferred I/O callbacks from previous iteration
idle / prepare  -> internal use only
poll            -> retrieve new I/O events; execute callbacks
check           -> setImmediate callbacks
close           -> close event callbacks (socket.on('close'))
```

**Microtask queue** runs between every phase transition and after every callback:
- `process.nextTick` callbacks run first (before Promise callbacks)
- `Promise.then` / `queueMicrotask` callbacks run after nextTick queue is drained

```js
setTimeout(() => console.log('timer'), 0);
setImmediate(() => console.log('check'));
Promise.resolve().then(() => console.log('promise microtask'));
process.nextTick(() => console.log('nextTick'));

// Output order:
// nextTick
// promise microtask
// timer          (or check -- depends on poll phase timing)
// check
```

**Rule**: Never starve the event loop. Avoid synchronous loops over large data sets in the main thread. Offload to worker threads.

---

## 3. Async Patterns

### async/await

Always `await` Promises or explicitly handle them. Never fire-and-forget without an error handler:

```js
// BAD -- unhandled rejection silently swallowed
somePromise();

// GOOD -- explicitly fire-and-forget with error handling
somePromise().catch((err) => logger.error({ err }, 'background task failed'));
```

### Async Iterators

Use `for await...of` for streaming data sources. Implement `Symbol.asyncIterator` on custom sources:

```js
async function* paginate(client, query) {
  let cursor = null;
  do {
    const { items, nextCursor } = await client.query({ ...query, cursor });
    yield* items;
    cursor = nextCursor;
  } while (cursor !== null);
}

for await (const record of paginate(client, { table: 'events' })) {
  await processRecord(record);
}
```

### AbortController / AbortSignal

Pass signals into every async operation that can hang. Compose signals with `AbortSignal.any()`:

```js
async function fetchWithTimeout(url, timeoutMs = 10_000) {
  const controller = new AbortController();
  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  const signal = AbortSignal.any([controller.signal, timeoutSignal]);

  try {
    return await fetch(url, { signal });
  } catch (err) {
    if (err.name === 'AbortError') throw new TimeoutError(`${url} timed out`);
    throw err;
  }
}
```

### Promise Combinators

| API | When to use |
|-----|-------------|
| `Promise.all(ps)` | All must succeed; fail-fast on first rejection |
| `Promise.allSettled(ps)` | Need results of all, regardless of failures |
| `Promise.race(ps)` | First settled wins (fulfilled or rejected) |
| `Promise.any(ps)` | First fulfilled wins; throws `AggregateError` if all reject |

```js
// Fan-out with partial-failure tolerance
const results = await Promise.allSettled([
  fetchUser(id),
  fetchPermissions(id),
  fetchPreferences(id),
]);

const [user, permissions, preferences] = results.map((r) =>
  r.status === 'fulfilled' ? r.value : null
);
```

---

## 4. Streams

### Core Types

- `Readable` -- source of data (file, HTTP body, DB cursor)
- `Writable` -- sink for data (file, HTTP response, DB insert)
- `Transform` -- Readable + Writable; transforms data in transit
- `Duplex` -- bidirectional, independent read/write sides

### pipeline()

Always use `stream.pipeline()` (or `stream/promises` variant) -- it handles cleanup on error and destroys all streams:

```js
import { pipeline } from 'node:stream/promises';
import { createReadStream, createWriteStream } from 'node:fs';
import { createGzip } from 'node:zlib';

await pipeline(
  createReadStream('input.csv'),
  new CSVParseTransform(),
  new ValidationTransform(),
  createGzip(),
  createWriteStream('output.csv.gz')
);
```

### stream.compose()

Combine multiple Transform streams into a single composable unit:

```js
import { compose } from 'node:stream';

const processingPipeline = compose(
  new CSVParseTransform(),
  new ValidationTransform(),
  new NormalisationTransform()
);

await pipeline(inputStream, processingPipeline, outputStream);
```

### Backpressure

Respect `writable.write()` return value. When it returns `false`, pause the readable until `drain` fires:

```js
class ThrottledTransform extends Transform {
  _transform(chunk, _encoding, callback) {
    const canContinue = this.push(processChunk(chunk));
    if (!canContinue) {
      // Node handles this automatically inside pipeline(); manual only for custom plumbing
    }
    callback();
  }
}
```

### Custom Readable (async generator shorthand)

```js
import { Readable } from 'node:stream';

const readable = Readable.from(async function* () {
  for (const id of ids) {
    yield await fetchRecord(id);
  }
}());
```

---

## 5. Worker Threads

Use worker threads for CPU-bound work that would block the event loop (parsing, crypto, compression, ML inference).

```js
// main.js
import { Worker } from 'node:worker_threads';

function runWorker(data) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./worker.js', import.meta.url), {
      workerData: data,
    });
    worker.once('message', resolve);
    worker.once('error', reject);
    worker.once('exit', (code) => {
      if (code !== 0) reject(new WorkerError(`Worker exited with code ${code}`));
    });
  });
}

// worker.js
import { workerData, parentPort } from 'node:worker_threads';

const result = heavyComputation(workerData);
parentPort.postMessage(result);
```

### cluster vs worker_threads

| Concern | `cluster` | `worker_threads` |
|---------|-----------|-----------------|
| Use case | Scale HTTP across CPU cores | CPU-bound tasks off event loop |
| Memory | Separate V8 heaps (high) | Shared `SharedArrayBuffer` possible |
| Communication | IPC (serialised) | `MessageChannel`, `SharedArrayBuffer` |
| Crash isolation | Yes -- child crash doesn't kill master | No -- uncaught exception kills process |
| Startup cost | High (full process fork) | Low (thread in same process) |

Prefer `worker_threads` for compute offload, `cluster` for HTTP load distribution (though a reverse proxy like nginx is usually better for the latter).

---

## 6. Error Handling

### Domain-Specific Error Classes

```js
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
  constructor(message, fields) {
    super(message, { fields });
    this.statusCode = 400;
  }
}
```

### Unhandled Rejections

Always register a top-level handler in your application entry point (not in library code):

```js
process.on('unhandledRejection', (reason, promise) => {
  logger.fatal({ err: reason, promise }, 'unhandled rejection -- shutting down');
  process.exitCode = 1;
  // allow current event loop cycle to complete, then exit
  setTimeout(() => process.exit(1), 100);
});

process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'uncaught exception -- shutting down');
  process.exit(1);
});
```

**Rules**:
- Never swallow errors with empty `catch` blocks
- Never use bare `catch (e) {}` -- always log or rethrow
- Never call `process.exit()` in library code -- only in application entry points

---

## 7. ES Modules

All code must use ES modules. Set in `package.json`:

```json
{ "type": "module" }
```

- Use `import`/`export` everywhere -- no `require()`
- Use `import.meta.url` instead of `__filename` / `__dirname`:

```js
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const configPath = resolve(__dirname, '../config/defaults.json');
```

- Use `exports` map in `package.json` to expose public API and hide internals:

```json
{
  "exports": {
    ".": "./src/index.js",
    "./utils": "./src/utils/index.js"
  }
}
```

---

## 8. Security

| Risk | Mitigation |
|------|-----------|
| `eval()` / `new Function(string)` | Never use -- enables arbitrary code execution |
| `child_process.exec(userInput)` | Use `execFile` with argument array; validate all inputs |
| Path traversal | Resolve paths with `path.resolve()` and assert result starts with expected root |
| Prototype pollution | Use `Object.create(null)` for dynamic key stores; validate with JSON Schema |
| Regex DoS (ReDoS) | Avoid backtracking-prone regexes; use `safe-regex` or limit input length |
| Dependency supply chain | Lock with `pnpm.lock`; run `npm audit` in CI; use `socket.dev` |

```js
// Path traversal guard
import { resolve } from 'node:path';

function safeReadFile(baseDir, userPath) {
  const resolved = resolve(baseDir, userPath);
  if (!resolved.startsWith(resolve(baseDir))) {
    throw new ForbiddenError('Path traversal attempt detected');
  }
  return readFile(resolved, 'utf8');
}
```

---

## 9. Observability

### node:diagnostics_channel

Publish structured events for cross-cutting concerns without tight coupling:

```js
import diagnosticsChannel from 'node:diagnostics_channel';

const httpRequestChannel = diagnosticsChannel.channel('app:http:request');

// Publisher (in HTTP layer)
httpRequestChannel.publish({ method, url, statusCode, durationMs });

// Subscriber (in observability layer)
diagnosticsChannel.subscribe('app:http:request', ({ method, url, statusCode, durationMs }) => {
  metrics.histogram('http.request.duration', durationMs, { method, statusCode });
});
```

### AsyncLocalStorage for Trace Propagation

Propagate request context (trace IDs, user IDs) through async call chains without passing parameters:

```js
import { AsyncLocalStorage } from 'node:async_hooks';

export const requestContext = new AsyncLocalStorage();

// Middleware -- set at request entry point
export function contextMiddleware(req, res, next) {
  const store = {
    traceId: req.headers['x-trace-id'] ?? crypto.randomUUID(),
    userId: null, // populated after auth
  };
  requestContext.run(store, next);
}

// Anywhere in the call stack
export function getTraceId() {
  return requestContext.getStore()?.traceId ?? 'no-context';
}

// Structured logger that automatically includes trace context
export function createLogger(name) {
  return {
    info(data, msg) {
      const store = requestContext.getStore() ?? {};
      process.stdout.write(JSON.stringify({
        level: 'info',
        name,
        msg,
        traceId: store.traceId,
        ...data,
        time: Date.now(),
      }) + '\n');
    },
    // error, warn, debug follow same pattern
  };
}
```

---

## 10. Code Standards

| Rule | Detail |
|------|--------|
| No `console.log` in library code | Use structured JSON logger; `console` is allowed only in scripts and CLI entry points |
| No `process.exit()` in library code | Throw errors; let the application entry point decide shutdown |
| No CommonJS | `require()`, `module.exports`, `__dirname`, `__filename` are banned |
| No deprecated typing | Use `Map`, `Set`, `Record` -- not custom prototype tricks |
| Explicit error types | Catch specific error classes, not bare `catch (e)` |
| Immutable configs | Freeze config objects with `Object.freeze()` before passing them around |
| Structured logging | Every log line is a JSON object with `level`, `msg`, `time`, and contextual fields |
