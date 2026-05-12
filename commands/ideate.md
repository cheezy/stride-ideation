---
description: Drive an interactive ideation session that produces a committed requirements markdown document. Replaces superpowers:brainstorming for Stride projects.
---

# /stride-ideation:ideate

Placeholder. Real command body lands in a downstream task per the design spec
(see W407 for the basic command, W408 for the `--continue` flag). At a high
level this command will:

1. Resolve the topic (from argument or one-question prompt).
2. If `--continue <path>` is supplied, read the prior requirements doc.
3. Invoke the `stride-ideation` skill to drive the interactive Q&A loop.
4. Write the result to `docs/superpowers/specs/<timestamp>-<topic>-requirements.md`.
5. Print the next-step suggestion: run `/stride-ideation:decompose <path>` to
   break the requirements into a Stride batch JSON.

Do not invoke this placeholder.
