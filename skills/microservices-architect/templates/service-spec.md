# Service Specification — {SERVICE_NAME}

## Overview

| Field | Value |
|-------|-------|
| Service name | {SERVICE_NAME} |
| Bounded context | {CONTEXT} |
| Owner team | {TEAM} |
| Repository | {REPO_URL} |
| Runtime | {Python 3.12 / Node 22 / etc.} |
| Framework | {FastAPI / NestJS / etc.} |

## Responsibility
{One paragraph describing what this service does and why it exists.}

## API Contract
- OpenAPI spec: `{path_to_openapi.yaml}`
- AsyncAPI spec: `{path_to_asyncapi.yaml}` (if event-driven)

### Endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET | /api/{resource} | List {resources} |
| GET | /api/{resource}/{id} | Get {resource} by ID |
| POST | /api/{resource} | Create {resource} |

### Events Published
| Event | Topic | Schema |
|-------|-------|--------|
| {resource}.created | {topic} | {schema_ref} |
| {resource}.updated | {topic} | {schema_ref} |

### Events Consumed
| Event | Source | Handler |
|-------|--------|---------|
| {event_name} | {source_service} | {handler_function} |

## Dependencies
| Dependency | Type | Circuit breaker | Timeout |
|-----------|------|----------------|---------|
| {service_name} | HTTP/gRPC | Yes | {N}s |
| PostgreSQL | Database | N/A | {N}s |
| Redis | Cache | Yes | {N}s |

## Data Store
- **Type**: {PostgreSQL / MongoDB / etc.}
- **Schema**: `{path_to_migrations}`
- **Isolation**: private database / private schema

## SLOs
| SLI | Target |
|-----|--------|
| Availability | {99.9%} |
| p99 latency | {< 500ms} |
| Error rate | {< 0.1%} |

## Deployment
- **Strategy**: {canary / blue-green / rolling}
- **Rollback ETA**: {< 5 min}
- **Health endpoints**: `/health`, `/ready`
