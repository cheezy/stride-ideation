# Changelog

All notable changes to the `stride-ideation` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-05-13

### Added

- **`--profile <name>` flag on `/stride-ideation:ideate`.** Selects one of three named profiles that shape which forcing questions run inside the rounds and which optional sections the document may include. The seven hard-gated section names and the mandatory round-3 framing and round-4 premortem are identical across all profiles — only the augmentations change. Pick a profile based on the audience and the part of the framing that's riskiest:
  - **`lean`** (default). The bare-minimum round structure — no profile-specific forcing questions, no profile-specific optional sections, no profile-specific reviewer checks. Use for engineering-only audiences, small topics, and the shortest path to a committed doc. Byte-for-byte equivalent to v0.3.0 behavior.
  - **`product`**. Adds a Round-1 JTBD (jobs-to-be-done) four-forces forcing question framing Problem and Goal around the user's job, the forces pulling them toward and away from a solution, and the habits they're abandoning. Unlocks an optional **Concrete Example** section (named user, trigger, current bad path, desired good path). The advisory reviewer rubric gains two profile-aware checks (JTBD framing presence, Concrete Example presence). Source technique: Clayton Christensen + Bob Moesta's *Jobs to Be Done* — for product/design audiences, persona-bound scenarios beat feature lists for framing trade-offs.
  - **`discovery`**. Adds a Round-2 Why-now + Alternative-options forcing question that asks what makes this problem worth solving *now* (versus later) and which other options were considered and rejected. The advisory reviewer rubric gains one profile-aware check (Why-now content presence). The Why-now content folds into the existing Problem and Assumptions sections — no new optional section. Source techniques: the Sequoia "Why now?" memo tradition (urgency-of-timing as a first-class section of an investment thesis) and Specification by Example's emphasis on naming alternatives that were rejected (Gojko Adzic).
- **Profile-aware advisory checks in `agents/requirements-reviewer.md`.** Three new conditional checks: Concrete Example presence (product-only), JTBD-derived Problem framing (product-only), Why-now content (discovery-only). All three are advisory, never blocking — they extend the existing advisory rubric and do NOT introduce a new hard-block path. The reviewer's calling contract (at most one refinement round; never edits the document) is unchanged.

### Changed

- The round-summary table in `skills/stride-ideation/SKILL.md` gains a per-profile **augmentations** column. The default-focus column is identical across all profiles — only the augmentations differ. Under `lean`, the augmentation column is empty (byte-for-byte v0.3.0).
- The plugin description in `.claude-plugin/plugin.json` and the slash-command frontmatter on `commands/ideate.md` now mention the `--profile` flag and name the three profiles.
- The README gains a Profiles subsection (one paragraph + a three-row table) showing what each profile adds and when to pick it.

### Migration

- **No migration needed.** `--profile` is optional and defaults to `lean`. v0.3.0 invocations of `/stride-ideation:ideate` are byte-identical under v0.4.0 — the round loop, the seven gated sections, the round-3 framing, the round-4 premortem, and the advisory reviewer pass all behave exactly as in v0.3.0 when the flag is omitted. Backward compatibility under the default profile is a load-bearing claim of this release.
- **No command surface changes beyond the optional flag.** The two slash commands (`/ideate`, `/stridify`) and their existing arguments are byte-identical to v0.3.0. The new flag is purely additive.
- **In-flight v0.3.0 requirements docs** (docs that pass the v0.3.0 hard gate but were produced without an explicit profile) are valid v0.4.0 lean documents — no rework needed.

## [0.3.0] - 2026-05-13

### Added

- **Round 4 — Premortem (mandatory).** After the round-3 framing checkpoint and before the advisory `requirements-reviewer` pass, `/stride-ideation:ideate` now runs a single batched premortem question that asks the user to invert the framing ("imagine it's six months after we ship and this initiative quietly underperformed — what's the most likely reason?"). The answer is folded into the Assumptions section as one or more failure-mode entries. Source technique: Gary Klein's *premortem* (Harvard Business Review, 2007) — the round-1-to-3 loop reliably surfaces expected design properties rather than the failure modes the design depends on NOT happening, and the premortem inverts that bias before the doc is committed. The round runs even on `--continue` mode — refining a v0.2.0 doc is exactly when the premortem catches things, so there is no skip carve-out.
- **Riskiest-assumption ranking.** The Assumptions section is now hard-gated on shape, not just presence: entries must be ordered highest-to-lowest risk and exactly one must be marked `(R)` (or `**(riskiest)**`). Either marker form is accepted by the reviewer rubric. The marker is what makes the ranking auditable — a sorted list with no marker reads the same as an unsorted one. Source technique: Giff Constable's *riskiest assumption test* (RAT) — focusing scarce validation effort on the one assumption whose failure changes the design more than any other.
- **Leading + lagging Success Metrics.** The Success Metrics section is now hard-gated on shape: it must contain at least one leading indicator (observable while the work is in flight, predicts the outcome) AND at least one lagging indicator (the outcome itself, observable only after it has occurred). All-leading or all-lagging metrics fail the gate. Source technique: leading-vs-lagging indicator literature commonly cited in the OKR / KPI world — all-lagging metrics can only be observed after it is too late to correct, and all-leading metrics never confirm the outcome itself.

### Changed

- `requirements-reviewer.md` rubric: the **Assumptions** row gains two advisory checks (no entry appears premortem-derived; no entry is marked riskiest) and the **Success Metrics** row gains one advisory check (only leading-or-only-lagging indicators). All three additions are advisory-only — they extend the existing advisory rubric and do NOT introduce a new hard-block path. The reviewer's calling contract (at most one refinement round; never edits the document) is unchanged.
- The round-summary table in `skills/stride-ideation/SKILL.md` is reshaped: Round 4 is now Premortem; gap-fill moves to Round 5+. Round 5+ remains a single bucket — no further structural slicing.
- The skill `description:` frontmatter field is updated to mention the mandatory round-4 premortem and the new shape requirements on Assumptions and Success Metrics; the seven required-section names themselves are unchanged.

### Migration

- **In-flight v0.2.0 requirements docs** (docs that pass the v0.2.0 hard gate but pre-date the new shape requirements) will fail the v0.3.0 reviewer rubric with three advisory findings — they will NOT be hard-blocked from being written or stridified, but the new advisory pass will flag the gaps. To bring an existing doc up to v0.3.0:
  ```bash
  /stride-ideation:ideate --continue path/to/<existing>-requirements.md
  ```
  The `--continue` mode preserves the existing content as read-only context and emits a sibling timestamped doc with the round-4 premortem run, the Assumptions ranked, and any missing indicator type added to Success Metrics. The source doc is never modified.
- The on-disk template in `commands/ideate.md` Step 6 has changed: the Success metrics block now shows labeled leading / lagging sub-bullets, and the Assumptions block shows ordered entries with a `(R)` marker on the riskiest. Documents written prior to v0.3.0 do not match this template but remain valid input to `/stride-ideation:stridify` — the decomposer only requires the seven gated sections to be present and substantive.
- **No command surface changes.** The two slash commands (`/ideate`, `/stridify`) and their argument shapes are byte-identical to v0.2.0.

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
