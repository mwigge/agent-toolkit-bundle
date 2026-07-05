---
name: presentation
description: Use when preparing slides, technical talks, decks, or stakeholder communication — structure, narrative, and Diátaxis-aware technical writing.
---

# Skill: Presentation & Technical Communication

## Diátaxis Framework

Always identify the documentation type before writing. Never mix types in a single document.

| Type | Orientation | Question answered | Example |
|------|-------------|-------------------|---------|
| **Tutorial** | Learning | "Help me learn X" | "Getting started with chaos experiments" |
| **How-To Guide** | Task | "How do I do X?" | "How to run a network partition experiment" |
| **Explanation** | Understanding | "Why does X work this way?" | "Why we use error budget burn rates" |
| **Reference** | Information | "What is X?" | "Chaos action API parameters" |

Rules:
- A tutorial walks a learner through a complete, meaningful task from scratch. Every step must work.
- A how-to guide assumes competence; it solves a specific problem. No teaching tangents.
- Explanation documents provide background, trade-offs, and conceptual models. No step-by-step instructions.
- Reference documents are dense, consistent, and complete. No narrative prose.

---

## Technical Presentation Structure

1. **Hook** (30 seconds) — a surprising stat, a failure anecdote, or a question that makes the audience feel the problem
2. **Problem statement** — describe the pain clearly before proposing any solution; use data where possible
3. **Solution overview** — one-slide summary: what you built, what it does, why it matters
4. **Deep dive** — technical details for the audience segment that needs them; use progressive disclosure
5. **Demo** — live or recorded; always have a fallback screenshot deck if live fails
6. **Metrics / Results** — before-vs-after; use absolute numbers *and* percentages; show confidence intervals
7. **Takeaways** — three bullet maximum; what you want the audience to remember tomorrow
8. **CTA (Call To Action)** — one specific next step per stakeholder type: exec / engineer / product

---

## Stakeholder Storytelling

**BLUF — Bottom Line Up Front**: state your conclusion and recommendation in the first 60 seconds. Executives make decisions; give them the answer first, evidence second.

Structure for executive audiences:
1. Recommendation (one sentence)
2. Business impact (cost / risk / revenue in concrete numbers)
3. Evidence summary (3 data points maximum)
4. Risks and mitigations
5. Ask (decision, budget approval, or endorsement)

Rules:
- Data before narrative — show the chart, then explain it
- Acknowledge risks honestly; hiding them destroys credibility when they surface
- Never bury the lead — "In conclusion…" belongs at the start, not the end
- Quantify everything: "significantly improved" → "p99 latency dropped from 840ms to 210ms"

---

## Slide Design Principles

- **One idea per slide** — if you need a transition word ("and", "also") to describe a slide's content, split it
- **Assertion-evidence format**: slide title is a complete sentence stating the *claim*; slide body is the *evidence* for that claim
  - Bad title: "Latency Results"
  - Good title: "P99 latency fell 75% after circuit-breaker rollout"
- Maximum 6 lines of text per slide (excluding title)
- No bullet nesting deeper than 2 levels; prefer visuals over nested bullets
- Use the assertion-evidence format even for agenda slides ("We solve three reliability problems")
- Avoid full sentences in bullets — use noun phrases; the speaker provides the verbs
- Font size floor: 24pt body, 32pt title — if content doesn't fit, split the slide

---

## Architecture Diagrams — C4 Model

Always use the C4 model. Four levels of abstraction:

1. **Context diagram** — the system and the people/systems that interact with it; no technology details; audience: everyone
2. **Container diagram** — major deployable units (web app, API, database, message queue); technology labels allowed; audience: technical stakeholders
3. **Component diagram** — components inside a single container; audience: developers working on that container
4. **Code diagram** — class/module level; generate from code, don't maintain manually; audience: IDE

Rules:
- Every diagram must include a **legend** (shape = meaning, colour = category)
- Use **Mermaid** for text-as-code diagrams in documentation (renders in GitLab/GitHub)
- Use **PlantUML** with the C4-PlantUML library for richer C4 diagrams in formal docs
- Label every relationship with the *technology and direction*: "HTTPS/REST →", "Kafka topic →"
- Context and Container diagrams must be maintained; Component and Code diagrams are optional

Mermaid diagram checklist:
- First line is `%%{init: {...}}%%` or diagram type declaration
- Include `title` directive
- Every node has a meaningful label, not just an ID
- Direction declared (`LR`, `TD`, etc.)
- Run through `diagram_lint.py` before committing

---

## Chaos Engineering Storytelling

Structure every chaos experiment narrative as:

1. **Baseline** — what does "normal" look like? SLI values, p50/p99 latency, error rate, throughput
2. **Hypothesis** — "When X fails, the system will Y because Z (steady-state maintained / degraded gracefully)"
3. **Experiment design** — what was injected, at what magnitude, for how long, on what scope
4. **Results** — what actually happened; use charts; compare against hypothesis
5. **Resilience score delta** — quantify the before/after score change using the agreed methodology
6. **Recommendation** — specific engineering action (e.g., "add retry with jitter on the payment client") with priority

When results contradict the hypothesis: treat it as the most valuable outcome. The system revealed a weakness. Frame this positively.

---

## Writing Clarity

- **Active voice**: "The experiment reduced error rate" not "Error rate was reduced by the experiment"
- **Avoid nominalisation**: "we decided" not "a decision was made"; "the system failed" not "failure occurred"
- **Sentence length**: target <25 words per sentence; never exceed 40 words without a full stop
- **Define acronyms on first use**: "Mean Time To Recovery (MTTR)" — then use MTTR throughout
- **Concrete over abstract**: "3 of 5 services failed the experiment" not "several services were affected"
- **Parallel structure in lists**: if the first item is a verb phrase, all items must be verb phrases
- **No weasel words**: "fairly", "quite", "somewhat", "various" — replace with specifics or delete

---

## Accessibility

- Every image must have alt text that conveys the *information*, not just the image description
  - Bad: `alt="bar chart"`
  - Good: `alt="Bar chart showing P99 latency: baseline 840ms, post-fix 210ms — a 75% reduction"`
- Colour contrast: minimum 4.5:1 for body text (WCAG AA); 3:1 for large text
- Never convey information through colour alone — add labels, patterns, or icons
- Slide decks: provide a text-based handout version for screen-reader users
- Diagrams: provide a prose description in the caption or surrounding text
- Avoid animations that flash more than 3 times per second (seizure risk)
