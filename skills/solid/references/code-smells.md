# Code Smells

Code smells are surface indications of deeper design problems. When you spot one, stop and refactor before adding more code.

---

## Bloaters — Things That Grow Too Large

| Smell | Signs | Solution |
|-------|-------|----------|
| **Long Method** | Method > 10 lines | Extract Method, Compose Method Pattern |
| **Large Class** | Class > 50 lines, doing too much | Extract Class (SRP) |
| **Long Parameter List** | > 3 parameters | Introduce Parameter Object, value objects |
| **Data Clumps** | Same 3–4 fields always travel together | Extract Class |
| **Primitive Obsession** | Strings for emails, ints for money | Wrap in value objects |

---

## Object-Orientation Abusers

| Smell | Signs | Solution |
|-------|-------|----------|
| **Switch on Type** | `switch/if-else` chains on a type enum | Replace with Polymorphism |
| **Refused Bequest** | Subclass ignores inherited behaviour | Extract sibling class, flatten hierarchy |
| **Alternative Classes with Different Interfaces** | Two classes doing the same thing, different names | Rename, unify behind interface |
| **Temporary Field** | Instance variable only set sometimes | Extract Class, Introduce Null Object |

---

## Change Preventers

| Smell | Signs | Solution |
|-------|-------|----------|
| **Divergent Change** | One class changes for many different reasons | Split (SRP) |
| **Shotgun Surgery** | One change requires edits in many classes | Move Method/Field, inline classes |
| **Parallel Inheritance Hierarchies** | Adding a subclass requires adding another elsewhere | Merge hierarchies |

---

## Dispensables — Things That Shouldn't Be There

| Smell | Signs | Solution |
|-------|-------|----------|
| **Speculative Generality** | Abstractions for hypothetical future use | Remove — YAGNI |
| **Dead Code** | Unreachable / commented-out code | Delete it |
| **Lazy Class** | Class that does almost nothing | Inline or merge |
| **Duplicate Code** | Same logic in two or more places | Extract Method/Function (after Rule of Three) |
| **Data Class** | Class with only fields and getters/setters | Add behaviour, push logic in |

---

## Couplers — Tight Coupling Symptoms

| Smell | Signs | Solution |
|-------|-------|----------|
| **Feature Envy** | Method uses another class's data more than its own | Move Method to the envied class |
| **Inappropriate Intimacy** | Class accesses private parts of another | Extract Class, move fields/methods |
| **Message Chains** | `a.b().c().d()` | Hide Delegate, introduce method |
| **Middle Man** | Class only delegates to another | Remove Middle Man (inline) |

---

## Detection Checklist

When reviewing code, ask:
- [ ] Does any class do more than one thing?
- [ ] Is there a method longer than 10 lines?
- [ ] Are there more than 3 parameters on any function?
- [ ] Are there raw strings/ints representing domain concepts?
- [ ] Are there `switch`/`if-else` chains on a type field?
- [ ] Is there duplicated logic (appears three or more times)?
- [ ] Are there empty method bodies or `throw new Error("Not implemented")`?
- [ ] Does any method use another class's data more than its own?
- [ ] Are there abstractions that nobody uses yet?

---

## Refactoring Safety Rules

1. Tests must pass **before and after** every refactoring step
2. Refactoring never changes behaviour — if it does, it's a bug fix
3. Small, incremental steps — commit after each refactoring
4. Never combine a refactoring with a feature change in the same commit
