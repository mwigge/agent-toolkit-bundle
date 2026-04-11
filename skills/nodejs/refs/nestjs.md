# NestJS v10+ -- Detailed Reference

**Runtime**: Node 22 LTS | **Framework**: NestJS v10+ | **Language**: TypeScript 5 strict | **ORM**: Prisma

---

## 1. Architecture Overview

NestJS organises code into feature modules. Each module is a self-contained vertical slice:

```
src/
  users/
    users.module.ts        <- DI wiring
    users.controller.ts    <- HTTP boundary
    users.service.ts       <- business logic
    dto/
      create-user.dto.ts   <- input validation
      user-response.dto.ts <- output shape
    guards/
      user-owner.guard.ts
    users.controller.spec.ts
    users.service.spec.ts
  app.module.ts
  main.ts
```

### Module Structure

```ts
import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [],            // other modules whose exports you need
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService], // expose to importing modules
})
export class UsersModule {}
```

---

## 2. Dependency Injection

### @Injectable() and Constructor Injection

```ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async findById(id: string): Promise<User> {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return user;
  }
}
```

### Custom Providers

```ts
// useValue -- inject a static value or mock
{ provide: 'FEATURE_FLAGS', useValue: { betaEnabled: true } }

// useFactory -- async providers with dependencies
{
  provide: EmailService,
  useFactory: async (config: ConfigService) => {
    const client = await createEmailClient(config.getOrThrow('SMTP_URL'));
    return new EmailService(client);
  },
  inject: [ConfigService],
}

// useClass -- swap implementation by environment
{
  provide: NotificationService,
  useClass: process.env.NODE_ENV === 'test' ? NoopNotificationService : SESNotificationService,
}
```

---

## 3. Validation with class-validator + class-transformer

### DTO Definition

```ts
import { IsEmail, IsString, Length, IsOptional, IsUUID } from 'class-validator';
import { Expose, Exclude } from 'class-transformer';

export class CreateUserDto {
  @IsEmail()
  readonly email: string;

  @IsString()
  @Length(1, 100)
  readonly name: string;

  @IsOptional()
  @IsString()
  @Length(0, 500)
  readonly bio?: string;
}
```

### Global ValidationPipe

Register in `main.ts` once -- applies to every route:

```ts
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,            // strips properties not in DTO
    forbidNonWhitelisted: true, // throws if unknown properties are present
    transform: true,            // transform plain objects to DTO class instances
    transformOptions: {
      enableImplicitConversion: true, // convert query param strings to numbers etc.
    },
  }),
);
```

**Rule**: Never use `transform: true` without `whitelist: true` -- you'll silently pass dirty input.

### Response Transformation

Use `@Exclude()` and `@Expose()` on response DTOs to ensure you never leak internal fields:

```ts
@Exclude()
export class UserResponseDto {
  @Expose() readonly id: string;
  @Expose() readonly email: string;
  @Expose() readonly name: string;
  @Expose() readonly createdAt: Date;
  // passwordHash, internalFlags etc. are automatically excluded
}
```

---

## 4. ORM: Prisma

### PrismaService

```ts
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
```

### Transactions

Use `$transaction()` for atomic operations. Prefer the interactive transaction form for complex logic:

```ts
async transferCredits(fromId: string, toId: string, amount: number): Promise<void> {
  await this.prisma.$transaction(async (tx) => {
    const from = await tx.account.findUniqueOrThrow({ where: { id: fromId } });
    if (from.credits < amount) throw new UnprocessableEntityException('Insufficient credits');

    await tx.account.update({
      where: { id: fromId },
      data: { credits: { decrement: amount } },
    });
    await tx.account.update({
      where: { id: toId },
      data: { credits: { increment: amount } },
    });
    await tx.transaction.create({
      data: { fromId, toId, amount, createdAt: new Date() },
    });
  });
}
```

### Prisma Client Extensions

Extend the client to add soft-delete, audit logging, or tenant filtering:

```ts
const client = new PrismaClient().$extends({
  query: {
    $allModels: {
      async findMany({ args, query }) {
        args.where = { ...args.where, deletedAt: null };
        return query(args);
      },
    },
  },
});
```

---

## 5. Configuration with @nestjs/config

### Validated Config with Joi

```ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import Joi from 'joi';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env.local', '.env'],
      validationSchema: Joi.object({
        NODE_ENV: Joi.string().valid('development', 'production', 'test').required(),
        PORT: Joi.number().integer().min(1024).max(65535).default(3000),
        DATABASE_URL: Joi.string().uri().required(),
        JWT_SECRET: Joi.string().min(32).required(),
      }),
      validationOptions: { abortEarly: false },
    }),
  ],
})
export class AppModule {}
```

### Typed Config Access

Never access `process.env` directly in services. Always inject `ConfigService`:

```ts
@Injectable()
export class AuthService {
  private readonly jwtSecret: string;

  constructor(private readonly config: ConfigService) {
    this.jwtSecret = this.config.getOrThrow<string>('JWT_SECRET');
  }
}
```

---

## 6. Testing

### Unit Tests with createTestingModule

```ts
import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';

describe('UsersService', () => {
  let service: UsersService;
  let prisma: DeepMockProxy<PrismaService>;

  beforeEach(async () => {
    prisma = mockDeep<PrismaService>();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get<UsersService>(UsersService);
  });

  it('returns a user by id', async () => {
    const expected = { id: 'user-1', email: 'alice@example.com', name: 'Alice' } as User;
    prisma.user.findUnique.mockResolvedValue(expected);

    const result = await service.findById('user-1');
    expect(result).toEqual(expected);
  });

  it('throws NotFoundException when user does not exist', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    await expect(service.findById('missing')).rejects.toThrow(NotFoundException);
  });
});
```

### E2E Tests with Supertest

```ts
import { Test } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';

describe('POST /users (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(PrismaService)
      .useValue(mockPrisma)
      .compile();

    app = module.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
  });

  afterAll(() => app.close());

  it('201 with valid payload', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'alice@example.com', name: 'Alice' })
      .expect(201);

    expect(res.body.id).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('400 when email is missing', async () => {
    await request(app.getHttpServer())
      .post('/users')
      .send({ name: 'Alice' })
      .expect(400);
  });
});
```

---

## 7. Authentication: @nestjs/passport + passport-jwt

### JWT Strategy

```ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';

export interface JwtPayload {
  sub: string;
  email: string;
  role: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.getOrThrow('JWT_SECRET'),
      ignoreExpiration: false,
    });
  }

  async validate(payload: JwtPayload) {
    if (!payload.sub) throw new UnauthorizedException();
    return { id: payload.sub, email: payload.email, role: payload.role };
  }
}
```

### @CurrentUser() Decorator

```ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<Request>();
    return request.user;
  },
);

// In controller:
@Get('profile')
@UseGuards(JwtAuthGuard)
getProfile(@CurrentUser() user: AuthenticatedUser): UserResponseDto {
  return plainToInstance(UserResponseDto, user, { excludeExtraneousValues: true });
}
```

---

## 8. Error Handling

### HttpException Subclasses

```ts
import { HttpException, HttpStatus } from '@nestjs/common';

export class ResourceConflictException extends HttpException {
  constructor(resource: string, identifier: string) {
    super(
      { error: 'Conflict', message: `${resource} '${identifier}' already exists`, statusCode: 409 },
      HttpStatus.CONFLICT,
    );
  }
}

// NestJS built-ins cover most cases:
throw new NotFoundException('User not found');
throw new BadRequestException('Invalid date range');
throw new UnauthorizedException('Token expired');
throw new ForbiddenException('Insufficient permissions');
throw new ConflictException('Email already registered');
throw new UnprocessableEntityException('Invalid state transition');
```

### Global Exception Filter

```ts
import { Catch, ArgumentsHost, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import type { Response } from 'express';

@Catch()
export class GlobalExceptionFilter extends BaseExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      response.status(status).json(body);
      return;
    }

    this.logger.error({ err: exception }, 'Unhandled exception');
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: 500,
      error: 'InternalServerError',
      message: 'An unexpected error occurred',
    });
  }
}
```

---

## 9. CQRS (Optional -- Complex Domains)

Use `@nestjs/cqrs` when a service has more than ~5 operations or domain logic spans multiple aggregates:

```ts
// Command
export class CreateOrderCommand {
  constructor(
    public readonly userId: string,
    public readonly items: OrderItemDto[],
  ) {}
}

// Command Handler
@CommandHandler(CreateOrderCommand)
export class CreateOrderHandler implements ICommandHandler<CreateOrderCommand> {
  constructor(
    private readonly prisma: PrismaService,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: CreateOrderCommand): Promise<Order> {
    const order = await this.prisma.$transaction(async (tx) => {
      // validate stock, create order, deduct inventory
    });
    await this.eventBus.publish(new OrderCreatedEvent(order.id));
    return order;
  }
}

// In Controller
constructor(private readonly commandBus: CommandBus) {}

@Post()
async create(@Body() dto: CreateOrderDto, @CurrentUser() user: AuthenticatedUser) {
  return this.commandBus.execute(new CreateOrderCommand(user.id, dto.items));
}
```

---

## 10. Observability: nestjs-pino + OpenTelemetry

### nestjs-pino

```ts
// app.module.ts
LoggerModule.forRootAsync({
  useFactory: (config: ConfigService) => ({
    pinoHttp: {
      level: config.get('LOG_LEVEL', 'info'),
      redact: ['req.headers.authorization', 'req.headers.cookie'],
      transport: config.get('NODE_ENV') !== 'production'
        ? { target: 'pino-pretty' }
        : undefined,
    },
  }),
  inject: [ConfigService],
}),
```

### OTel Interceptor

```ts
import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { trace, SpanStatusCode } from '@opentelemetry/api';
import { Observable, throwError } from 'rxjs';
import { tap, catchError } from 'rxjs/operators';

@Injectable()
export class TracingInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const span = trace.getActiveSpan();

    span?.setAttributes({
      'http.method': request.method,
      'http.route': request.route?.path,
      'user.id': request.user?.id,
    });

    return next.handle().pipe(
      tap(() => span?.setStatus({ code: SpanStatusCode.OK })),
      catchError((err) => {
        span?.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
        span?.recordException(err);
        return throwError(() => err);
      }),
    );
  }
}
```

---

## Code Standards

| Rule | Detail |
|------|--------|
| No `process.env` in services | Always inject `ConfigService`; use `getOrThrow` for required values |
| No `any` | TypeScript strict mode enforced; use `unknown` and narrow explicitly |
| Readonly DTOs | All DTO properties marked `readonly` |
| Explicit return types | All service methods have explicit return type annotations |
| Never throw plain `Error` | Always throw `HttpException` subclasses |
| `whitelist: true` globally | ValidationPipe strips unknown fields on every endpoint |
| Mock via `createTestingModule` | Never instantiate services directly in tests |
