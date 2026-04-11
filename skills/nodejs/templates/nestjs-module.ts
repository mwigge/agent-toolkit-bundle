import { Module, Controller, Get, Post, Patch, Delete, Param, Body, UseGuards,
         HttpCode, HttpStatus, SerializeOptions, ParseUUIDPipe } from '@nestjs/common';
import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsString, Length, IsEmail, IsOptional } from 'class-validator';
import { Expose, Exclude } from 'class-transformer';
import { PartialType } from '@nestjs/mapped-types';
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Test, TestingModule } from '@nestjs/testing';
import { PrismaService } from './prisma.service';

// ── DTOs ──────────────────────────────────────────────────────────────────────

export class CreateUserDto {
  @IsString()
  @Length(1, 100)
  readonly name: string;

  @IsEmail()
  readonly email: string;

  @IsOptional()
  @IsString()
  @Length(0, 500)
  readonly bio?: string;
}

export class UpdateUserDto extends PartialType(CreateUserDto) {}

@Exclude()
export class UserResponseDto {
  @Expose() readonly id: string;
  @Expose() readonly name: string;
  @Expose() readonly email: string;
  @Expose() readonly bio: string | null;
  @Expose() readonly createdAt: Date;
  @Expose() readonly updatedAt: Date;
  // passwordHash, internalFlags, deletedAt etc. are NOT exposed
}

// ── Custom decorators ─────────────────────────────────────────────────────────

export interface AuthenticatedUser {
  id: string;
  email: string;
  role: string;
}

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthenticatedUser => {
    const request = ctx.switchToHttp().getRequest<{ user: AuthenticatedUser }>();
    return request.user;
  }
);

// ── Service ───────────────────────────────────────────────────────────────────

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
}

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(page = 1, limit = 20): Promise<PaginatedResult<UserResponseDto>> {
    const skip = (page - 1) * limit;

    const [items, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        select: { id: true, name: true, email: true, bio: true, createdAt: true, updatedAt: true },
      }),
      this.prisma.user.count(),
    ]);

    return { items: items as unknown as UserResponseDto[], total, page, limit };
  }

  async findById(id: string): Promise<UserResponseDto> {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: { id: true, name: true, email: true, bio: true, createdAt: true, updatedAt: true },
    });

    if (!user) throw new NotFoundException(`User ${id} not found`);
    return user as unknown as UserResponseDto;
  }

  async create(dto: CreateUserDto): Promise<UserResponseDto> {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException(`Email ${dto.email} is already registered`);

    return this.prisma.user.create({
      data: {
        name: dto.name,
        email: dto.email,
        bio: dto.bio ?? null,
      },
      select: { id: true, name: true, email: true, bio: true, createdAt: true, updatedAt: true },
    }) as unknown as Promise<UserResponseDto>;
  }

  async update(id: string, dto: UpdateUserDto): Promise<UserResponseDto> {
    await this.findById(id); // throws NotFoundException if absent

    if (dto.email) {
      const conflict = await this.prisma.user.findFirst({
        where: { email: dto.email, id: { not: id } },
      });
      if (conflict) throw new ConflictException(`Email ${dto.email} is already in use`);
    }

    return this.prisma.user.update({
      where: { id },
      data: {
        ...(dto.name !== undefined && { name: dto.name }),
        ...(dto.email !== undefined && { email: dto.email }),
        ...(dto.bio !== undefined && { bio: dto.bio }),
      },
      select: { id: true, name: true, email: true, bio: true, createdAt: true, updatedAt: true },
    }) as unknown as Promise<UserResponseDto>;
  }

  async remove(id: string): Promise<void> {
    await this.findById(id); // throws NotFoundException if absent
    await this.prisma.user.delete({ where: { id } });
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

@Controller('users')
@UseGuards(AuthGuard('jwt'))
@SerializeOptions({ type: UserResponseDto, excludeExtraneousValues: true })
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  findAll(): Promise<PaginatedResult<UserResponseDto>> {
    return this.usersService.findAll();
  }

  @Get('me')
  getProfile(@CurrentUser() user: AuthenticatedUser): Promise<UserResponseDto> {
    return this.usersService.findById(user.id);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string): Promise<UserResponseDto> {
    return this.usersService.findById(id);
  }

  @Post()
  create(@Body() dto: CreateUserDto): Promise<UserResponseDto> {
    return this.usersService.create(dto);
  }

  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateUserDto
  ): Promise<UserResponseDto> {
    return this.usersService.update(id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    return this.usersService.remove(id);
  }
}

// ── Module ────────────────────────────────────────────────────────────────────

@Module({
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}

// ── Unit test stub ────────────────────────────────────────────────────────────
// Delete this block and move to users.service.spec.ts in production code.

async function exampleTest() {
  const mockPrisma = {
    user: {
      findMany: jest.fn().mockResolvedValue([]),
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
    },
    $transaction: jest.fn().mockResolvedValue([[], 0]),
  };

  const module: TestingModule = await Test.createTestingModule({
    providers: [
      UsersService,
      { provide: PrismaService, useValue: mockPrisma },
    ],
  }).compile();

  const service = module.get<UsersService>(UsersService);

  // Example: NotFoundException on missing user
  mockPrisma.user.findUnique.mockResolvedValueOnce(null);
  try {
    await service.findById('nonexistent-uuid');
    throw new Error('Expected NotFoundException');
  } catch (err) {
    if (!(err instanceof NotFoundException)) throw err;
    console.log('Test passed: NotFoundException thrown for missing user');
  }
}

// Uncomment to run the inline test stub:
// exampleTest().catch(console.error);
