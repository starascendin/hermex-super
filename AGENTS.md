## Update for the fork

I deployed hermes + hermes-webui to a vm:
ssh hermes@100.78.186.127


# AGENTS.md — working agreement for Hermex

Hermex is a native SwiftUI iPhone app (Xcode target/scheme `HermesMobile`, App Store
name `Hermex`) for a self-hosted `hermes-webui` server. `PROJECT_SPEC.md` is the
product/API source of truth — if a request conflicts with it, stop and ask.
Read by every agent (Codex, Claude Code, …); keep it tool-agnostic.

## Session start & wrap-up
- Read `CURRENT.md` first if it exists — it holds the latest resumable state. It is
  local-only (gitignored), never committed; a fresh clone won't have one.
- Read only the `PROJECT_SPEC.md` sections named in CURRENT.md's **Spec Read** field;
  never the whole ~850-line spec unless told to.
- Active work lives in GitHub Issues. Implement only the issue the human selects, one
  labeled `ready-for-agent`, or one named in CURRENT.md — not every open issue.
- On "wrap up": verify repo/build/test state, overwrite `CURRENT.md` with the new
  state (it stays uncommitted), then commit the code.
  History lives in `git log` and merged PRs; there is no append-only log.

## How work flows
- One issue → one short `issue/<n>-slug` branch → one PR (branches with no issue use
  `chore/` or `fix/`). Issue/triage/domain conventions live in `docs/agents/`.
- `master` is the protected release-candidate branch (the source for internal
  TestFlight builds): keep it buildable, never do feature work on it.
- Pushing a branch, opening/updating a PR, or merging needs explicit human approval.
  Triage bot/review comments before accepting them.

## Hard rules
1. **Never invent API endpoints or JSON shapes.** Verify in this precedence order:
   (a) `curl` your own running server — final arbiter; (b) the official API docs at
   https://get-hermes.ai/api-docs/ — best for endpoint intent, auth contract, SSE
   event vocabulary, and conventions (no version pin; tracks the latest release);
   (c) the pinned upstream copy at `.codex-tmp/hermes-webui/api/routes.py` — ground
   truth for exact JSON shapes, but may lag the release the docs describe (clone it
   if missing: `git clone https://github.com/nesquena/hermes-webui .codex-tmp/hermes-webui`).
   That upstream copy is read-only — never modify it (refreshing via `git pull` is fine).
2. **No new third-party dependencies** beyond the spec's locked list without approval.
3. **Tolerant decoding:** every `Codable` model uses optionals for fields upstream
   might add/rename. Never crash on unknown fields.
4. **No destructive commands** (`rm -rf`, `git push --force`, anything touching
   `~/Library/LaunchAgents/` or restarting Mac services). Suggest them; let the human run them.
5. **Don't commit broken builds.** If a build or test fails, fix it before writing more code.

## Tooling
- The maintainer works in **VS Code**, not the Xcode UI — prefer terminal validation;
  ask to open Xcode only when the terminal can't answer.
- **Do not run simulator validation for this repo.** Do not use XcodeBuildMCP simulator
  run/install/log flows, `xcrun simctl`, or simulator launch checks unless the human
  explicitly asks for simulator work in that turn.
- For runtime/manual app validation, build and upload the real app to TestFlight with
  `scripts/push-testflight` so the human can test on device. Do not substitute a
  simulator run for a requested TestFlight push.
- Before asking for review or committing a slice: run practical terminal validation
  that does not launch the simulator, then use TestFlight for UI/runtime validation
  when the human asks to try the app.

## App identity (resolved via xcconfig — not grep-able)
Bundle ID `com.bryanliu.superhermex` · tests `….tests` · Team `87BJNUS53C` · SKU `hermex-super-ios`.

## TestFlight upload (maintainer-only)
Upload only the real SuperHermex app (`com.bryanliu.superhermex`) to TestFlight.
There is no side-by-side branch TestFlight app in this repo anymore. Do not add an
`APP_IDENTIFIER_SUFFIX`, suffixed bundle ID, branch xcconfig, or branch upload script.
Requires the maintainer's App Store Connect access and the local iOS signing keychain.
Run `scripts/push-testflight`; it resolves the bundle ID before archiving and refuses
to upload anything other than `com.bryanliu.superhermex`.

## Working with the human
- Surface tradeoffs in plain English before non-obvious choices; when in doubt, ask.
- Ask before touching anything under the spec's "Open questions."
- After each slice, report: (1) files changed (2) build/test command run (3) result
  (4) next suggested step — plus a short TestFlight/device test plan when UI changed.

## Keep this file honest
If something here surprises you or contradicts the project, tell the developer and
**propose** an AGENTS.md edit — don't silently edit it. This file is a Band-Aid for what
can't be fixed in code/tests/tooling; your proposed edits are also a signal of what to fix structurally.
