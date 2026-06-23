# Reynard latest IPA and Page Zoom

This ExecPlan follows the repository root `PLANS.md`. It must remain current as work proceeds.

## Purpose / Big Picture

Produce a verified latest-main Reynard IPA from the `lowestprime/reynard-browser` fork and then add a discoverable Page Zoom feature that works through Reynard's Gecko-based browsing stack.

## Success Criteria

- [ ] The fork is synchronized with or verified against latest upstream `minh-ton/reynard-browser@main`.
- [ ] GitHub Actions workflow `Build Latest Reynard IPA` completes successfully on `main`.
- [ ] Artifact `Reynard-latest-main-ipa` is uploaded and downloaded locally.
- [ ] Downloaded artifact contains `Reynard.ipa`.
- [ ] IPA contents include `Payload/Reynard.app/Reynard` plus required app extensions.
- [ ] Build identity is post-0.4.0 and not only public build `63836c3`.
- [ ] Page Zoom supports zoom out, zoom in, reset, displayed percentage, per-site persistence where feasible, and a default/global zoom where feasible.
- [ ] Page Zoom applies to the active tab without restarting the app.
- [ ] Relevant local checks and final GitHub Actions build are run and recorded.

## Current State

Working directory: `C:\Users\Cooper\Desktop\reynard-browser`.

Branch: `main`, tracking `origin/main`.

Initial `git status --short --branch`:

```text
## main...origin/main
?? .codex/
```

Recent commits include:

```text
3eb3881 Add Codex agent instructions for Reynard build automation
454565e Add Codex agent instructions for Reynard build automation
c0fa94f Expose wasm-ld for Gecko WASI linker
```

Latest inspected workflow failure:

- Run ID: `27987957678`
- URL: `https://github.com/lowestprime/reynard-browser/actions/runs/27987957678`
- Branch: `main`
- Head SHA: `c0fa94f22fc8022ed632ef877917688578d9705a`
- Failed step: `Install build dependencies`
- Exact failing line: `/opt/homebrew/opt/llvm/bin/wasm-ld --version`
- Exact error: `/opt/homebrew/opt/llvm/bin/wasm-ld: No such file or directory`
- Important preceding Homebrew caveat: `LLD is now provided in a separate formula: brew install lld`

## Constraints

- Do not use `engine/firefox` as the project root.
- Do not commit arbitrary durable changes inside `engine/firefox`; use root workflow, `tools/`, or `patches/`.
- Keep Apple/Xcode clang as `CC`, `CXX`, `HOST_CC`, and `HOST_CXX` unless logs prove a change is required.
- Use Homebrew LLVM/LLD only for WASM/WASI compiler/linker plumbing.
- Do not use unknown third-party IPAs as final success without verified provenance.
- Continue the build/log/patch loop autonomously until success or a real external blocker.
- If WASI linking still fails after explicit `lld` and one targeted repair, document the exact error before using `--without-wasm-sandboxed-libraries`.

## Progress

- [x] Goal objective read.
- [x] Root `AGENTS.md` read.
- [x] Root `PLANS.md` read.
- [x] CI-fix skill instructions read.
- [x] Latest workflow run and failed log inspected.
- [x] ExecPlan created.
- [x] First workflow patch applied for explicit Homebrew `lld` and `wasm-ld` lookup.
- [ ] Workflow fix committed and pushed.
- [ ] Workflow rerun started.
- [ ] Workflow rerun completed.
- [ ] IPA artifact downloaded and inspected.
- [ ] Page Zoom architecture inspected.
- [ ] Page Zoom implemented.
- [ ] Final Page Zoom build and artifact verified.
- [ ] Final outcome recorded.

## Surprises & Discoveries

- The latest failed run was still at commit `c0fa94f22fc8022ed632ef877917688578d9705a`, while local `main` has later AGENTS-only commits. The workflow bug remains in the current workflow file.
- Homebrew LLVM 22.1.7 on `macos-26` no longer provides `wasm-ld` under `/opt/homebrew/opt/llvm/bin`; Homebrew prints that LLD is a separate formula.

## Decision Log

- Decision: Install Homebrew `lld` explicitly and find `wasm-ld` through `command -v`.
  - Reason: The failing log proves `wasm-ld` is missing from the LLVM formula path, and Homebrew says to install `lld`.
  - Evidence: Run `27987957678`, `Install build dependencies`, `/opt/homebrew/opt/llvm/bin/wasm-ld: No such file or directory`.
  - Consequence: The workflow keeps Apple clang for iOS/macOS while exposing LLD only to WASM wrapper commands and the WASM link preflight.

## Plan of Work

First repair `.github/workflows/build-latest-reynard-ipa.yml` so the dependency step installs `lld`, prepends `/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin` for WASM-only wrapper commands, uses `command -v wasm-ld`, and validates a real WASM link using the Homebrew WASI sysroot. Commit, push, trigger the workflow, and inspect the result.

If the workflow fails, retrieve failed logs and the debug artifact if available, identify the exact failing lines, update this plan, patch the smallest root cause, commit, push, and rerun.

After the IPA workflow is green and the artifact is downloaded and inspected, inspect Reynard's tab/session/settings/menu/GeckoView architecture before implementing Page Zoom. Prefer Gecko/session preference support; add conservative fallback behavior only if the current iOS GeckoView layer lacks true page zoom. Then run local validation available on Windows and final GitHub Actions validation.

## Concrete Steps

Commands run so far:

```powershell
git status --short --branch
git log --oneline -10
gh auth status
gh run list --repo lowestprime/reynard-browser --workflow "Build Latest Reynard IPA" --limit 5
gh run view 27987957678 --repo lowestprime/reynard-browser --json databaseId,headSha,headBranch,conclusion,status,url,createdAt,updatedAt,event,workflowName,displayTitle
gh run view 27987957678 --repo lowestprime/reynard-browser --log-failed
```

Next commands:

```powershell
git diff --check
git diff -- .github/workflows/build-latest-reynard-ipa.yml .agent/execplans/20260623_reynard-latest-ipa-page-zoom.md
git add .github/workflows/build-latest-reynard-ipa.yml .agent/execplans/20260623_reynard-latest-ipa-page-zoom.md
git commit -m "ci: expose Homebrew lld for Gecko WASI"
git push origin main
gh workflow run "Build Latest Reynard IPA" --repo lowestprime/reynard-browser --ref main
gh run list --repo lowestprime/reynard-browser --workflow "Build Latest Reynard IPA" --limit 5
gh run watch <RUN_ID> --repo lowestprime/reynard-browser
```

## Validation

Build validation:

- Workflow `Build Latest Reynard IPA` must complete successfully.
- Artifact `Reynard-latest-main-ipa` must exist for the successful run.
- Downloaded artifact must contain `Reynard.ipa`.
- `unzip -l Reynard.ipa` must show the main app and required extensions.

Feature validation:

- Local static/build checks available on Windows must pass or be documented if unavailable.
- Final GitHub Actions build after Page Zoom must upload a fresh IPA artifact.
- Physical iPhone checks for iOS 26.6 Developer Beta 2, SideStore, LocalDevVPN, and JIT/TXM remain manual unless the device is available.

## Recovery / Fallbacks

If explicit `lld` still cannot expose `wasm-ld`, inspect `brew --prefix lld`, `ls /opt/homebrew/opt/lld/bin`, and `command -v wasm-ld` from the failed run logs or debug artifact, then patch the wrapper path once.

If WASI compile succeeds but link fails after that targeted repair, switch Gecko mozconfig generation from `--with-wasi-sysroot=/opt/homebrew/share/wasi-sysroot` to `--without-wasm-sandboxed-libraries` and record the exact log lines that justify the fallback.

If later app archive or IPA creation fails, retrieve `Reynard-build-debug` and inspect Xcode logs, `dist`, `browser/Configuration/Reynard.xcconfig`, and app extension packaging before patching.

## Outcomes & Retrospective

- What changed:
- What passed:
- What failed or remains unknown:
- Artifact/run/commit identifiers:
- Recommended next action:
