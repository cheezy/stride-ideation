# Changelog

All notable changes to the `stride-ideation` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-05-13

### Changed

- **BREAKING: Three-command surface collapsed to two.** The standalone `/stride-ideation:decompose` and `/stride-ideation:ship` commands are removed; both flows are merged into a single new command `/stride-ideation:stridify <path-to-requirements.md>` that runs the full pipeline end-to-end (validate → preflight auth → dispatch decomposer → stamp audit metadata → write + commit batch JSON → strip audit fields → POST → render G/W identifiers). The intermediate `*-stride-batch.json` artifact and its commit are preserved exactly as before — the merge is a UX collapse, not a data-model change.
- **Auth read is now a preflight step** (Step 3 of `/stridify`, before the decomposer dispatch) so a misconfigured `.stride_auth.md` fails fast without first burning a subagent pass and writing a batch JSON that can't be shipped. The historical `/ship`-side late auth read is gone.
- **Drift check removed.** The historical `/ship` command ran a `source_spec_sha256` drift check to catch the case where a user hand-edited the requirements doc between `/decompose` and `/ship`. In the merged `/stridify` flow the batch JSON is written by the same invocation, so source drift cannot have occurred and the check is omitted with an explicit one-line justification in the command body.
- **`requirements-decomposer` and `requirements-reviewer` agents are unchanged** — only the outer command surface changes. The `lib/` helpers (`validate_batch.py`, `read_auth.py`, `strip_audit_fields.py`, `filename.sh`) are reused verbatim by `/stridify`. `lib/drift_check.py` is no longer called by any shipping command (all 7 of its unit tests still pass; left in place for potential future reuse).
- All internal cross-references (in `commands/ideate.md`, `skills/stride-ideation/SKILL.md`, both agent prompts, the fixture README + smoke-test note, and the marketplace manifest description) have been updated to reference `/stride-ideation:stridify`.

### Migration

- Replace any scripted invocations of the old two-command form with the new one-command form:
  - Before: `/stride-ideation:decompose <doc>` then `/stride-ideation:ship <batch-json>`
  - After: `/stride-ideation:stridify <doc>` (one invocation, same on-disk artifacts as before)
- If you previously ran `/stride-ideation:decompose` and want to ship the existing on-disk batch JSON without re-decomposing, the old `/ship`-style invocation is no longer available. The `lib/strip_audit_fields.py` and `curl … /api/tasks/batch` paths are still available as a manual escape hatch — the recipe is documented inline in `commands/stridify.md` Steps 9a-9c.
- Re-installation: `/plugin update stride-marketplace` once the marketplace manifest catches up to the renamed plugin entry, OR `/plugin uninstall stride-ideation` then `/plugin install stride-ideation@stride-marketplace` for a clean re-install.

## [0.1.0] - 2026-05-12

Initial public release. Distributed via [stride-marketplace](https://github.com/cheezy/stride-marketplace); install with:

```text
/plugin marketplace add cheezy/stride-marketplace
/plugin install stride-ideation@stride-marketplace
```

### Added

- **`/stride-ideation:ideate [<topic>] [--continue <path>]`** — interactive ideation command. Captures the session timestamp once at invocation, runs the round-based question loop defined in `skills/stride-ideation/SKILL.md` (≤ 4 batched `AskUserQuestion` per round; mandatory round-3 framing checkpoint; seven hard-gated requirements sections), auto-dispatches the `requirements-reviewer` subagent for an advisory pass, then writes and commits a timestamped `*-requirements.md`. The terminal state is the written doc — the command does NOT auto-invoke `/decompose`. `--continue <path>` refines an existing requirements doc in read-only mode (source file is never modified) under a fresh timestamp.
- **`/stride-ideation:decompose <path>`** — converts a requirements doc into a Stride batch JSON document. Validates that all seven hard-gated sections are present in the source doc, dispatches the `requirements-decomposer` subagent, stamps `source_spec` + lowercase `source_spec_sha256` at the JSON root for drift detection, runs the structural validator (`lib/validate_batch.py`), and writes a timestamped sibling file at the same prefix as the requirements doc.
- **`/stride-ideation:ship <path>`** — POSTs a Stride batch JSON to `/api/tasks/batch`. Validates structure, runs the source-spec drift check (`lib/drift_check.py`) and prompts the user on mismatch with `[y/N]` default-no, reads auth from `.stride_auth.md` via `lib/read_auth.py`, strips the three local-audit fields from the in-memory payload via `lib/strip_audit_fields.py` (the on-disk file is never modified), POSTs with token hygiene (no `curl -v`, no token in logs or error messages), surfaces 4xx / 5xx response bodies verbatim, and renders the created G / W identifiers in a two-column table on success.
- **`skills/stride-ideation/SKILL.md`** — the ideation protocol contract: seven hard-gated sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success Metrics), batched questioning loop, round-3 framing checkpoint, advisory reviewer pass before commit, neutral terminal state. Replaces the `superpowers:brainstorming` skill for Stride projects.
- **`agents/requirements-decomposer.md`** — subagent prompt that turns a requirements doc into a Stride batch JSON. Embeds the canonical batch shape, the four most common batch-API mistakes (root key `goals` not `tasks`; `verification_steps` as object array; `dependencies` by array index within a goal; `key_files` as object array), the two-reason multi-goal split rule (code-coupling + ~10-task soft cap), and the explicit do-not-emit list of orchestrator- and server-controlled fields. Worked examples cover single-goal, multi-goal independent, and 14-task multi-goal coupled shapes.
- **`agents/requirements-reviewer.md`** — advisory subagent prompt that audits a draft requirements doc against a calibrated rubric covering all seven hard-gated sections + five cross-section consistency checks. Returns a single fenced JSON document; never edits the doc; never demands more than one refinement round.
- **`lib/`** — pure helpers that the slash commands compose: `filename.sh` (slug + unique-path generation with collision discriminator), `validate_batch.py` (five named structural-validity checks with path-precise error messages), `drift_check.py` (source-spec drift detection with three exit codes), `read_auth.py` (auth extraction with token-leak hardening and onboarding-doc links), `strip_audit_fields.py` (in-memory removal of local-audit fields; on-disk file unchanged).
- **`fixtures/`** — three paired requirements docs + batch JSONs demonstrating small / multi-goal independent / 14-task multi-goal coupled decomposition shapes. Each batch passes the structural validator; each `source_spec_sha256` matches the actual SHA of its paired requirements doc.
- **`lib/run_smoke_test.sh`** — end-to-end pipeline driver. Dry mode (default) composes every helper the slash commands invoke with deterministic fixture inputs and a canned 2xx response; `--live <path>` adds a real HTTP POST against the Stride instance in `.stride_auth.md`. 36 unit tests across the per-helper harnesses (`lib/test-*.sh`) plus 10 dry-mode composition stages.
