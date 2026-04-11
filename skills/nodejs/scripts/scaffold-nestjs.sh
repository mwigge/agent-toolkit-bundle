#!/usr/bin/env bash
# scripts/scaffold.sh — NestJS feature module scaffold generator
# Generates a complete feature module with controller, service, DTOs, and spec files.
#
# Usage: bash scripts/scaffold.sh <module-name> [src-dir]
#
# Examples:
#   bash scripts/scaffold.sh users
#   bash scripts/scaffold.sh audit-logs src
#
# Output structure:
#   src/<name>/
#     <name>.module.ts
#     <name>.controller.ts
#     <name>.service.ts
#     dto/create-<name>.dto.ts
#     dto/update-<name>.dto.ts
#     dto/<name>-response.dto.ts
#     <name>.controller.spec.ts
#     <name>.service.spec.ts

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf "${GREEN}[scaffold]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}    %s\n" "$*"; }
error() { printf "${RED}[error]${NC}   %s\n" "$*" >&2; }

# ── Arguments ────────────────────────────────────────────────────────────────
MODULE_NAME="${1:-}"
SRC_DIR="${2:-src}"

if [[ -z "$MODULE_NAME" ]]; then
  error "Module name is required"
  echo "Usage: bash scripts/scaffold.sh <module-name> [src-dir]"
  exit 1
fi

# Normalise names
MODULE_KEBAB=$(echo "$MODULE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '-')
MODULE_PASCAL=$(echo "$MODULE_KEBAB" | sed 's/-\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/')
MODULE_CAMEL=$(echo "$MODULE_PASCAL" | sed 's/^\([A-Z]\)/\l\1/')

info "Scaffolding NestJS module: $MODULE_KEBAB"
info "  Pascal: $MODULE_PASCAL | Camel: $MODULE_CAMEL"

# ── Directories ───────────────────────────────────────────────────────────────
MODULE_DIR="$SRC_DIR/$MODULE_KEBAB"
DTO_DIR="$MODULE_DIR/dto"

if [[ -d "$MODULE_DIR" ]]; then
  warn "Module directory already exists: $MODULE_DIR"
  read -r -p "Overwrite? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    info "Aborted."
    exit 0
  fi
fi

mkdir -p "$DTO_DIR"

# ── dto/create-<name>.dto.ts ──────────────────────────────────────────────────
cat > "$DTO_DIR/create-${MODULE_KEBAB}.dto.ts" <<DTO_EOF
import { IsString, Length, IsOptional, IsEmail } from 'class-validator';

export class Create${MODULE_PASCAL}Dto {
  @IsString()
  @Length(1, 200)
  readonly name: string;

  @IsOptional()
  @IsEmail()
  readonly email?: string;
}
DTO_EOF
info "Created $DTO_DIR/create-${MODULE_KEBAB}.dto.ts"

# ── dto/update-<name>.dto.ts ──────────────────────────────────────────────────
cat > "$DTO_DIR/update-${MODULE_KEBAB}.dto.ts" <<DTO_EOF
import { PartialType } from '@nestjs/mapped-types';
import { Create${MODULE_PASCAL}Dto } from './create-${MODULE_KEBAB}.dto';

export class Update${MODULE_PASCAL}Dto extends PartialType(Create${MODULE_PASCAL}Dto) {}
DTO_EOF
info "Created $DTO_DIR/update-${MODULE_KEBAB}.dto.ts"

# ── dto/<name>-response.dto.ts ────────────────────────────────────────────────
cat > "$DTO_DIR/${MODULE_KEBAB}-response.dto.ts" <<DTO_EOF
import { Expose, Exclude } from 'class-transformer';

@Exclude()
export class ${MODULE_PASCAL}ResponseDto {
  @Expose()
  readonly id: string;

  @Expose()
  readonly name: string;

  @Expose()
  readonly email?: string;

  @Expose()
  readonly createdAt: Date;

  @Expose()
  readonly updatedAt: Date;
}
DTO_EOF
info "Created $DTO_DIR/${MODULE_KEBAB}-response.dto.ts"

# ── <name>.service.ts ─────────────────────────────────────────────────────────
cat > "$MODULE_DIR/${MODULE_KEBAB}.service.ts" <<SVC_EOF
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Create${MODULE_PASCAL}Dto } from './dto/create-${MODULE_KEBAB}.dto';
import type { Update${MODULE_PASCAL}Dto } from './dto/update-${MODULE_KEBAB}.dto';
import type { Prisma, ${MODULE_PASCAL} } from '@prisma/client';

@Injectable()
export class ${MODULE_PASCAL}Service {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(params: { page?: number; limit?: number } = {}): Promise<{ items: ${MODULE_PASCAL}[]; total: number }> {
    const page = params.page ?? 1;
    const limit = params.limit ?? 20;
    const skip = (page - 1) * limit;

    const [items, total] = await this.prisma.$transaction([
      this.prisma.${MODULE_CAMEL}.findMany({ skip, take: limit, orderBy: { createdAt: 'desc' } }),
      this.prisma.${MODULE_CAMEL}.count(),
    ]);

    return { items, total };
  }

  async findById(id: string): Promise<${MODULE_PASCAL}> {
    const item = await this.prisma.${MODULE_CAMEL}.findUnique({ where: { id } });
    if (!item) throw new NotFoundException(\`${MODULE_PASCAL} \${id} not found\`);
    return item;
  }

  async create(dto: Create${MODULE_PASCAL}Dto): Promise<${MODULE_PASCAL}> {
    return this.prisma.${MODULE_CAMEL}.create({
      data: dto as Prisma.${MODULE_PASCAL}CreateInput,
    });
  }

  async update(id: string, dto: Update${MODULE_PASCAL}Dto): Promise<${MODULE_PASCAL}> {
    await this.findById(id); // throws NotFoundException if not found
    return this.prisma.${MODULE_CAMEL}.update({
      where: { id },
      data: dto as Prisma.${MODULE_PASCAL}UpdateInput,
    });
  }

  async remove(id: string): Promise<void> {
    await this.findById(id); // throws NotFoundException if not found
    await this.prisma.${MODULE_CAMEL}.delete({ where: { id } });
  }
}
SVC_EOF
info "Created $MODULE_DIR/${MODULE_KEBAB}.service.ts"

# ── <name>.controller.ts ──────────────────────────────────────────────────────
cat > "$MODULE_DIR/${MODULE_KEBAB}.controller.ts" <<CTRL_EOF
import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  Query,
  ParseIntPipe,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
  UseGuards,
  SerializeOptions,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ${MODULE_PASCAL}Service } from './${MODULE_KEBAB}.service';
import { Create${MODULE_PASCAL}Dto } from './dto/create-${MODULE_KEBAB}.dto';
import { Update${MODULE_PASCAL}Dto } from './dto/update-${MODULE_KEBAB}.dto';
import { ${MODULE_PASCAL}ResponseDto } from './dto/${MODULE_KEBAB}-response.dto';

@Controller('${MODULE_KEBAB}')
@UseGuards(JwtAuthGuard)
@SerializeOptions({ type: ${MODULE_PASCAL}ResponseDto, excludeExtraneousValues: true })
export class ${MODULE_PASCAL}Controller {
  constructor(private readonly ${MODULE_CAMEL}Service: ${MODULE_PASCAL}Service) {}

  @Get()
  findAll(
    @Query('page', new ParseIntPipe({ optional: true })) page?: number,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    return this.${MODULE_CAMEL}Service.findAll({ page, limit });
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.${MODULE_CAMEL}Service.findById(id);
  }

  @Post()
  create(@Body() dto: Create${MODULE_PASCAL}Dto) {
    return this.${MODULE_CAMEL}Service.create(dto);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: Update${MODULE_PASCAL}Dto) {
    return this.${MODULE_CAMEL}Service.update(id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    return this.${MODULE_CAMEL}Service.remove(id);
  }
}
CTRL_EOF
info "Created $MODULE_DIR/${MODULE_KEBAB}.controller.ts"

# ── <name>.module.ts ──────────────────────────────────────────────────────────
cat > "$MODULE_DIR/${MODULE_KEBAB}.module.ts" <<MOD_EOF
import { Module } from '@nestjs/common';
import { ${MODULE_PASCAL}Controller } from './${MODULE_KEBAB}.controller';
import { ${MODULE_PASCAL}Service } from './${MODULE_KEBAB}.service';
import { PrismaModule } from '../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [${MODULE_PASCAL}Controller],
  providers: [${MODULE_PASCAL}Service],
  exports: [${MODULE_PASCAL}Service],
})
export class ${MODULE_PASCAL}Module {}
MOD_EOF
info "Created $MODULE_DIR/${MODULE_KEBAB}.module.ts"

# ── <name>.service.spec.ts ────────────────────────────────────────────────────
cat > "$MODULE_DIR/${MODULE_KEBAB}.service.spec.ts" <<SPEC_EOF
import { Test, type TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { mockDeep, type DeepMockProxy } from 'jest-mock-extended';
import { ${MODULE_PASCAL}Service } from './${MODULE_KEBAB}.service';
import { PrismaService } from '../prisma/prisma.service';
import type { ${MODULE_PASCAL} } from '@prisma/client';

const makeItem = (overrides: Partial<${MODULE_PASCAL}> = {}): ${MODULE_PASCAL} => ({
  id: 'test-uuid-1',
  name: 'Test ${MODULE_PASCAL}',
  email: null,
  createdAt: new Date('2026-01-01T00:00:00Z'),
  updatedAt: new Date('2026-01-01T00:00:00Z'),
  ...overrides,
});

describe('${MODULE_PASCAL}Service', () => {
  let service: ${MODULE_PASCAL}Service;
  let prisma: DeepMockProxy<PrismaService>;

  beforeEach(async () => {
    prisma = mockDeep<PrismaService>();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ${MODULE_PASCAL}Service,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get<${MODULE_PASCAL}Service>(${MODULE_PASCAL}Service);
  });

  describe('findAll', () => {
    it('returns paginated items and total', async () => {
      const items = [makeItem()];
      prisma.\$transaction.mockResolvedValue([items, 1]);

      const result = await service.findAll({ page: 1, limit: 10 });

      expect(result.items).toEqual(items);
      expect(result.total).toBe(1);
    });
  });

  describe('findById', () => {
    it('returns item when found', async () => {
      const item = makeItem();
      prisma.${MODULE_CAMEL}.findUnique.mockResolvedValue(item);

      await expect(service.findById('test-uuid-1')).resolves.toEqual(item);
    });

    it('throws NotFoundException when item does not exist', async () => {
      prisma.${MODULE_CAMEL}.findUnique.mockResolvedValue(null);

      await expect(service.findById('missing')).rejects.toThrow(NotFoundException);
    });
  });

  describe('create', () => {
    it('creates and returns the new item', async () => {
      const dto = { name: 'New ${MODULE_PASCAL}' };
      const created = makeItem(dto);
      prisma.${MODULE_CAMEL}.create.mockResolvedValue(created);

      await expect(service.create(dto)).resolves.toEqual(created);
      expect(prisma.${MODULE_CAMEL}.create).toHaveBeenCalledWith({ data: dto });
    });
  });

  describe('update', () => {
    it('updates and returns the item', async () => {
      const existing = makeItem();
      const dto = { name: 'Updated' };
      const updated = makeItem(dto);
      prisma.${MODULE_CAMEL}.findUnique.mockResolvedValue(existing);
      prisma.${MODULE_CAMEL}.update.mockResolvedValue(updated);

      await expect(service.update('test-uuid-1', dto)).resolves.toEqual(updated);
    });

    it('throws NotFoundException when updating non-existent item', async () => {
      prisma.${MODULE_CAMEL}.findUnique.mockResolvedValue(null);

      await expect(service.update('missing', { name: 'x' })).rejects.toThrow(NotFoundException);
    });
  });

  describe('remove', () => {
    it('deletes the item', async () => {
      const existing = makeItem();
      prisma.${MODULE_CAMEL}.findUnique.mockResolvedValue(existing);
      prisma.${MODULE_CAMEL}.delete.mockResolvedValue(existing);

      await expect(service.remove('test-uuid-1')).resolves.toBeUndefined();
      expect(prisma.${MODULE_CAMEL}.delete).toHaveBeenCalledWith({ where: { id: 'test-uuid-1' } });
    });
  });
});
SPEC_EOF
info "Created $MODULE_DIR/${MODULE_KEBAB}.service.spec.ts"

# ── <name>.controller.spec.ts ─────────────────────────────────────────────────
cat > "$MODULE_DIR/${MODULE_KEBAB}.controller.spec.ts" <<CTRL_SPEC_EOF
import { Test, type TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { ${MODULE_PASCAL}Controller } from './${MODULE_KEBAB}.controller';
import { ${MODULE_PASCAL}Service } from './${MODULE_KEBAB}.service';
import type { ${MODULE_PASCAL} } from '@prisma/client';

const mockService = {
  findAll: jest.fn(),
  findById: jest.fn(),
  create: jest.fn(),
  update: jest.fn(),
  remove: jest.fn(),
};

const makeItem = (overrides = {}): ${MODULE_PASCAL} => ({
  id: 'test-uuid-1',
  name: 'Test Item',
  email: null,
  createdAt: new Date('2026-01-01T00:00:00Z'),
  updatedAt: new Date('2026-01-01T00:00:00Z'),
  ...overrides,
});

describe('${MODULE_PASCAL}Controller', () => {
  let controller: ${MODULE_PASCAL}Controller;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [${MODULE_PASCAL}Controller],
      providers: [{ provide: ${MODULE_PASCAL}Service, useValue: mockService }],
    }).compile();

    controller = module.get<${MODULE_PASCAL}Controller>(${MODULE_PASCAL}Controller);
    jest.clearAllMocks();
  });

  it('findAll delegates to service', async () => {
    const expected = { items: [makeItem()], total: 1 };
    mockService.findAll.mockResolvedValue(expected);

    const result = await controller.findAll(1, 10);
    expect(result).toEqual(expected);
    expect(mockService.findAll).toHaveBeenCalledWith({ page: 1, limit: 10 });
  });

  it('findOne returns item', async () => {
    const item = makeItem();
    mockService.findById.mockResolvedValue(item);

    const result = await controller.findOne('test-uuid-1');
    expect(result).toEqual(item);
  });

  it('findOne propagates NotFoundException from service', async () => {
    mockService.findById.mockRejectedValue(new NotFoundException('not found'));

    await expect(controller.findOne('missing')).rejects.toThrow(NotFoundException);
  });

  it('create calls service with dto', async () => {
    const dto = { name: 'New Item' };
    const created = makeItem(dto);
    mockService.create.mockResolvedValue(created);

    const result = await controller.create(dto);
    expect(result).toEqual(created);
    expect(mockService.create).toHaveBeenCalledWith(dto);
  });
});
CTRL_SPEC_EOF
info "Created $MODULE_DIR/${MODULE_KEBAB}.controller.spec.ts"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "Scaffold complete for module: $MODULE_KEBAB"
echo ""
echo "  Files created in $MODULE_DIR/:"
echo "    ${MODULE_KEBAB}.module.ts"
echo "    ${MODULE_KEBAB}.controller.ts"
echo "    ${MODULE_KEBAB}.service.ts"
echo "    dto/create-${MODULE_KEBAB}.dto.ts"
echo "    dto/update-${MODULE_KEBAB}.dto.ts"
echo "    dto/${MODULE_KEBAB}-response.dto.ts"
echo "    ${MODULE_KEBAB}.controller.spec.ts"
echo "    ${MODULE_KEBAB}.service.spec.ts"
echo ""
echo "  Next steps:"
echo "    1. Add '${MODULE_PASCAL}Module' to app.module.ts imports"
echo "    2. Add '${MODULE_PASCAL}' model to prisma/schema.prisma"
echo "    3. Run: npx prisma migrate dev --name add_${MODULE_CAMEL}"
echo "    4. Run tests: npx jest ${MODULE_KEBAB}"
