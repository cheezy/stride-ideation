---
description: Break a stride-ideation requirements markdown doc into a Stride batch JSON file (timestamped, paired by slug with its source).
---

# /stride-ideation:decompose

Placeholder. Real command body lands in a downstream task per the design spec
(see W413 for the basic command, W414 for source-spec stamping, W415 for
validation). At a high level this command will:

1. Validate the input path is a `*-requirements.md` produced by `/ideate`.
2. Dispatch the `requirements-decomposer` subagent with the requirements doc.
3. Receive the Stride batch JSON shape and stamp `source_spec` +
   `source_spec_sha256` at the root for drift detection.
4. Apply multi-goal splitting if the batch grows past the size threshold.
5. Write the result to a timestamped sibling path (e.g.
   `docs/superpowers/specs/<timestamp>-<topic>-stride-batch.json`).
6. Print the next-step suggestion: run `/stride-ideation:ship <path>` to POST
   the batch to Stride.

Do not invoke this placeholder.
