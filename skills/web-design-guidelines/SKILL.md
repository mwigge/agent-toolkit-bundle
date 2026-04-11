---
name: web-design-guidelines
description: Review UI code for Web Interface Guidelines compliance. Use when asked to "review my UI", "check accessibility", "audit design", "review UX", or "check my site against best practices".
argument-hint: <file-or-pattern>
metadata:
  author: vercel
  version: "1.0.0"
---

# Web Interface Guidelines

Review files for compliance with Web Interface Guidelines.

## How It Works

1. Fetch the latest guidelines from the source URL below
2. Read the specified files (or prompt user for files/pattern)
3. Check against all rules in the fetched guidelines
4. Output findings in the terse `file:line` format

## Guidelines Source

Fetch fresh guidelines before each review:

```
https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md
```

Use WebFetch to retrieve the latest rules. The fetched content contains all the rules and output format instructions.

## Usage

When a user provides a file or pattern argument:
1. Fetch guidelines from the source URL above
2. Read the specified files
3. Apply all rules from the fetched guidelines
4. Output findings using the format specified in the guidelines

If no files specified, ask the user which files to review.

## WCAG 2.1 Accessibility

### POUR Principles (Level AA)

All web interfaces must satisfy four foundational principles:

| Principle | Meaning | Key requirements |
|-----------|---------|------------------|
| **Perceivable** | Content must be presentable in ways all users can perceive | Text alternatives, captions, sufficient contrast, resizable text |
| **Operable** | UI must be operable by all users | Keyboard accessible, enough time, no seizure triggers, navigable |
| **Understandable** | Content and UI must be understandable | Readable, predictable, input assistance |
| **Robust** | Content must be robust enough for diverse user agents | Valid markup, compatible with assistive technologies |

### Semantic HTML

Use native HTML elements before reaching for ARIA:

```html
<!-- ✅ Correct: semantic landmarks -->
<header>...</header>
<nav aria-label="Main navigation">...</nav>
<main>
  <article>
    <h1>Page Title</h1>
    <section aria-labelledby="section-heading">
      <h2 id="section-heading">Section</h2>
    </section>
  </article>
</main>
<aside aria-label="Related content">...</aside>
<footer>...</footer>

<!-- ❌ Wrong: div soup with ARIA bolted on -->
<div role="banner">...</div>
<div role="navigation">...</div>
<div role="main">...</div>
```

**Rules**:
- Use heading levels (`h1`–`h6`) in logical order — never skip levels
- Every page must have exactly one `h1`
- Use `<button>` for actions, `<a>` for navigation — never use `<div onclick>`
- Every `<img>` must have an `alt` attribute (empty `alt=""` for decorative images)
- Use `aria-label` or `aria-labelledby` only when visible text is insufficient
- First rule of ARIA: do not use ARIA if a native HTML element provides the semantics

### Keyboard Navigation

All interactive elements must be fully operable with keyboard alone:

- **Tab order** must follow logical reading order (use `tabindex="0"` to add to flow, never use positive `tabindex` values)
- **Focus indicator** must be visible — never set `outline: none` without providing an alternative focus style
- **Skip links** — provide "Skip to main content" link as the first focusable element
- **Custom widgets** must implement the expected keyboard pattern from WAI-ARIA Authoring Practices (e.g., arrow keys for tabs, Enter/Space for buttons)
- **Trap focus** inside modal dialogs — Tab must cycle within the dialog, not escape to background content
- **Escape key** must close modals, dropdowns, and popups

### Color Contrast

| Element | Minimum ratio | WCAG criterion |
|---------|---------------|----------------|
| Normal text (< 18pt / < 14pt bold) | 4.5:1 | 1.4.3 AA |
| Large text (>= 18pt / >= 14pt bold) | 3:1 | 1.4.3 AA |
| UI components and graphical objects | 3:1 | 1.4.11 AA |

**Rules**:
- Never rely on color alone to convey information — always pair with text, icons, or patterns
- Test with both light and dark themes
- Check contrast of text on images and gradients at the lowest-contrast point
- Validate with a contrast checker tool during development

### Screen Reader Testing

Test with at least two assistive technologies from different categories:

| Platform | Screen reader | Browser pairing |
|----------|---------------|-----------------|
| macOS / iOS | VoiceOver | Safari |
| Windows | NVDA | Firefox or Chrome |
| Windows | JAWS | Chrome or Edge |
| Android | TalkBack | Chrome |

**Testing checklist**:
- [ ] All interactive elements are announced with correct role and state
- [ ] Form inputs have associated labels (`<label for="...">` or `aria-labelledby`)
- [ ] Dynamic content updates are announced via `aria-live` regions
- [ ] Error messages are associated with their form fields via `aria-describedby`
- [ ] Tables have proper `<th>` headers with `scope` attributes

### Focus Management for SPAs

Single-page applications must manage focus explicitly when content changes:

- **Route changes**: move focus to the new page's `h1` or main content area after navigation
- **Dynamic content**: when content loads asynchronously, announce it via `aria-live="polite"` or move focus to the new content
- **Deletion**: when an item is removed from a list, move focus to the previous item, next item, or a logical container
- **Loading states**: announce loading with `aria-busy="true"` on the updating region

```html
<!-- Live region for async updates -->
<div aria-live="polite" aria-atomic="true" class="sr-only">
  <!-- Inject status messages here -->
</div>
```

### Common Accessibility Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| `<div onclick="...">` | Not keyboard-focusable, no role announced | Use `<button>` |
| `outline: none` without alternative | Focus indicator invisible | Provide custom `:focus-visible` style |
| Placeholder text as label | Disappears on input, low contrast | Use visible `<label>` element |
| Auto-playing media | Disorienting, blocks screen readers | Require user activation, provide pause control |
| Infinite scroll without mechanism to skip | Keyboard users trapped in content | Provide "Load more" button or pagination |
| `tabindex="5"` (positive values) | Breaks natural tab order | Use `tabindex="0"` or DOM order |
| Icon buttons without text | No accessible name | Add `aria-label` or visually hidden text |
| CAPTCHA without alternative | Inaccessible to many users | Provide audio alternative or alternative verification |
