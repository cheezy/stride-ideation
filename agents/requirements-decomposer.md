---
name: requirements-decomposer
description: Reads a stride-ideation requirements markdown doc and returns a Stride batch JSON document. Use only from /stride-ideation:decompose.
---

# requirements-decomposer

Placeholder. Real agent prompt lands in a downstream task per the design spec
(see W411 for the embedded Stride batch JSON shape, W412 for multi-goal
splitting). At a high level this subagent will:

1. Receive the requirements markdown as input.
2. Identify natural task boundaries and dependency edges.
3. Decide whether the batch fits in a single goal or must split across two or
   more goals (code-coupling preferred, size-capped at roughly 10 tasks per
   goal).
4. Return a Stride batch JSON document with root key `goals`, conforming to
   `docs/api/post_tasks_batch.md` in the Stride repo. Local-audit fields are
   added at the root (`source_spec`, `source_spec_sha256`) by the calling
   command, not by this subagent.

Do not dispatch this placeholder.
