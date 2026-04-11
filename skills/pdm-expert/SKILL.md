---
name: pdm-expert
description: Expert in PDM package manager, Artifactory private PyPI integration, and CI/CD pipeline configuration from a PDM perspective. Covers source resolution, include_packages/exclude_packages mechanics, lock file strategies, credentials, and common pitfalls.
---

# PDM Expert

Deep knowledge of the [PDM](https://github.com/pdm-project/pdm) package manager — source index configuration, Artifactory integration, lock file strategies, CI/CD patterns, and all inner workings.

## When to Activate

- Configuring private PyPI sources (Artifactory, Nexus, devpi)
- Debugging `include_packages` / `exclude_packages` resolution issues
- Designing lock file strategies (`--static-urls`, cross-platform, lock targets)
- Setting up PDM in CI pipelines (GitLab CI, GitHub Actions, Docker)
- Diagnosing why packages resolve from the wrong source
- Credential and authentication configuration for private indexes
- PDM performance tuning (caching, parallel install, uv backend)

---

## Configuration Files and Precedence

Three locations, highest to lowest priority:

| Priority | File | Scope |
|----------|------|-------|
| 1 | `<PROJECT_ROOT>/pdm.toml` | Project-local (gitignored — private overrides) |
| 2 | `~/.config/pdm/config.toml` | User-level |
| 3 | `/etc/xdg/pdm/config.toml` | System-wide |

**Rule**: Shared team settings go in `pyproject.toml` (checked in). Credentials and local overrides go in `pdm.toml` or `~/.config/pdm/config.toml` (not checked in).

```bash
pdm config                          # show all resolved config
pdm config --local <key> <value>    # write to pdm.toml
pdm config -d <key>                 # delete/unset
```

---

## Package Index (Source) Configuration

### In `pyproject.toml` (shared)

```toml
[[tool.pdm.source]]
name = "artifactory"
url = "https://artifactory.example.com/artifactory/api/pypi/pypi-local/simple"
verify_ssl = true
include_packages = ["<your-project>", "myorg-*"]

[[tool.pdm.source]]
name = "pypi"
url = "https://pypi.org/simple"
```

### Source fields

| Field | Required | Notes |
|-------|----------|-------|
| `name` | Yes | Use `"pypi"` to replace the default PyPI index |
| `url` | Yes | Index URL; supports `${ENV_VAR}` expansion |
| `verify_ssl` | No (default `true`) | |
| `username` / `password` | No | Prefer config file or env var injection |
| `type` | No (default `"index"`) | `"index"` (PEP 503) or `"find_links"` |
| `include_packages` | No | Glob list — exclusive binding |
| `exclude_packages` | No | Glob list — exclusion |

### Via `pdm config` (not shared)

```bash
pdm config pypi.url "https://test.pypi.org/simple"
pdm config pypi.extra.url "https://extra.pypi.org/simple"
```

---

## Source Resolution Order

Without `respect-source-order`: all sources race — highest version across all sources wins.

With `respect-source-order = true`: waterfall — first source wins; next source only tried if package not found.

```toml
[tool.pdm.resolution]
respect-source-order = true
```

### Ignoring user-level stored indexes in CI

```bash
PDM_IGNORE_STORED_INDEX=true pdm install
# or in pdm.toml:
# pypi.ignore_stored_index = true
```

**Always set this in CI** — prevents developer's personal `~/.config/pdm/config.toml` sources from leaking into the build.

---

## `include_packages` and `exclude_packages` — Inner Workings

```toml
[[tool.pdm.source]]
name = "artifactory"
url = "..."
include_packages = ["<your-project>", "myorg-*"]
exclude_packages = ["requests"]
```

### Rules

1. **`include_packages` is EXCLUSIVE**: when a package name matches, it is fetched **only** from this source. It will NOT fall back to other sources if not found here.
2. **`exclude_packages`**: the source is never considered for matching packages, even if they would otherwise be eligible.
3. **Glob patterns**, not regex. Case-insensitive.
4. **`<your-project>` does NOT match `<your-project>`** (no suffix). To match both: `["<your-project>", "<your-project>"]`.

### Common pitfall: glob too broad or too narrow

```toml
# Matches <your-project>, <your-project>, etc. — NOT plain "<your-project>"
include_packages = ["<your-project>"]

# Matches ONLY <your-project> — nothing else from Artifactory
include_packages = ["<your-project>"]

# Matches both the base package AND all sub-packages
include_packages = ["<your-project>", "<your-project>"]
```

### Why `<your-project>` breaks CI (the red build problem)

If the Artifactory index only contains `<your-project>` (not other `<your-project>` packages), using `<your-project>` may cause PDM to try resolving other transitive deps from Artifactory where they don't exist, or bind packages to Artifactory that belong on PyPI. Using the exact name `<your-project>` scopes the binding precisely.

### Belt-and-suspenders pattern (include + respect-source-order)

```toml
[tool.pdm.resolution]
respect-source-order = true

[[tool.pdm.source]]
name = "artifactory"
url = "https://..."
include_packages = ["<your-project>"]

[[tool.pdm.source]]
name = "pypi"
url = "https://pypi.org/simple"
```

`include_packages` forces exact routing; `respect-source-order` controls fallback for everything else.

---

## Credentials and Authentication

### Option 1: Environment variable expansion in URL (CI-friendly)

```toml
[[tool.pdm.source]]
name = "artifactory"
url = "https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@artifactory.example.com/api/pypi/pypi-local/simple"
```

### Option 2: Split config (recommended for teams)

`pyproject.toml` (checked in — no secrets):
```toml
[[tool.pdm.source]]
name = "artifactory"
url = "https://artifactory.example.com/api/pypi/pypi-local/simple"
```

CI or `pdm.toml` (not checked in):
```bash
pdm config pypi.artifactory.username "${ARTIFACTORY_USER}"
pdm config pypi.artifactory.password "${ARTIFACTORY_TOKEN}"
```

### Important: no `PDM_PYPI_<NAME>_*` env vars for named sources

Only the **default** `pypi` source has direct env var support:
- `PDM_PYPI_URL`, `PDM_PYPI_USERNAME`, `PDM_PYPI_PASSWORD`, `PDM_PYPI_VERIFY_SSL`

For named sources (e.g. `artifactory`), you must use `pdm config` or embed credentials in the URL with `${ENV_VAR}` expansion.

---

## Lock File Strategies

```bash
pdm lock -S <strategy>        # enable strategy
pdm lock -S no_<strategy>     # disable strategy
```

| Strategy | Default | Description |
|----------|---------|-------------|
| `cross_platform` | **On** | Include wheels for all platforms. Portable lockfile. |
| `static_urls` | Off | Store full download URLs in lockfile — faster CI install, no index lookup at install time. |
| `direct_minimal_versions` | Off | Resolve minimum versions (compatibility testing). |
| `inherit_metadata` | On | Inherit groups/markers from parent packages. |

### `--static-urls` with Artifactory

```bash
pdm lock --static-urls
```

- Lockfile stores full Artifactory download URLs.
- CI needs network access to Artifactory at install time (download), but **not** for index queries.
- If Artifactory URL changes → lockfile is invalid → `pdm lock --refresh` to regenerate.

### Shorthand flags

```bash
pdm lock --static-urls          # = -S static_urls
pdm lock --no-static-urls       # = -S no_static_urls
pdm lock --no-cross-platform    # = -S no_cross_platform
pdm lock --check                # fail if lockfile is stale
pdm lock --refresh              # refresh hashes, keep versions
```

### Platform-specific locks (v2.17.0+)

```bash
pdm lock --python=">=3.11" --platform=linux --lockfile=linux-py311.lock
pdm lock --python=">=3.11" --platform=windows --lockfile=win-py311.lock
```

Merge multiple targets into one file:
```bash
pdm lock --python=">=3.10"
pdm lock --python="<3.10" --append
```

---

## `pdm install` vs `pdm sync` vs `pdm update`

| Command | Lockfile | Resolves | Use case |
|---------|----------|---------|---------|
| `pdm install` | Creates/updates if stale | Yes | Local dev |
| `pdm install --frozen-lockfile` | Read-only; fails if stale | No | CI strict |
| `pdm sync` | Read-only | No | CI fast |
| `pdm update` | Regenerates | Yes | Upgrading deps |

**CI best practice**: use `pdm sync` or `pdm install --frozen-lockfile`. Never plain `pdm install` in CI — it may silently regenerate the lockfile.

### Useful flags

```bash
pdm install --prod --no-editable     # production / Docker
pdm install --check                  # verify lockfile is current
pdm sync --clean                     # remove packages no longer in lockfile
pdm install -G test -G lint          # include named groups
pdm install --no-self                # skip installing the project package itself
```

---

## Key `PDM_*` Environment Variables

| Env Var | Default | Use |
|---------|---------|-----|
| `PDM_CHECK_UPDATE` | `True` | Set `false` in CI to suppress version check |
| `PDM_IGNORE_STORED_INDEX` | `False` | Set `true` in CI to ignore user-level indexes |
| `PDM_PYPI_URL` | `https://pypi.org/simple` | Override default index |
| `PDM_PYPI_USERNAME` / `PDM_PYPI_PASSWORD` | — | Auth for default pypi source only |
| `PDM_PYPI_VERIFY_SSL` | `True` | SSL for default source |
| `PDM_USE_UV` | `False` | Use uv resolver/installer (faster) |
| `PDM_INSTALL_PARALLEL` | `True` | Parallel install |
| `PDM_IGNORE_SAVED_PYTHON` | — | Force venv Python re-detection in CI |
| `PDM_LOCK_FORMAT` | `pdm` | `pdm` or `pylock` |
| `PDM_VENV_IN_PROJECT` | `True` | Create `.venv` in project root |
| `PDM_CACHE_DIR` | `~/.cache/pdm` | Cache location |
| `PDM_BUILD_ISOLATION` | `True` | PEP 517 build isolation |

---

## CI/CD Patterns

### GitLab CI — Artifactory private source

```yaml
.pdm_setup: &pdm_setup
  before_script:
    - pip install -U pdm
    - pdm config pypi.url $PIP_INDEX_URL
    - pdm config pypi.artifactory.url $PIP_<your-project>
    - pdm config pypi.artifactory.include_packages "<your-project>"

test:
  <<: *pdm_setup
  script:
    - PDM_CHECK_UPDATE=false pdm sync -G test
    - pdm run pytest
```

### GitHub Actions

```yaml
- uses: pdm-project/setup-pdm@v4
  with:
    python-version: "3.11"
- run: PDM_CHECK_UPDATE=false pdm sync --prod --no-editable
```

### Docker multi-stage

```dockerfile
FROM python:3.11-slim AS builder
RUN pip install -U pdm
ENV PDM_CHECK_UPDATE=false
COPY pyproject.toml pdm.lock ./
RUN pdm install --check --prod --no-editable

FROM python:3.11-slim
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
```

### Lock regeneration job (CI)

When you need CI to auto-regenerate `pdm.lock` (e.g. after `pyproject.toml` changes), use a separate job with PyPI (not Artifactory) as the sole index — Artifactory often cannot proxy all packages needed for `pdm lock`:

```yaml
lock-update:
  before_script:
    - pip install -U pdm
    - pdm config pypi.url https://pypi.org/simple
    - pdm config pypi.artifactory.url $PIP_<your-project>
    - pdm config pypi.artifactory.include_packages "<your-project>"
  script:
    - pdm lock --static-urls
    - git add pdm.lock && git diff --cached --quiet || git commit -m "chore: regenerate pdm.lock"
    - git push "https://ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" HEAD:${CI_COMMIT_REF_NAME}
```

---

## Default Flags (`tool.pdm.options`)

Inject flags automatically for every invocation of a command:

```toml
[tool.pdm.options]
add = ["--no-isolation", "--no-self"]
install = ["--no-self"]
lock = ["--no-cross-platform"]
```

---

## Dependency Resolution Overrides

```toml
[tool.pdm.resolution.overrides]
urllib3 = ">=1.26.2"
pytz = "https://mypypi.org/packages/pytz-2020.9-py3-none-any.whl"
```

Exclude packages from lockfile entirely:
```toml
[tool.pdm.resolution]
excludes = ["requests"]
```

---

## Common Pitfalls Checklist

1. **`<your-project>` glob does not match `<your-project>`** — add both if needed.
2. **`include_packages` is exclusive** — if Artifactory doesn't have the package, install fails; no fallback.
3. **User-level indexes bleed into CI** — always set `PDM_IGNORE_STORED_INDEX=true` in CI.
4. **Named sources have no `PDM_PYPI_<NAME>_*` env vars** — use URL embedding or `pdm config`.
5. **`pdm install` in CI may regenerate lockfile** — use `pdm sync` or `--frozen-lockfile`.
6. **Static URL lockfile + Artifactory URL change** — run `pdm lock --refresh` after any URL migration.
7. **`respect-source-order` can cause version downgrades** — enabling mid-project may switch resolution winner.
8. **Editable installs only in `dev` group** — `pdm add -e` outside dev raises `PdmUsageError`.
9. **`pdm lock` on CI via Artifactory may fail** for packages Artifactory cannot proxy — use `pypi.org` for lock generation, Artifactory only for install.
10. **`include_packages` with too-broad glob (`<your-project>`)** — binds ALL `<your-project>` packages exclusively to Artifactory; use the exact package name to scope precisely.
