---
name: iac-patterns
description: >
  Infrastructure-as-Code patterns: module design, state management, drift detection,
  policy-as-code, environment promotion, secret management, and import strategies.
  Activate when designing IaC modules, managing infrastructure state, or reviewing
  IaC configurations.
version: 1.0.0
argument-hint: "[IaC concern or module name]"
---

# Infrastructure-as-Code Patterns

## When to activate
- Designing or reviewing IaC module structure
- Managing remote state backends and locking
- Implementing drift detection or reconciliation
- Writing policy-as-code validation rules
- Planning environment promotion pipelines
- Handling secrets in IaC configurations
- Importing existing infrastructure into managed state
- Reducing blast radius of infrastructure changes

---

## Module Design

### Composable, Versioned, Documented Modules

Every IaC module should be self-contained, reusable, and independently versioned.

**Structure**:
```
modules/
  networking/
    main.tf          # Resource definitions
    variables.tf     # Input variables with descriptions and validation
    outputs.tf       # Output values for consumers
    versions.tf      # Provider and module version constraints
    README.md        # Usage examples and interface documentation
    tests/
      networking_test.go   # Integration tests
```

**Rules**:
- One module per logical infrastructure concern (networking, compute, storage, observability)
- Every input variable must have a `description` and a `type` constraint
- Every input variable with a finite set of valid values must use `validation` blocks
- Every output must have a `description`
- Pin module versions using semantic versioning — consumers reference `v1.2.0`, never `main`
- Modules must not contain hardcoded values for environment-specific settings (region, account, naming)
- Keep modules small — a module with more than 10 resources is likely doing too much

```hcl
# ✅ Good: variable with validation
variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ❌ Bad: no description, no validation, magic string
variable "env" {
  type = string
}
```

### Module Versioning Strategy

| Version bump | When |
|-------------|------|
| Patch (0.0.x) | Bug fix, documentation update, no interface change |
| Minor (0.x.0) | New optional variable, new output, new resource (additive) |
| Major (x.0.0) | Removed variable/output, renamed resource, state migration required |

Tag releases in the module repository. Consumer configurations pin to a specific version and upgrade deliberately.

---

## State Management

### Remote Backends

Always use a remote backend with locking and encryption:

```hcl
# Example: S3 + DynamoDB backend
terraform {
  backend "s3" {
    bucket         = "myorg-terraform-state"
    key            = "services/payment-api/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**Rules**:
- Never use local state in shared or production environments
- Enable server-side encryption on the state storage backend
- Enable state locking to prevent concurrent modifications
- Use separate state files per environment and per service — never share a single state file across environments
- Restrict access to state storage to the CI/CD pipeline service account and a break-glass admin role
- State files contain sensitive data (resource IDs, connection strings) — treat them as secrets

### State File Organisation

```
state/
  networking/
    dev.tfstate
    staging.tfstate
    prod.tfstate
  compute/
    dev.tfstate
    staging.tfstate
    prod.tfstate
```

One state file per (module, environment) pair. This limits blast radius and enables independent lifecycle management.

---

## Drift Detection and Reconciliation

Drift occurs when real infrastructure diverges from the declared state.

**Detection**:
```bash
# Run plan in CI on a schedule (e.g., daily) to detect drift
terraform plan -detailed-exitcode
# Exit code 0 = no changes, 1 = error, 2 = changes detected (drift)
```

**Reconciliation strategies**:
| Strategy | When to use |
|----------|-------------|
| Apply the plan | Drift is accidental — restore to declared state |
| Import the change | Drift is intentional (manual hotfix) — update state and code |
| Ignore temporarily | Drift is expected (ongoing migration) — document and track |

**Rules**:
- Run drift detection in CI at least daily for production environments
- Alert on drift — do not silently ignore it
- Every drift event must be resolved within 48 hours (apply, import, or document)
- Never manually edit infrastructure without a follow-up IaC update

---

## Policy-as-Code

Validate infrastructure configurations before applying them:

```python
# Example: policy rule — no public S3 buckets
def deny_public_buckets(plan):
    for resource in plan.resource_changes:
        if resource.type == "aws_s3_bucket":
            acl = resource.change.after.get("acl", "private")
            if acl == "public-read" or acl == "public-read-write":
                return f"DENY: S3 bucket {resource.address} has public ACL '{acl}'"
    return "PASS"
```

**Common policies**:
| Policy | Purpose |
|--------|---------|
| No public storage buckets | Prevent data exposure |
| Encryption at rest required | Compliance |
| No wildcard IAM permissions | Least privilege |
| Tags required (owner, environment, cost-centre) | Cost attribution and governance |
| Approved instance types only | Cost control |
| No ingress from 0.0.0.0/0 on non-HTTP ports | Network security |

**Rules**:
- Run policies in CI before `apply` — block non-compliant changes
- Policies must produce clear, actionable error messages
- Separate policies from infrastructure code — policies are organisational standards
- Version policies alongside infrastructure modules

---

## Environment Promotion

Promote identical configurations from dev through staging to prod:

```
dev → staging → prod
 │       │        │
 └───────┴────────┘
   Same module versions,
   different variable values
```

**Implementation**:
```hcl
# environments/dev/main.tf
module "api" {
  source      = "git::https://gitlab.example.com/infra/modules/api.git?ref=v1.3.0"
  environment = "dev"
  instance_count = 1
  instance_type  = "t3.small"
}

# environments/prod/main.tf
module "api" {
  source      = "git::https://gitlab.example.com/infra/modules/api.git?ref=v1.3.0"
  environment = "prod"
  instance_count = 3
  instance_type  = "t3.large"
}
```

**Rules**:
- Same module version across all environments — differences are in variables only
- Promote by updating the module version reference, not by copying code
- Changes must pass through dev and staging before reaching prod
- Use automated pipelines with manual approval gates for production promotion

---

## Secret Management in IaC

**Rule: never store secrets in state files, variable files, or version control.**

```hcl
# ❌ NEVER — secret in variable default or tfvars
variable "db_password" {
  default = "hunter2"
}

# ✅ ALWAYS — reference an external secret store
data "vault_generic_secret" "db" {
  path = "secret/services/payment-api/database"
}

resource "aws_db_instance" "main" {
  password = data.vault_generic_secret.db.data["password"]
}
```

**Strategies**:
| Approach | Description |
|----------|-------------|
| External secret store | Reference secrets from Vault, AWS Secrets Manager, Azure Key Vault at apply time |
| Encrypted variable files | Encrypt tfvars with SOPS or age; decrypt in pipeline only |
| CI/CD environment variables | Inject via pipeline variables; never commit to repository |

**Rules**:
- Use `sensitive = true` on variables and outputs that may contain secrets
- Enable state encryption — secrets resolved at apply time are stored in state
- Rotate secrets independently of infrastructure deployments
- Audit secret access logs from the external store

---

## Import Existing Resources

Bring manually created infrastructure under IaC management:

```bash
# Step 1: Write the resource block in code (matching current config)
# Step 2: Import into state
terraform import aws_s3_bucket.legacy_data my-legacy-bucket

# Step 3: Run plan — should show no changes if code matches reality
terraform plan
# If changes appear, adjust the code to match current state exactly

# Step 4: From this point forward, manage exclusively through IaC
```

**Rules**:
- Never modify imported resources in the same apply that imports them — import first, then modify in a separate change
- Verify with `plan` after import — a clean plan confirms code matches reality
- Document which resources were imported and when
- Import one resource at a time to isolate issues

---

## Blast Radius Control

Limit the scope of any single `apply` to reduce risk:

**Strategies**:
| Strategy | How |
|----------|-----|
| Small state files | One per (service, environment) — changes to payment-api cannot affect user-api |
| Targeted applies | `terraform apply -target=module.api` — apply only specific resources |
| Separate lifecycle stages | Network layer, compute layer, application layer as independent stacks |
| Plan review | Require human review of plan output before apply in production |

**Rules**:
- Never run `apply` without reviewing the plan first
- Production applies require at least one reviewer
- Use `-target` sparingly — it skips dependency validation; prefer proper state separation
- Monitor apply duration — applies that take > 10 minutes may indicate too-large state

---

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| Monolithic configuration | Single state file for all infrastructure; one change can break everything | Split into independent modules with separate state |
| Hardcoded values | Region, account ID, instance type embedded in resources | Use variables with validation and per-environment tfvars |
| Manual state edits | `terraform state mv` or editing state JSON directly | Use proper import/moved blocks; manual edits corrupt state |
| No lock file | Provider versions float between applies | Pin provider versions in `versions.tf` with lock file committed |
| Copy-paste modules | Duplicated module code across environments | Use versioned module references with environment-specific variables |
| Secrets in state without encryption | Credentials readable by anyone with state access | Enable backend encryption; use external secret stores |
| No drift detection | Manual changes accumulate silently | Scheduled plan-only CI runs with alerting |
| `apply -auto-approve` in production | No human review before destructive changes | Require manual approval gate in production pipelines |
