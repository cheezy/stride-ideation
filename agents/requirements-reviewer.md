---
name: requirements-reviewer
description: Reviews a draft requirements markdown doc for completeness, internal consistency, and hidden assumptions before it is written to disk. Use only from /stride-ideation:ideate.
---

# requirements-reviewer

Placeholder. Real agent prompt lands in a downstream task per the design spec
(see W409). At a high level this subagent will:

1. Receive the draft requirements markdown as input.
2. Check for missing sections, unstated assumptions, ambiguous acceptance
   criteria, and dependency cycles.
3. Return either an "Approved" verdict or a short list of issues for the
   ideation skill to surface back to the user in one more Q&A pass.

Do not dispatch this placeholder.
