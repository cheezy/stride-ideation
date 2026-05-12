---
name: stride-ideation
description: Interactive ideation protocol for /stride-ideation:ideate — drives a Q&A loop that turns a fuzzy idea into a committed requirements markdown document. Replaces superpowers:brainstorming for Stride projects.
---

# Stride Ideation

Placeholder. Real protocol lands in a downstream task per the design spec
(see W406). At a high level this skill will:

1. Surface assumptions and constraints early so the user can correct them
   before they harden into spec text.
2. Drive twice-through coverage: a first pass to elicit the shape, a second
   pass to sharpen and stress-test it.
3. Emit a requirements document that downstream tools (especially
   `/stride-ideation:decompose`) can consume without further interpretation.
4. Optionally call a `requirements-reviewer` subagent for auto spec review
   before the document is written to disk.

Do not invoke this placeholder.
