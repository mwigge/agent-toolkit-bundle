# Skill Anatomy — Detailed Reference

## Directory Structure

A minimal skill contains only `SKILL.md`. A fully-featured skill includes
bundled resources organised by type.

### Minimal Skill

```
my-skill/
  SKILL.md
```

Suitable for simple reference skills (cheat sheets, quick-reference patterns)
where all content fits in under 2000 words.

### Standard Skill

```
my-skill/
  SKILL.md
  refs/
    REFERENCES.md        # External links and detailed docs
  templates/
    output-template.md   # Starter file for user output
```

Suitable for most skills. The body contains actionable patterns; refs hold
supplementary links and deep-dive content.

### Full-Featured Skill

```
my-skill/
  SKILL.md
  scripts/
    validate.sh          # Automated checks
    generate.py          # Code generation
  refs/
    REFERENCES.md        # External links
    advanced-patterns.md # Deep-dive content
  templates/
    config.yaml          # Configuration template
    report.md            # Output report template
  assets/
    architecture.png     # Diagram
    sample-data.json     # Test fixture
```

Suitable for complex domains (database patterns, security review, observability)
where scripts automate repetitive checks and multiple output templates exist.

## When to Use Each Resource Type

### Use scripts/ when:

- A check can be automated (lint, validate, audit)
- Output is structured and deterministic
- The task would otherwise require the user to write boilerplate
- Token efficiency matters (run script vs. load large doc)

Examples: SQL linters, schema validators, coverage checkers, migration generators.

### Use refs/ when:

- Content is too detailed for the SKILL.md body (> 30 lines on a subtopic)
- External links need descriptions and context
- Advanced patterns are only needed occasionally
- Historical context or rationale needs preservation

Examples: REFERENCES.md (link collections), advanced-patterns.md, engine-specific
details, methodology documentation.

### Use templates/ when:

- Users need a starting point for a deliverable
- The output format is standardised (runbooks, reports, configs)
- TODO placeholders guide the user through required fields
- The template should not consume context when not in use

Examples: migration runbooks, audit reports, configuration files, PR description
templates.

### Use assets/ when:

- Content is binary or non-textual (images, diagrams)
- Data files support testing or demonstration
- Files are referenced by templates or documentation
- Content should never be loaded into the conversation context

Examples: architecture diagrams, sample datasets, logo files.

## Frontmatter Best Practices

### Name

- Use lowercase kebab-case: `database-patterns`, `skill-development`
- Match the directory name exactly
- Keep short but descriptive (2-3 words)

### Description

- Write in third person: "This skill should be used when..."
- Include 3-5 trigger phrases in quotes
- Cover both explicit invocations and keyword matches
- Keep under 300 characters for the first sentence

### Version

- Start at `1.0.0` for new skills
- Bump minor for new sections or resources
- Bump major for restructuring or scope changes
- Bump patch for typo fixes and minor corrections

## Body Organisation Patterns

### Pattern: Reference Skill

For skills that primarily provide lookup tables and quick patterns.

```
# Skill Name
One-line summary.

## When to Activate
- Bullet list

## Quick Reference
### Table 1
### Table 2

## Common Patterns
### Pattern A (with code block)
### Pattern B (with code block)

## Anti-Patterns
### What to avoid

## Related
- Cross-references
```

### Pattern: Workflow Skill

For skills that guide users through a multi-step process.

```
# Skill Name
One-line summary.

## When to Activate
- Bullet list

## Workflow Overview
1. Step 1
2. Step 2
3. Step 3

## Step 1: [Name]
### Details and code

## Step 2: [Name]
### Details and code

## Step 3: [Name]
### Details and code

## Troubleshooting
## Related
```

### Pattern: Audit/Review Skill

For skills that check code or systems against standards.

```
# Skill Name
One-line summary.

## When to Activate
- Bullet list

## Checklist
- [ ] Item 1
- [ ] Item 2

## Category 1
### What to check
### Common findings
### Remediation

## Category 2
### What to check
### Common findings
### Remediation

## Report Template
## Related
```
