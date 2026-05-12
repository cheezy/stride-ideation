---
description: POST a stride-ideation batch JSON to the Stride API after validating and drift-checking against its source spec.
---

# /stride-ideation:ship

Placeholder. Real command body lands in a downstream task per the design spec
(see W417 for the basic command, W418 for drift checks, W419-W421 for payload
hygiene + auth + error handling). At a high level this command will:

1. Read the batch JSON at the supplied path.
2. Validate the root key (`goals`) and the schema shape.
3. Recompute the SHA-256 of the referenced `source_spec` and compare against
   the stamped `source_spec_sha256`; prompt-and-abort on drift.
4. Strip local-audit fields that the Stride API does not accept.
5. Read auth from `.stride_auth.md` and POST to `/api/tasks/batch`.
6. Surface 4xx/5xx responses verbatim and exit non-zero on failure.

Do not invoke this placeholder.
