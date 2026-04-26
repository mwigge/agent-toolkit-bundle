/**
 * di_container.ts — InversifyJS DI container setup.
 *
 * Demonstrates:
 *   - Typed symbol tokens
 *   - Container module pattern
 *   - Binding service and repository implementations
 *   - Async factory binding
 *   - Container snapshot/restore for testing
 */

import "reflect-metadata";

import { Container, ContainerModule, inject, injectable, interfaces } from "inversify";

// ---------------------------------------------------------------------------
// 1. Typed Symbol Tokens — prevent magic string collisions
// ---------------------------------------------------------------------------

export const TOKENS = {
  // Repositories
  ExperimentRepository: Symbol.for("ExperimentRepository"),
  MetricsRepository: Symbol.for("MetricsRepository"),

  // Services
  ExperimentService: Symbol.for("ExperimentService"),
  ResilienceScoreService: Symbol.for("ResilienceScoreService"),

  // Infrastructure
  DatabaseConnection: Symbol.for("DatabaseConnection"),
  HttpClient: Symbol.for("HttpClient"),

  // Config
  Config: Symbol.for("Config"),
} as const;


// ---------------------------------------------------------------------------
// 2. Domain Interfaces (in real code these live in domain/)
// ---------------------------------------------------------------------------

export interface ExperimentRepository {
  findById(id: string): Promise<ExperimentRecord | null>;
  save(experiment: ExperimentRecord): Promise<void>;
  listAll(): Promise<ExperimentRecord[]>;
}

export interface ExperimentRecord {
  readonly id: string;
  readonly name: string;
  readonly success: boolean;
  readonly durationMs: number;
}

export interface ExperimentService {
  run(id: string): Promise<ExperimentRecord>;
  getScore(): Promise<number>;
}

export interface AppConfig {
  readonly databaseUrl: string;
  readonly apiBaseUrl: string;
  readonly timeoutMs: number;
}


// ---------------------------------------------------------------------------
// 3. Concrete implementations (in real code these live in infrastructure/)
// ---------------------------------------------------------------------------

@injectable()
class PostgresExperimentRepository implements ExperimentRepository {
  constructor(
    @inject(TOKENS.DatabaseConnection)
    private readonly db: { query: (sql: string, params: unknown[]) => Promise<unknown[]> },
  ) {}

  async findById(id: string): Promise<ExperimentRecord | null> {
    const rows = await this.db.query(
      "SELECT id, name, success, duration_ms FROM experiments WHERE id = $1",
      [id],
    );
    if (rows.length === 0) return null;
    const row = rows[0] as Record<string, unknown>;
    return {
      id: row["id"] as string,
      name: row["name"] as string,
      success: row["success"] as boolean,
      durationMs: row["duration_ms"] as number,
    };
  }

  async save(experiment: ExperimentRecord): Promise<void> {
    await this.db.query(
      `INSERT INTO experiments (id, name, success, duration_ms)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (id) DO UPDATE
         SET success = $3, duration_ms = $4`,
      [experiment.id, experiment.name, experiment.success, experiment.durationMs],
    );
  }

  async listAll(): Promise<ExperimentRecord[]> {
    const rows = await this.db.query(
      "SELECT id, name, success, duration_ms FROM experiments ORDER BY id",
      [],
    );
    return (rows as Record<string, unknown>[]).map((row) => ({
      id: row["id"] as string,
      name: row["name"] as string,
      success: row["success"] as boolean,
      durationMs: row["duration_ms"] as number,
    }));
  }
}


@injectable()
class ExperimentServiceImpl implements ExperimentService {
  constructor(
    @inject(TOKENS.ExperimentRepository)
    private readonly repo: ExperimentRepository,
  ) {}

  async run(id: string): Promise<ExperimentRecord> {
    const existing = await this.repo.findById(id);
    if (existing !== null) {
      throw new Error(`Experiment ${id} already exists`);
    }
    const record: ExperimentRecord = {
      id,
      name: `experiment-${id}`,
      success: true,
      durationMs: 0,
    };
    await this.repo.save(record);
    return record;
  }

  async getScore(): Promise<number> {
    const all = await this.repo.listAll();
    if (all.length === 0) return 0;
    const passed = all.filter((r) => r.success).length;
    return Math.round((passed / all.length) * 100);
  }
}


// ---------------------------------------------------------------------------
// 4. Container Modules — group related bindings
// ---------------------------------------------------------------------------

export const infrastructureModule = new ContainerModule(
  (bind: interfaces.Bind) => {
    // Async factory for database connection
    bind(TOKENS.DatabaseConnection).toDynamicValue(async (context) => {
      const config = context.container.get<AppConfig>(TOKENS.Config);
      // In real code: return pg.Pool({ connectionString: config.databaseUrl })
      return {
        query: async (sql: string, _params: unknown[]) => {
          console.log(`[mock-db] ${sql}`);
          return [];
        },
      };
    });

    bind<ExperimentRepository>(TOKENS.ExperimentRepository)
      .to(PostgresExperimentRepository)
      .inSingletonScope();
  },
);

export const applicationModule = new ContainerModule(
  (bind: interfaces.Bind) => {
    bind<ExperimentService>(TOKENS.ExperimentService)
      .to(ExperimentServiceImpl)
      .inSingletonScope();
  },
);


// ---------------------------------------------------------------------------
// 5. Container factory — compose modules, inject config
// ---------------------------------------------------------------------------

export function createContainer(config: AppConfig): Container {
  const container = new Container({ defaultScope: "Singleton" });

  container.bind<AppConfig>(TOKENS.Config).toConstantValue(config);
  container.load(infrastructureModule, applicationModule);

  return container;
}


// ---------------------------------------------------------------------------
// 6. Usage
// ---------------------------------------------------------------------------

const config: AppConfig = {
  databaseUrl: process.env["DATABASE_URL"] ?? "postgresql://localhost:5432/chaos",
  apiBaseUrl: process.env["API_BASE_URL"] ?? "https://api.chaos.internal",
  timeoutMs: 5000,
};

export const container = createContainer(config);

// Resolve a service:
// const service = container.get<ExperimentService>(TOKENS.ExperimentService);
// const result = await service.run("exp-001");
