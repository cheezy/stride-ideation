# Community Directory Submission — Readiness Checklist

Go/no-go package for submitting the **stride-ideation** plugin to the Anthropic
community plugin directory. Produced by task **W1287**, the final task of the
submission-readiness goal. **This package stops at ready-to-submit — it does NOT
submit the form.**

- **Date:** 2026-06-22
- **Plugin:** `stride-ideation` v0.8.0
- **Public repo:** <https://github.com/cheezy/stride-ideation>
- **Marketplace (today's install path):** `cheezy/stride-marketplace`

## Prior-task status

| Task | Produced | State |
|------|----------|-------|
| **W1282** | `SUBMISSION-AUDIT.md` — baseline validation + triaged findings | ✅ Done |
| **W1283** | `plugin.json` completed (author.url, concise catalog-blurb description) | ✅ Done |
| **W1284** | Credential-hygiene sweep — **all clear**, appended to the audit | ✅ Done |
| **W1285** | `SECURITY.md` — reviewer-facing runtime model (single POST egress, no hooks.json); file-backed | ✅ Done |
| **W1286** | `README.md` made self-contained (both install paths, prerequisites, component inventory, external-service note, security link) | ✅ Done |
| **W1287** | This readiness checklist | ✅ (this doc) |

## Hard validation gate (fresh run)

```
$ claude plugin validate --strict stride-ideation/
Validating plugin manifest: .../stride-ideation/.claude-plugin/plugin.json
✔ Validation passed        (exit 0)
```

Validator: Claude Code 2.1.186. The marketplace manifest
(`stride-marketplace/.claude-plugin/marketplace.json`) also passes `--strict`
(recorded in `SUBMISSION-AUDIT.md`).

## Submission package contents

- **Security doc:** [`SECURITY.md`](SECURITY.md) — trust boundary, the single `/stridify` `POST /api/tasks/batch` egress, token handling, disk writes, and the explicit no-`hooks.json` / no-client-side-hook-execution model.
- **Listing storefront:** [`README.md`](README.md) — self-contained: both install paths, prerequisites, component inventory, external-service disclosure, security link.
- **Audit trail:** [`SUBMISSION-AUDIT.md`](SUBMISSION-AUDIT.md) — validator results + credential-hygiene all-clear.
- **Manifest:** [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) — `name: stride-ideation`, `version: 0.8.0`, MIT, author + url, homepage/repository → public repo.

## Where to submit (this author)

The account on file (`cheezy@letstango.ca`) is an **individual author**, so the
Console submission path applies (not the claude.ai Teams/Enterprise admin
directory path).

| Author type | Submission entry point |
|-------------|------------------------|
| **Individual author (this case)** | Console plugin submission — `platform.claude.com/plugins/submit` |
| Teams / Enterprise | claude.ai admin directory — `claude.ai/admin-settings/directory/submissions/plugins/new` |

> ✅ **Verified.** The individual-author Console path
> (`platform.claude.com/plugins/submit`) has been confirmed against the live
> page and is the correct submission entry point.

## Open follow-ups before clicking submit

1. **✅ RESOLVED — plugin repo pushed and marketplace pin current.** The 5
   deliverable commits (`d4e14be`, `7924aa8`, `3ad5ad6`, `80d3c70`, `f0306cc`)
   are on `origin/main` at `github.com/cheezy/stride-ideation` (verified: local
   `main` is 0 ahead / 0 behind after a fresh fetch). The
   `cheezy/stride-marketplace` catalog pins `stride-ideation` v0.8.0 pointing at
   the public repo.
2. **✅ RESOLVED — marketplace blurb trimmed.** The `plugins[].description` for
   `stride-ideation` in `cheezy/stride-marketplace` was cut from the ~5,510-char
   changelog paragraph to a concise 283-char one-line blurb covering both
   `/ideate` and `/stridify` (marketplace commit `2647559`, pushed; delivered as
   Stride task W1346 under goal G274): *"Turn a fuzzy idea into shipped Stride
   tasks via two slash commands — /ideate drives an interactive, profile-aware
   question loop that hard-gates seven requirements sections into a committed
   markdown doc, and /stridify decomposes that doc into Stride goals and tasks
   via the batch API."*

## Credential rotation

**Not required.** The W1284 credential-hygiene sweep found no tracked secrets, no
hardcoded credentials/token literals (fixtures included), and no real token
literal in git history (only synthetic test placeholders in the lib test
scripts). No rotation blocks this submission.

## Go / No-Go

**Validation, manifest, security doc, README, and credential hygiene are all
GREEN.** Both operational follow-ups are now resolved: the plugin repo is pushed
public with the marketplace pin current (item 1), and the marketplace blurb is
trimmed (item 2). The submission URL is confirmed. **No blockers remain — the
package is ready to submit.**

**This goal ends here. The submission form is intentionally NOT submitted** —
that is the user's call.
