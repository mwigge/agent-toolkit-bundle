import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { PrismaClient, type Prisma } from '@prisma/client';

/**
 * PrismaService — application-scoped Prisma singleton.
 *
 * Responsibilities:
 *   - Connect on module init, disconnect on module destroy
 *   - Provide a typed $transaction helper for interactive transactions
 *   - Integrate with NestJS lifecycle (graceful shutdown)
 *
 * Usage:
 *   1. Add PrismaModule to the imports of any feature module that needs DB access.
 *   2. Inject PrismaService via constructor.
 *   3. Use this.prisma.user.findUnique(...) etc. for standard queries.
 *   4. Use this.prisma.transaction(async (tx) => { ... }) for atomic operations.
 *
 * Never import PrismaService into controller layer — services only.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    super({
      log: [
        { emit: 'event', level: 'query' },
        { emit: 'event', level: 'warn' },
        { emit: 'event', level: 'error' },
      ],
      errorFormat: 'minimal',
    });

    // Forward Prisma log events to NestJS/Pino structured logger.
    // 'query' logging is verbose — only enable in development.
    if (process.env.NODE_ENV !== 'production') {
      (this.$on as (event: 'query', listener: (e: Prisma.QueryEvent) => void) => void)(
        'query',
        (e) => {
          this.logger.debug({ query: e.query, params: e.params, durationMs: e.duration }, 'prisma query');
        }
      );
    }

    (this.$on as (event: 'warn', listener: (e: Prisma.LogEvent) => void) => void)(
      'warn',
      (e) => this.logger.warn({ message: e.message, target: e.target }, 'prisma warning')
    );

    (this.$on as (event: 'error', listener: (e: Prisma.LogEvent) => void) => void)(
      'error',
      (e) => this.logger.error({ message: e.message, target: e.target }, 'prisma error')
    );
  }

  async onModuleInit(): Promise<void> {
    this.logger.log('Connecting to database...');
    await this.$connect();
    this.logger.log('Database connection established');
  }

  async onModuleDestroy(): Promise<void> {
    this.logger.log('Disconnecting from database...');
    await this.$disconnect();
    this.logger.log('Database connection closed');
  }

  /**
   * Run a set of Prisma operations inside a single atomic transaction.
   *
   * Prefer this over the sequential form (`prisma.$transaction([op1, op2])`)
   * when you need conditional logic or need to read data between writes.
   *
   * @example
   * await this.prisma.transaction(async (tx) => {
   *   const from = await tx.account.findUniqueOrThrow({ where: { id: fromId } });
   *   if (from.balance < amount) throw new UnprocessableEntityException('Insufficient funds');
   *   await tx.account.update({ where: { id: fromId }, data: { balance: { decrement: amount } } });
   *   await tx.account.update({ where: { id: toId },   data: { balance: { increment: amount } } });
   * });
   */
  async transaction<T>(
    fn: (tx: Prisma.TransactionClient) => Promise<T>,
    options?: {
      maxWait?: number;   // ms to wait for a transaction slot (default 2000)
      timeout?: number;   // ms before transaction is forcibly rolled back (default 5000)
      isolationLevel?: Prisma.TransactionIsolationLevel;
    }
  ): Promise<T> {
    return this.$transaction(fn, {
      maxWait: options?.maxWait ?? 2_000,
      timeout: options?.timeout ?? 5_000,
      ...(options?.isolationLevel && { isolationLevel: options.isolationLevel }),
    });
  }

  /**
   * Run multiple independent Prisma operations in a single network round-trip
   * (sequential batch transaction). All succeed or all fail — no conditional
   * logic between operations.
   *
   * @example
   * const [users, total] = await this.prisma.batch([
   *   this.prisma.user.findMany({ skip, take }),
   *   this.prisma.user.count(),
   * ]);
   */
  async batch<T extends Prisma.PrismaPromise<unknown>[]>(
    operations: [...T]
  ): Promise<{ [K in keyof T]: Awaited<T[K]> }> {
    return this.$transaction(operations) as Promise<{ [K in keyof T]: Awaited<T[K]> }>;
  }

  /**
   * Verify the database connection is alive.
   * Used in health checks and readiness probes.
   *
   * @throws {Error} if the database is unreachable
   */
  async healthCheck(): Promise<void> {
    await this.$queryRaw`SELECT 1`;
  }
}
