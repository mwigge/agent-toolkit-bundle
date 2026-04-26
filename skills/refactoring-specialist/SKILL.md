---
name: refactoring-specialist
description: >
  Code refactoring patterns: smell detection, extract/inline/move/rename
  transformations, migration strategies, technical debt management, and
  safe refactoring with test coverage. Activate when cleaning up code,
  reducing complexity, migrating patterns, or paying down tech debt.
version: 1.0.0
argument-hint: "[code smell, module, or refactoring goal]"
---

# Refactoring Specialist Skill

## When to activate
- Detecting and fixing code smells
- Extracting functions, classes, or modules
- Simplifying complex conditionals or loops
- Migrating from deprecated patterns to modern alternatives
- Reducing cyclomatic complexity
- Managing technical debt backlog
- Preparing code for new features (preparatory refactoring)
- Reviewing code for maintainability

---

## Refactoring Safety Rules

1. **Tests must pass before and after every refactoring step**
2. **Refactoring does not change behaviour** — if behaviour changes, it is a bug fix or feature
3. **Small, incremental steps** — commit after each refactoring; do not combine multiple refactorings
4. **One refactoring per commit** — makes reverting safe
5. **Run the full test suite after each step** — not just related tests
6. **Never refactor and add features in the same commit**

---

## Code Smell Catalogue

### Bloaters (code that grows too large)

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Long method** | > 20 lines or > 3 levels of nesting | Extract Method |
| **Large class** | > 200 lines or > 10 methods | Extract Class |
| **Long parameter list** | > 4 parameters | Introduce Parameter Object |
| **Primitive obsession** | Raw strings/ints for domain concepts | Replace Primitive with Value Object |
| **Data clumps** | Same group of fields in multiple places | Extract Class |

### Object-orientation abusers

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Switch statements** | Repeated if/elif or match on type | Replace Conditional with Polymorphism |
| **Refused bequest** | Subclass ignores parent methods | Replace Inheritance with Composition |
| **Feature envy** | Method uses another class more than its own | Move Method |
| **Inappropriate intimacy** | Classes access each other's internals | Move Method/Field, Extract Class |

### Change preventers

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Divergent change** | One class changed for many different reasons | Extract Class (SRP) |
| **Shotgun surgery** | One change requires edits in many classes | Move Method/Field to consolidate |
| **Parallel inheritance** | Adding subclass in one hierarchy requires adding in another | Merge hierarchies |

### Dispensables

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Dead code** | Unreachable code, unused variables | Remove Dead Code |
| **Speculative generality** | Abstract classes with single implementation | Collapse Hierarchy, Inline Class |
| **Duplicate code** | Same structure in 2+ places | Extract Method/Class |
| **Comments explaining "what"** | Comment restates the code | Rename to make self-documenting |

---

## Core Refactoring Patterns

### Extract Method

Before:
```python
def process_experiment(experiment: dict) -> dict:
    # Validate experiment
    if not experiment.get("name"):
        raise ValueError("Missing name")
    if not experiment.get("target"):
        raise ValueError("Missing target")
    if experiment.get("duration", 0) > 3600:
        raise ValueError("Duration too long")

    # Calculate score
    base_score = experiment["probes_passed"] / experiment["probes_total"]
    weight = 1.0 if experiment["scope"] == "production" else 0.5
    final_score = base_score * weight

    return {"name": experiment["name"], "score": final_score}
```

After:
```python
def process_experiment(experiment: dict) -> dict:
    _validate_experiment(experiment)
    score = _calculate_score(experiment)
    return {"name": experiment["name"], "score": score}


def _validate_experiment(experiment: dict) -> None:
    if not experiment.get("name"):
        raise ValueError("Missing name")
    if not experiment.get("target"):
        raise ValueError("Missing target")
    if experiment.get("duration", 0) > 3600:
        raise ValueError("Duration too long")


def _calculate_score(experiment: dict) -> float:
    base_score = experiment["probes_passed"] / experiment["probes_total"]
    weight = 1.0 if experiment["scope"] == "production" else 0.5
    return base_score * weight
```

### Replace Conditional with Polymorphism

Before:
```python
def calculate_blast_radius(fault_type: str, target: dict) -> str:
    if fault_type == "latency":
        return f"Service {target['name']} and upstream callers"
    elif fault_type == "kill":
        return f"Instance {target['instance_id']} only"
    elif fault_type == "network_partition":
        return f"Zone {target['zone']} isolated from cluster"
    else:
        return "Unknown blast radius"
```

After:
```python
from abc import ABC, abstractmethod


class FaultStrategy(ABC):
    @abstractmethod
    def blast_radius(self, target: dict) -> str: ...


class LatencyFault(FaultStrategy):
    def blast_radius(self, target: dict) -> str:
        return f"Service {target['name']} and upstream callers"


class KillFault(FaultStrategy):
    def blast_radius(self, target: dict) -> str:
        return f"Instance {target['instance_id']} only"


class NetworkPartitionFault(FaultStrategy):
    def blast_radius(self, target: dict) -> str:
        return f"Zone {target['zone']} isolated from cluster"


STRATEGIES: dict[str, FaultStrategy] = {
    "latency": LatencyFault(),
    "kill": KillFault(),
    "network_partition": NetworkPartitionFault(),
}


def calculate_blast_radius(fault_type: str, target: dict) -> str:
    strategy = STRATEGIES.get(fault_type)
    if strategy is None:
        raise ValueError(f"Unknown fault type: {fault_type}")
    return strategy.blast_radius(target)
```

### Introduce Parameter Object

Before:
```python
def create_experiment(
    name: str,
    target_service: str,
    fault_type: str,
    duration_s: int,
    delay_ms: int,
    scope: str,
    abort_threshold: float,
) -> dict:
    ...
```

After:
```python
from dataclasses import dataclass


@dataclass(frozen=True)
class ExperimentConfig:
    name: str
    target_service: str
    fault_type: str
    duration_s: int
    delay_ms: int = 0
    scope: str = "service"
    abort_threshold: float = 0.05


def create_experiment(config: ExperimentConfig) -> dict:
    ...
```

### Replace Inheritance with Composition

Before:
```python
class BaseProbe:
    def execute(self) -> ProbeResult: ...
    def format_output(self) -> str: ...
    def send_notification(self) -> None: ...  # not all probes need this


class HttpProbe(BaseProbe):
    def execute(self) -> ProbeResult: ...
    def send_notification(self) -> None:
        pass  # refused bequest — does nothing
```

After:
```python
from typing import Protocol


class Probe(Protocol):
    def execute(self) -> ProbeResult: ...


class Notifier(Protocol):
    def notify(self, result: ProbeResult) -> None: ...


class HttpProbe:
    def execute(self) -> ProbeResult: ...


class SlackNotifier:
    def notify(self, result: ProbeResult) -> None: ...


# Compose at the call site
def run_probe_with_notification(probe: Probe, notifier: Notifier | None = None) -> ProbeResult:
    result = probe.execute()
    if notifier and not result.passed():
        notifier.notify(result)
    return result
```

---

## Migration Strategies

### Strangler fig pattern

For migrating from a monolith to microservices or from legacy code:

1. **Identify** a seam in the existing code
2. **Build** the new implementation alongside the old
3. **Route** traffic/calls to the new implementation (behind feature flag)
4. **Verify** the new implementation with parallel running
5. **Remove** the old implementation once verified

### Branch by abstraction

For replacing a dependency or subsystem:

1. **Create** an abstraction (interface/protocol) over the existing implementation
2. **Modify** all callers to use the abstraction
3. **Build** the new implementation of the abstraction
4. **Switch** to the new implementation (via config or feature flag)
5. **Remove** the old implementation

```python
from typing import Protocol


# Step 1: Create abstraction
class ExperimentRepository(Protocol):
    async def get(self, experiment_id: str) -> dict: ...
    async def save(self, experiment: dict) -> str: ...


# Step 2: Wrap existing implementation
class LegacySqlRepository:
    async def get(self, experiment_id: str) -> dict: ...
    async def save(self, experiment: dict) -> str: ...


# Step 3: New implementation
class AsyncPgRepository:
    async def get(self, experiment_id: str) -> dict: ...
    async def save(self, experiment: dict) -> str: ...


# Step 4: Switch via configuration
def get_repository(use_new: bool = False) -> ExperimentRepository:
    if use_new:
        return AsyncPgRepository()
    return LegacySqlRepository()
```

---

## Technical Debt Management

### Debt classification

| Type | Example | Priority |
|------|---------|----------|
| **Deliberate prudent** | "We know this is a shortcut; we will fix it next sprint" | Plan into backlog |
| **Deliberate reckless** | "We do not have time for tests" | Fix immediately |
| **Inadvertent prudent** | "Now we know a better way to do this" | Refactor when touching the area |
| **Inadvertent reckless** | "What is a layered architecture?" | Training + refactoring sprint |

### Debt tracking

```python
# Use TODO comments with a ticket reference — never bare TODOs
# Good:
# TODO(CLS-42): replace raw SQL with repository pattern
# TODO(CLS-99): extract this into a shared utility

# Bad:
# TODO: fix this later
# HACK: workaround for now
```

### Refactoring prioritisation

Score each debt item:

| Factor | Weight | Score (1-5) |
|--------|--------|-------------|
| Frequency of change in affected area | 3x | How often is this code modified? |
| Impact on development speed | 2x | How much does it slow down changes? |
| Risk of bugs | 2x | How likely is a defect from this debt? |
| Effort to fix | 1x | How hard is the refactoring? (invert: 5=easy) |

Priority = sum of (weight x score). Address highest-priority items first.

---

## Complexity Metrics

### Cyclomatic complexity targets

| Complexity | Rating | Action |
|-----------|--------|--------|
| 1-5 | Simple | No action needed |
| 6-10 | Moderate | Monitor, refactor if growing |
| 11-20 | Complex | Refactor — extract methods |
| 21+ | Very complex | Mandatory refactoring |

### Measuring complexity

```bash
# Python — radon
radon cc src/ -a -s -n C  # show functions with complexity >= C

# Python — ruff
ruff check --select C901 src/  # McCabe complexity

# TypeScript — eslint
# In eslint.config.js: complexity rule
```

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Refactoring without tests | Write characterisation tests first |
| Big-bang refactoring | Small, incremental steps with commits |
| Refactoring + feature in same commit | Separate commits: refactor first, then feature |
| Premature abstraction | Wait until you see duplication in 3+ places |
| Renaming without updating all references | Use IDE refactoring tools or `grep` to find all usages |
| Refactoring code you do not understand | Read and understand first; add characterisation tests |
| Gold-plating during refactoring | Stop when the code is clean enough for the current task |
| No tracking of tech debt | Use TODO(TICKET) comments; maintain a debt backlog |
