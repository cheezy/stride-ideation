# Security Model

This document describes what the **stride-ideation** Claude Code plugin does at
runtime, written for a security reviewer evaluating it for the plugin directory.
Every claim here is backed by the plugin's own files — primarily
[`commands/stridify.md`](commands/stridify.md),
[`commands/ideate.md`](commands/ideate.md),
[`lib/read_auth.py`](lib/read_auth.py), and
[`lib/draft.sh`](lib/draft.sh).

> **Key difference from the `stride` plugin:** stride-ideation ships **no
> `hooks.json`** and therefore performs **no client-side hook execution** of your
> `.stride.md` commands. There is no `hooks/` directory; `.claude-plugin/`
> contains only [`plugin.json`](.claude-plugin/plugin.json) (metadata).

## Trust boundary (read this first)

- **What runs on your machine:** the agent following this plugin's Markdown
  skill/commands/subagents (instructions, not executable code), plus the small
  set of `lib/` helper scripts the plugin ships (a few Python/bash utilities for
  slug/path generation, batch-JSON validation, drift checks, draft autosave, and
  credential extraction). The slash commands' `allowed-tools` frontmatter
  enumerates exactly which Bash invocations are permitted
  ([`commands/stridify.md:3`](commands/stridify.md),
  [`commands/ideate.md:3`](commands/ideate.md)); `/ideate` is not even allowed to
  call `curl`.
- **What leaves your machine:** exactly **one** network request — a single
  `POST` of the decomposed batch JSON to **your configured Stride server**
  (`stridelikeaboss.com` by default) when you run `/stridify`. Nothing else is
  transmitted.
- **Where your secret lives:** a project-local `.stride_auth.md` file that **you**
  create and that is **never committed**. The plugin reads it; it never bundles,
  prints, logs, or persists the token.
- **What the plugin does NOT do:** no telemetry/analytics, no background
  processes, no auto-update, and no arbitrary code execution beyond the `lib/`
  helper scripts it ships.

## What the plugin installs

All agent-facing components are Markdown (instructions for the agent, not
executable code):

| Component | Count | Files |
|-----------|-------|-------|
| Slash commands | 2 | [`commands/ideate.md`](commands/ideate.md), [`commands/stridify.md`](commands/stridify.md) |
| Skill | 1 | [`skills/stride-ideation/SKILL.md`](skills/stride-ideation/SKILL.md) |
| Subagents | 2 | [`agents/requirements-decomposer.md`](agents/requirements-decomposer.md), [`agents/requirements-reviewer.md`](agents/requirements-reviewer.md) |

Plus `lib/` helper scripts — the only executable surface the plugin ships:
`read_auth.py`, `validate_batch.py`, `drift_check.py`, `strip_audit_fields.py`,
`filename.sh`, `draft.sh`, and `run_smoke_test.sh` (the smoke-test harness, used
for development; its only network call is gated behind an explicit `--live`
flag). There is **no `hooks.json` and no `hooks/` directory** — the plugin
registers no lifecycle hooks and executes none of your `.stride.md` sections.

## What runs at runtime

The plugin is purely invocation-driven: its two slash commands execute
synchronously in your Claude Code session when you invoke them. There is no
event-triggered hook, no daemon, and no background task.

- **`/stride-ideation:ideate`** drives an interactive ideation session and, on
  completion, writes and commits a requirements Markdown document. It is not
  permitted to make network calls (its `allowed-tools` list contains no `curl`).
- **`/stride-ideation:stridify`** decomposes the requirements doc into a Stride
  batch JSON (via a read-only subagent), commits it for audit, and — after a
  human preview-and-approval gate — issues the single POST described below.

The `lib/` helpers are plain utilities invoked by these commands: regex
credential extraction (`read_auth.py`), JSON shape validation
(`validate_batch.py`), SHA drift checks (`drift_check.py`), audit-field stripping
(`strip_audit_fields.py`), and pure slug/path/draft bash functions
(`filename.sh`, `draft.sh`). None except the `--live` smoke test makes any
outbound call.

## What data leaves the machine, and where

The plugin makes **exactly one** kind of outbound request — the `/stridify`
batch upload ([`commands/stridify.md:546-555`](commands/stridify.md)):

```
POST {your API URL}/api/tasks/batch
Authorization: Bearer {your token}
Content-Type: application/json
```

- **Destination host** is whatever you configured as the `**API URL:**` in
  `.stride_auth.md` — `https://www.stridelikeaboss.com` by default. The hostname
  is not hardcoded into the curl call; it is sourced from your auth file. The
  plugin contacts no other host.
- **Payload** is the decomposed batch JSON (the goals/tasks `/stridify` produced
  from your requirements doc), with the three local audit fields (`source_spec`,
  `source_spec_sha256`, `decomposition_notes`) stripped in memory before send.
  It contains only the task content you reviewed and approved at the preview
  gate.
- **Header-only token:** the token is passed solely via
  `-H "Authorization: Bearer $STRIDE_API_TOKEN"`, never as a `ps`-visible
  positional argument. `curl -v` is **explicitly prohibited** so the
  Authorization header is never echoed
  ([`commands/stridify.md:151,560`](commands/stridify.md)), and the variable is
  `unset` immediately after the call
  ([`commands/stridify.md:557`](commands/stridify.md)).

The only other `curl` in the repo lives in
[`lib/run_smoke_test.sh:214-220`](lib/run_smoke_test.sh) and runs **only** under
the explicit `--live` flag; in default/dry-run mode it makes no network call.

## Token & credential handling

The bearer token and API URL are resolved at runtime by
[`lib/read_auth.py`](lib/read_auth.py) from the **user-local `.stride_auth.md`**
path passed as its argument — no other source:

- **Prod-token disambiguation:** the token regex uses a `(?<!Local )` negative
  lookbehind ([`lib/read_auth.py:38-39`](lib/read_auth.py)) so it matches the
  production `**API Token:**` line and **not** the `**Local API Token:**` line.
- **Token never reaches the error channel:** the resolved token is written
  **only to stdout** as a sourceable `STRIDE_API_TOKEN=…` line
  ([`lib/read_auth.py:108-109`](lib/read_auth.py)); every error path writes to
  stderr and the code comments enforce that the token value is never placed in a
  stderr message ([`lib/read_auth.py:21,95`](lib/read_auth.py)).
- **No hardcoded credential, no process-env read:** there is no token literal
  anywhere in the plugin, and `read_auth.py` does not read environment variables
  (`os.environ` / `getenv` are absent). The token is passed only as a `curl`
  header and never echoed, logged, or persisted.
- `.stride_auth.md` is user-created and must never be committed (stated in the
  README's auth section).

A full credential-hygiene sweep of this repository — no tracked secrets, no
hardcoded credentials, no real token literal in git history, 11/11 lib test
scripts clean — is recorded in [`SUBMISSION-AUDIT.md`](SUBMISSION-AUDIT.md).

## What is written to disk

Both writes are committed for audit and are ordinary project files — neither
contains any credential:

- **`/ideate`** writes a timestamped requirements Markdown document and commits
  it ([`commands/ideate.md:215-231`](commands/ideate.md)). During the session an
  intra-session autosave scratch file is written under a **gitignored** `.stride/`
  path and deleted on successful commit; `lib/draft.sh` documents that it never
  serializes any secret — it writes only the content it is handed, and the API
  token is not in scope during ideation at all
  ([`lib/draft.sh:20-24`](lib/draft.sh)).
- **`/stridify`** writes a timestamped `<ts>-<slug>-stride-batch.json` sibling to
  the requirements doc and commits it
  ([`commands/stridify.md:456-465`](commands/stridify.md)). On the rare path
  where all subagent dispatch attempts fail, it writes a
  `<ts>-<slug>-decomposer-prompt.md` fallback that explicitly contains no
  authentication material ([`commands/stridify.md:365-368`](commands/stridify.md)).

## What it does NOT do

Confirmed by absence across all `.md`, `.sh`, `.py`, and `.json` files:

- **No telemetry/analytics** — no calls to any analytics endpoint or beacon.
- **No background/daemon process** — every command runs synchronously in the
  session; there is no cron, daemon, or process-launching code.
- **No auto-update** — the plugin has no self-update mechanism; version changes
  are manual author releases.
- **No arbitrary code execution** — the slash commands' `allowed-tools`
  frontmatter enumerates the exact permitted Bash invocations; there is no `eval`
  of untrusted content and no execution surface beyond the shipped `lib/` helpers.

## External dependency

The single external dependency is **your configured Stride server**
(`https://www.stridelikeaboss.com` by default), contacted exactly once per
`/stridify` run for the `POST /api/tasks/batch`. No third-party services,
package registries, or other hosts are contacted at runtime.

## Reporting

Security concerns about this plugin can be raised via the issue tracker at
<https://github.com/cheezy/stride-ideation>.
