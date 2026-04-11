---
name: skill-development
description: >
  Guide for creating and improving Claude Code skills. This skill should be used when
  the user wants to "create a skill", "add a new skill", "improve a skill", "write a
  SKILL.md", or needs guidance on skill structure, progressive disclosure, or bundled
  resources (scripts, references, assets).
version: 1.0.0
---

# Skill Development

Create, improve, and validate Claude Code skills. Follow this guide to produce
well-structured skills that load efficiently and provide the right information
at the right time.

## When to Activate

- Creating a new skill from scratch
- Improving an existing skill (restructuring, adding resources)
- Writing or reviewing a SKILL.md file
- Deciding what belongs in the skill body vs. references vs. scripts
- Validating skill quality before shipping

---

## Anatomy of a Skill

A skill is a directory containing a `SKILL.md` file and optional bundled resources.

```
skill-name/
  SKILL.md              # Required. Frontmatter + body.
  scripts/              # Optional. Executable files (sh, py, sql).
  refs/                 # Optional. Reference documents loaded on demand.
  templates/            # Optional. Output templates and starter files.
  assets/               # Optional. Images, diagrams, other static files.
```

### SKILL.md Structure

Every SKILL.md has two parts:

1. **Frontmatter** (YAML between `---` delimiters) — metadata always available to the system
2. **Body** (Markdown after frontmatter) — loaded when the skill is triggered

Frontmatter fields:

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | Yes | Unique identifier, matches directory name |
| `description` | Yes | Third-person description with trigger phrases |
| `version` | Yes | SemVer string |

See `templates/SKILL.md.template` for a starter file with TODO placeholders.

---

## Progressive Disclosure

Skills use three levels of disclosure to minimise context consumption:

### Level 1: Metadata (Always Loaded)

The frontmatter `name` and `description` fields are always visible to the system.
Use the description to declare when the skill should activate. Include trigger
phrases that match natural user requests.

**Write the description in third person:**
```yaml
description: >
  This skill should be used when the user wants to "design an API",
  "create an OpenAPI spec", "review REST endpoints", or needs guidance
  on resource modelling, versioning, or pagination.
```

### Level 2: Body (On Trigger)

The Markdown body loads when the skill is activated by keyword match or
explicit invocation. Keep the body focused and actionable.

**Rules for the body:**
- Write in imperative/infinitive form, verb-first ("Create", "Add", "Validate")
- Target 1500-2000 words; never exceed 3000
- Use tables for quick-reference lookups
- Use code blocks for patterns the user will copy
- Reference bundled resources by relative path — do not duplicate their content
- Structure with clear H2/H3 headings for scanability

### Level 3: Resources (On Demand)

Bundled files in `scripts/`, `refs/`, `templates/`, and `assets/` load only
when explicitly requested or when the body references them. This keeps the
base context small while making deep knowledge available.

---

## Creation Process

Follow these six steps to create a new skill.

### Step 1: Understand the Domain

Identify the skill's scope before writing anything.

- Define the target audience (who uses this skill?)
- List 5-10 trigger phrases users would naturally say
- Identify 3-5 key decisions or patterns the skill must cover
- Check for overlap with existing skills — merge or cross-reference, do not duplicate

### Step 2: Plan Resources

Decide what belongs in the body vs. bundled resources.

| Content Type | Where | Why |
|-------------|-------|-----|
| Quick-reference tables | Body | Always needed, scannable |
| Step-by-step workflows | Body | Core value of the skill |
| Code patterns (< 20 lines) | Body | Copy-paste ready |
| Detailed reference docs | `refs/` | Loaded on demand, avoids bloat |
| Executable checks/linters | `scripts/` | Deterministic, token-efficient |
| Output templates | `templates/` | Not loaded into context |
| Diagrams, images | `assets/` | Not loaded into context |

**Key principle:** if content exceeds 30 lines or is only needed in specific
situations, move it to a resource file and reference it from the body.

### Step 3: Create the Directory Structure

```bash
mkdir -p skills/my-skill/{scripts,refs,templates}
```

Create `SKILL.md` with frontmatter first. Fill in name, description (with
trigger phrases), and version. Copy from `templates/SKILL.md.template` if
available.

### Step 4: Write the Body

Follow this outline:

1. **Title** — H1, matches the skill name in human-readable form
2. **Opening paragraph** — one sentence stating what the skill does
3. **When to Activate** — bullet list of activation scenarios
4. **Core sections** (H2) — the main knowledge, patterns, workflows
5. **Related** — cross-references to other skills, agents, resources

**Writing rules:**
- Use imperative mood: "Add an index" not "You should add an index"
- Start list items and headings with a verb
- Keep sentences short — one idea per sentence
- Avoid filler phrases ("it is important to note that")
- Use specific, concrete examples over abstract descriptions

### Step 5: Validate

Run the validation script or manually check:

```bash
bash scripts/validate_skill.sh skills/my-skill
```

Or check manually:

- [ ] Frontmatter has `name`, `description`, `version`
- [ ] Description uses third-person and includes trigger phrases
- [ ] Body uses imperative style (verb-first)
- [ ] Body word count is 1500-3000
- [ ] All resource files referenced in the body exist
- [ ] No content duplicated between body and refs
- [ ] Code examples are copy-paste ready (no pseudo-code)
- [ ] Directory name matches frontmatter `name`

### Step 6: Iterate

After first use, refine based on activation patterns:

- Does the skill activate when expected? Adjust description trigger phrases.
- Is the body too long? Move detail to `refs/`.
- Are users asking follow-up questions the skill should answer? Add content.
- Are scripts failing? Fix and add error handling.

---

## Bundled Resources

### scripts/

Executable files that perform deterministic tasks. Scripts are token-efficient
because they produce structured output without loading large documents into
context.

**Guidelines:**
- Make scripts executable (`chmod +x`)
- Add a usage comment at the top of every script
- Accept file/directory paths as arguments
- Exit with 0 on success, non-zero on failure
- Print structured output (one finding per line, or JSON)
- Never require interactive input

**Good candidates for scripts:**
- Linters and validators (SQL checks, schema validation)
- Code generators (boilerplate, migration stubs)
- Audit tools (dependency checks, coverage reports)

### refs/

Reference documents loaded on demand. Use refs for detailed knowledge that
would bloat the SKILL.md body but is needed for deep dives.

**Guidelines:**
- Use Markdown format for consistency
- Name files descriptively: `REFERENCES.md`, `migration-patterns.md`
- Do not duplicate content that already exists in the SKILL.md body
- Include external links with brief descriptions
- Keep each ref file focused on one topic

### templates/

Output files that serve as starting points for user work. Templates are not
loaded into context — they are copied and customised.

**Guidelines:**
- Use TODO placeholders for values the user must fill in
- Include comments explaining each section
- Name files with their output format: `runbook.md`, `config.yaml`

### assets/

Static files (images, diagrams, data files) that support the skill. Assets
are never loaded into context automatically.

---

## Quality Checklist

Run this checklist before considering a skill complete.

### Frontmatter
- [ ] `name` matches directory name
- [ ] `description` is third-person with trigger phrases
- [ ] `version` follows SemVer

### Body
- [ ] Opens with a one-line summary
- [ ] "When to Activate" section present
- [ ] Uses imperative/infinitive style throughout
- [ ] Word count between 1500 and 3000
- [ ] Tables used for quick-reference data
- [ ] Code blocks are copy-paste ready
- [ ] H2/H3 hierarchy is logical and scannable

### Resources
- [ ] Every resource file is referenced in the body
- [ ] No content duplicated between body and resources
- [ ] Scripts have usage comments and exit codes
- [ ] Templates have TODO placeholders
- [ ] Ref files do not duplicate the body

### Integration
- [ ] No overlap with existing skills (or cross-referenced)
- [ ] Related skills/agents listed in "Related" section
- [ ] Skill activates correctly on trigger phrases

---

## Anti-Patterns

Avoid these common mistakes when creating skills.

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Wall of text | Body exceeds 3000 words, wastes context | Move detail to refs/ |
| No trigger phrases | Skill never activates automatically | Add phrases to description |
| Duplicated content | Same info in body and refs | Keep in one place, reference the other |
| Pseudo-code examples | Users cannot copy-paste | Use real, runnable code |
| Missing resources | Body references files that do not exist | Create them or remove references |
| Overlapping skills | Two skills cover the same topic | Merge or clearly delineate scope |
| Interactive scripts | Scripts require user input at runtime | Accept args, use env vars |

---

## Related

- Reference: `refs/skill-anatomy.md` — detailed directory structure and resource type guidance
- Template: `templates/SKILL.md.template` — starter SKILL.md with TODO placeholders
- Script: `scripts/validate_skill.sh` — automated validation checks
