# stride-ideation Plugin — Community Directory Submission Audit

Baseline audit for submitting the **stride-ideation** plugin to the Anthropic
community plugin directory. Produced by task **W1282**. This document **captures
and classifies** findings only — it does not fix them. Each finding names the
downstream task that resolves it. This mirrors `stride/SUBMISSION-AUDIT.md`
(W1128 in G234).

## Environment

- **Validator:** `claude plugin validate` from Claude Code `2.1.186`
- **Plugin source:** `stride-ideation/.claude-plugin/plugin.json` (repo `github.com/cheezy/stride-ideation`, v0.8.0)
- **Marketplace source:** `stride-marketplace/.claude-plugin/marketplace.json` (repo `github.com/cheezy/stride-marketplace`, v1.45.0) — local source clone, not the `~/.claude/plugins` cache
- **Date:** 2026-06-22

## Validator results (the hard gate)

| Target | Command | Result |
|--------|---------|--------|
| Plugin manifest | `claude plugin validate --strict stride-ideation/` | ✅ **Validation passed** (exit 0) |
| Plugin manifest | `claude plugin validate stride-ideation/` (non-strict) | ✅ Validation passed (exit 0) |
| Marketplace manifest | `claude plugin validate --strict stride-marketplace/` | ✅ **Validation passed** (exit 0) |

**Zero validator errors and zero `--strict` warnings.** Both manifests are
structurally valid, all referenced fields are recognized, and no unknown fields
were flagged. This is the clean baseline; downstream tasks must not regress it.

## Triaged findings (manual completeness review)

The validator passing means the manifests are *structurally* correct — not that
they are *directory-optimal*. The items below are completeness / discovery /
trust observations gathered by inspecting the manifests and repo against the
submission bar. None are validator errors.

| # | Finding | Severity | Classification | Resolved by |
|---|---------|----------|----------------|-------------|
| 1 | `plugin.json` has no `author.url` field. `author` carries only `name` and `email`; the URL-equivalents (`homepage`, `repository`) live at the top level. Present top-level keys: name, description, version, author{name,email}, homepage, repository, license, keywords. | low | **fix-now** | W1283 |
| 2 | `description` (~660 chars) opens with a tight sentence ("Turn an idea into shipped Stride tasks.") but then expands into a parenthetical inventory of every flag/affordance — a feature-dump, not a one-line catalog blurb. | low | **fix-now** (tune) | W1283 |
| 3 | The `stride-ideation` marketplace entry's `plugins[].description` is an enormous changelog-style paragraph (5,510 chars of concatenated per-version release notes — ~40× a normal blurb). As a catalog blurb this is unreadable. | medium | **fix-now** (separate `stride-marketplace` repo, out of this goal's plugin scope) | flagged for follow-up — see Notes |
| 4 | No `SECURITY.md` / reviewer-facing security doc exists anywhere in the repo; the token-read + single-POST egress model is undocumented for a safety reviewer. | high | **fix-now** | W1285 |
| 5 | README is not directory-self-contained: install section documents only the custom-marketplace path (no community-directory install path), has no explicit component inventory, no security pointer, thin prerequisites (omits the Python 3 / bash runtime deps of the lib/ helpers), and contains a hard reference to a design spec "in the parent repo" that dead-links for a standalone marketplace install. | medium | **fix-now** | W1286 |
| 6 | Credential hygiene (no bundled secrets; helpers read creds from user-local `.stride_auth.md` only) is asserted but not yet verified end-to-end. | high | **fix-now** | W1284 |

## Security-relevant notes (forwarded to W1285)

Per this task's `security_considerations`, anything touching credential handling
or network egress is flagged here for the SECURITY.md task. **Unlike the `stride`
plugin, `stride-ideation` ships no `hooks.json`** — its `.claude-plugin/`
directory contains only `plugin.json`, so there is no client-side
hook-execution surface. The risk surface is instead the `/stridify` token-read
and single network POST:

- **Token read:** `lib/read_auth.py` reads `$PROJECT_DIR/.stride_auth.md` and
  extracts `STRIDE_API_URL` + `STRIDE_API_TOKEN` via regex, printing them as
  sourceable shell assignments to stdout. It explicitly disambiguates the
  prod `**API Token:**` line from the `**Local API Token:**` line, never writes
  the token to stderr, and performs no disk writes.
- **Network egress:** Single outbound call. `/stridify` (Step 9) issues one
  `curl -sS -X POST` to `$STRIDE_API_URL/api/tasks/batch` with the token in an
  `Authorization: Bearer` header (never on the command line as a positional
  argument). `-v` is explicitly prohibited; curl stderr is captured to a temp
  file. No other helper makes outbound calls (except `run_smoke_test.sh`, only
  in opt-in `--live` mode).
- **Disk writes:** the committed requirements doc (read-only to `/stridify`),
  the batch JSON `<ts>-<slug>-stride-batch.json` (written via the Write tool and
  committed by explicit path, not `git add -A`), an optional
  `<source-stem>-decomposer-prompt.md` fallback on retry exhaustion, and the
  gitignored `.stride/<ts>-<slug>-draft.md` autosave (deleted on successful
  commit; documented as never holding the API token).
- **lib/ helper scripts** (`strip_audit_fields.py`, `validate_batch.py`,
  `drift_check.py`, `filename.sh`, `draft.sh`) perform no network calls and no
  credential handling; they are pure JSON/string/bash utilities.
- No secret material was observed in the manifests or helpers (findings #1–#6
  are all non-secret). The full credential-hygiene sweep is W1284's deliverable.

## Notes / out-of-scope follow-ups

- **Finding #3** lives in the separate `cheezy/stride-marketplace` repo, not the
  `stride-ideation` plugin repo this goal targets. It is recorded here so it
  isn't lost, but trimming the 5,510-char marketplace blurb is outside this
  goal's plugin scope — raise it as a separate marketplace-repo task before the
  listing goes live.
- No real tokens, `.stride_auth.md`, or `.env` content appears in this audit, per
  the task's security constraint.

## Credential-hygiene audit (W1284) — ALL CLEAR

Full sweep of the `stride-ideation/` plugin repo for bundled secrets and
credential handling. **No leak found; no rotation or history remediation
required.**

| Check | Method | Result |
|-------|--------|--------|
| No secret files tracked | `git ls-files \| grep -Ei 'auth\|secret\|token\|\.env\|\.pem\|\.key'` | ✅ only `lib/read_auth.py` matches — the auth-*reader* script, not a secret file (no token content). No `.stride_auth.md`, `.env`, `.pem`, or `.key` tracked. |
| No hardcoded credentials | `git ls-files \| xargs grep -nEi 'stride_(dev\|prod)_…\|Bearer …'` over skills/commands/agents/lib/fixtures | ✅ no real token literals. Every `Bearer` usage references the `$STRIDE_API_TOKEN` **variable** (`commands/stridify.md`, `lib/run_smoke_test.sh`); `lib/read_auth.py:69` shows a `stride_xxx...` **placeholder** in a help string. |
| Fixtures clean | `grep -rnEi 'stride_(dev\|prod)_\|Bearer …' fixtures/` | ✅ the three example requirements docs + batch JSONs and the fixtures README carry no token literals or auth material. |
| No real token in history | `git log --all -S 'stride_dev_'` / `-S 'stride_prod_'` | ✅ the only `stride_dev_` strings ever committed are obvious synthetic test placeholders in lib test scripts (`stride_dev_TEST_TOKEN_FOR_SMOKE_TEST_ONLY`, `stride_dev_LOCAL_should_not_match`, `stride_dev_REAL_TOKEN_xyz123`, `stride_dev_SUPER_SECRET_TOKEN_xyz_DO_NOT_LEAK`). No real credential ever entered history. |
| lib test scripts pass clean | `for t in lib/test-*.sh; do bash "$t"; done` | ✅ all 11 test scripts then present passed at audit time (2026-06-22). Re-verified 2026-07-02: the suite has since grown to 12 scripts — all 12 pass, 168 assertions, 0 failures. |
| User docs warn against committing creds | `README.md` § Auth | ✅ `README.md:110` states "Never commit `.stride_auth.md` — it carries a bearer token"; token shown only as `stride_xxx...` placeholder. |

### Credential-sourcing model (verified in `lib/read_auth.py`)

The token and API base URL are resolved at runtime from **user-local sources
only** — never hardcoded:

1. **Source:** `lib/read_auth.py <path>` reads the user's `.stride_auth.md` and
   extracts `STRIDE_API_URL` + `STRIDE_API_TOKEN` via regex.
2. **Prod-token disambiguation:** the token regex uses a negative lookbehind
   `(?<!Local )` so it matches the prod `**API Token:**` line and explicitly
   **not** the `**Local API Token:**` line.
3. **Token never leaks to the error channel:** the resolved token is written
   **only to stdout** (a sourceable `STRIDE_API_TOKEN=…` line); every error path
   writes to stderr and the code comments enforce that the token value is never
   placed in a stderr message — even on a partial match.
4. **No persistence / no echo:** the token is never written to disk, logged, or
   persisted. In `/stridify` it is passed only as a `curl -H "Authorization:
   Bearer $STRIDE_API_TOKEN"` header (never as a `ps`-visible positional
   argument; `-v` is prohibited).

Unlike the `stride` plugin, `stride-ideation` ships **no `hooks.json`** — there
is no client-side hook-execution surface and `read_auth.py` is the sole
credential-handling component. The `draft.sh` autosave is documented as never
holding the API token.

**W1284 verdict:** credential hygiene is **ALL CLEAR**. Audit finding #6 (this
sweep) is now closed with no remediation needed.

## Baseline conclusion

The submission's **hard validation gate is already green** (all three targets
pass `--strict` at exit 0). The remaining work is completeness and trust:
manifest polish (W1283), credential-hygiene verification (W1284), the
reviewer-facing security doc (W1285), and a directory-self-contained README
(W1286) — consolidated by the go/no-go readiness checklist (W1287).
