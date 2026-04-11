/**
 * test_example.ts — Vitest test suite demonstrating best practices.
 *
 * Shows:
 *   - describe/it/expect structure
 *   - beforeEach setup
 *   - vi.mock and vi.spyOn
 *   - MSW v2 HTTP handler
 *   - Async tests
 *   - Type-safe mocks
 */

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

// ---------------------------------------------------------------------------
// Module under test (inline for self-contained example)
// ---------------------------------------------------------------------------

interface ExperimentResult {
  readonly id: string;
  readonly success: boolean;
  readonly durationMs: number;
}

interface ExperimentRepository {
  findById(id: string): Promise<ExperimentResult | null>;
  save(result: ExperimentResult): Promise<void>;
}

class ExperimentService {
  constructor(
    private readonly repo: ExperimentRepository,
    private readonly clock: () => number = Date.now,
  ) {}

  async run(id: string): Promise<ExperimentResult> {
    const existing = await this.repo.findById(id);
    if (existing !== null) {
      throw new Error(`Experiment ${id} already exists`);
    }
    const start = this.clock();
    // Simulate work
    const durationMs = this.clock() - start;
    const result: ExperimentResult = { id, success: true, durationMs };
    await this.repo.save(result);
    return result;
  }
}

function computeScore(results: ExperimentResult[]): number {
  if (results.length === 0) return 0;
  const passed = results.filter((r) => r.success).length;
  return Math.round((passed / results.length) * 100);
}

// ---------------------------------------------------------------------------
// 1. Basic describe/it/expect
// ---------------------------------------------------------------------------

describe("computeScore", () => {
  it("returns 0 for empty results", () => {
    expect(computeScore([])).toBe(0);
  });

  it("returns 100 when all experiments pass", () => {
    const results: ExperimentResult[] = [
      { id: "e1", success: true, durationMs: 100 },
      { id: "e2", success: true, durationMs: 200 },
    ];
    expect(computeScore(results)).toBe(100);
  });

  it("returns 50 when half pass", () => {
    const results: ExperimentResult[] = [
      { id: "e1", success: true, durationMs: 100 },
      { id: "e2", success: false, durationMs: 50 },
    ];
    expect(computeScore(results)).toBe(50);
  });

  it("returns 0 when all experiments fail", () => {
    const results: ExperimentResult[] = [
      { id: "e1", success: false, durationMs: 100 },
    ];
    expect(computeScore(results)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2. beforeEach + vi.spyOn + async
// ---------------------------------------------------------------------------

describe("ExperimentService", () => {
  let mockRepo: ExperimentRepository;
  let mockClock: ReturnType<typeof vi.fn>;
  let service: ExperimentService;

  beforeEach(() => {
    mockClock = vi.fn().mockReturnValue(1000);
    mockRepo = {
      findById: vi.fn().mockResolvedValue(null),
      save: vi.fn().mockResolvedValue(undefined),
    };
    service = new ExperimentService(mockRepo, mockClock);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("runs a new experiment and saves it", async () => {
    const result = await service.run("exp-001");

    expect(result.id).toBe("exp-001");
    expect(result.success).toBe(true);
    expect(mockRepo.save).toHaveBeenCalledOnce();
    expect(mockRepo.save).toHaveBeenCalledWith(
      expect.objectContaining({ id: "exp-001", success: true }),
    );
  });

  it("throws if experiment already exists", async () => {
    vi.mocked(mockRepo.findById).mockResolvedValueOnce({
      id: "exp-001",
      success: true,
      durationMs: 100,
    });

    await expect(service.run("exp-001")).rejects.toThrow("already exists");
  });

  it("calls findById with the correct id", async () => {
    await service.run("exp-002");
    expect(mockRepo.findById).toHaveBeenCalledWith("exp-002");
  });
});

// ---------------------------------------------------------------------------
// 3. vi.mock — module-level mock
// ---------------------------------------------------------------------------

vi.mock("node:crypto", () => ({
  randomUUID: vi.fn().mockReturnValue("mocked-uuid-1234"),
}));

describe("vi.mock example", () => {
  it("intercepts crypto.randomUUID", async () => {
    const { randomUUID } = await import("node:crypto");
    expect(randomUUID()).toBe("mocked-uuid-1234");
  });
});

// ---------------------------------------------------------------------------
// 4. MSW v2 HTTP mocking
// ---------------------------------------------------------------------------

// Guard: only run if msw is installed
const mswAvailable = await import("msw").then(() => true).catch(() => false);

describe.skipIf(!mswAvailable)("HTTP integration with MSW", () => {
  // Conditional MSW setup to avoid hard dependency
  let server: { listen: () => void; close: () => void; resetHandlers: () => void } | null = null;

  beforeAll(async () => {
    if (!mswAvailable) return;
    const { setupServer } = await import("msw/node");
    const { http, HttpResponse } = await import("msw");

    server = setupServer(
      http.get("https://api.chaos.internal/experiments", () => {
        return HttpResponse.json({
          experiments: [{ id: "exp-001", status: "completed" }],
        });
      }),
      http.post("https://api.chaos.internal/experiments", async ({ request }) => {
        const body = await request.json();
        return HttpResponse.json({ id: "exp-new", ...body as object }, { status: 201 });
      }),
    );
    server.listen();
  });

  afterEach(() => server?.resetHandlers());
  afterAll(() => server?.close());

  it("fetches experiments list", async () => {
    const res = await fetch("https://api.chaos.internal/experiments");
    const data = await res.json() as { experiments: { id: string }[] };

    expect(res.status).toBe(200);
    expect(data.experiments).toHaveLength(1);
    expect(data.experiments[0]?.id).toBe("exp-001");
  });

  it("creates an experiment", async () => {
    const res = await fetch("https://api.chaos.internal/experiments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "network-latency" }),
    });

    expect(res.status).toBe(201);
    const body = await res.json() as { id: string; name: string };
    expect(body.name).toBe("network-latency");
  });
});

// ---------------------------------------------------------------------------
// 5. Snapshot testing
// ---------------------------------------------------------------------------

describe("snapshot", () => {
  it("stable experiment summary shape", () => {
    const result: ExperimentResult = {
      id: "exp-snap-001",
      success: true,
      durationMs: 1234,
    };
    expect(result).toMatchInlineSnapshot(`
      {
        "durationMs": 1234,
        "id": "exp-snap-001",
        "success": true,
      }
    `);
  });
});
