# Reynard latest IPA and Page Zoom

This ExecPlan follows the repository root `PLANS.md`. It must remain current as work proceeds.

## Purpose / Big Picture

Produce a verified latest-main Reynard IPA from the `lowestprime/reynard-browser` fork and then add a discoverable Page Zoom feature that works through Reynard's Gecko-based browsing stack.

## Success Criteria

- [x] The fork is synchronized with or verified against latest upstream `minh-ton/reynard-browser@main`.
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
- [x] Workflow fix committed and pushed.
- [x] Workflow rerun started.
- [x] Workflow rerun completed with a new WASI runtime failure.
- [x] Second targeted WASI runtime patch applied.
- [x] Non-final run confirmed dependencies passed and reached `Build Gecko`.
- [x] Latest upstream `minh-ton/reynard-browser@main` merged.
- [x] Quick upstream/fork release audit completed; no clearly newer downloadable IPA was found.
- [x] Latest-main run `27994353614` completed Gecko and failed in Xcode archive signing.
- [x] Copy Gecko Stuff signing failure root cause identified.
- [x] Copy Gecko Stuff unsigned-archive fix committed and pushed as `49556ae`.
- [x] Unaccelerated rerun `28001189594` cancelled before another full Gecko rebuild.
- [x] Gecko build caching and checkpointing implemented and first rerun attempted.
- [x] Fast configure failure in run `28001837486` identified and patched.
- [ ] Checkpointed workflow rerun succeeds through Gecko artifact upload.
- [ ] IPA artifact downloaded and inspected.
- [ ] Page Zoom architecture inspected.
- [ ] Page Zoom implemented.
- [ ] Final Page Zoom build and artifact verified.
- [ ] Final outcome recorded.

## Surprises & Discoveries

- The latest failed run was still at commit `c0fa94f22fc8022ed632ef877917688578d9705a`, while local `main` has later AGENTS-only commits. The workflow bug remains in the current workflow file.
- Homebrew LLVM 22.1.7 on `macos-26` no longer provides `wasm-ld` under `/opt/homebrew/opt/llvm/bin`; Homebrew prints that LLD is a separate formula.
- Run `27993600431` proved the explicit `lld` patch worked: `command -v wasm-ld` returned `/opt/homebrew/opt/lld/bin/wasm-ld` and `wasm-ld --version` returned `Homebrew LLD 22.1.7`.
- The same run exposed the next WASI runtime dependency: `/opt/homebrew/opt/llvm/bin/clang --target=wasm32-unknown-wasi --sysroot=/opt/homebrew/share/wasi-sysroot /tmp/wasm-test.c -o /tmp/wasm-test.wasm` failed with `cannot open ... lib/wasm32-unknown-wasi/libclang_rt.builtins.a: No such file or directory`.
- Run `27993866717` passed `Install build dependencies`, `Update Gecko source`, `Apply Gecko patches`, `Build idevice FFI`, and `Force Gecko to use Xcode ld64`; it reached `Build Gecko` before being intentionally canceled because the fork had not yet merged latest upstream main.
- After `git fetch upstream main`, `upstream/main...HEAD` was `9 13`, proving the fork was missing nine upstream commits. The upstream head was `0fcee2c40f8629c50a9481419dfb9184c75c0236` (`Hide tab bar when in iPad 1/3 split screen`).
- `git merge upstream/main --no-edit` completed without conflicts and produced merge commit `6190269606d3c09e97b70db08a9f85ecaf1d861e`; `git merge-base --is-ancestor upstream/main HEAD` then confirmed upstream is contained in the fork.
- Run `27994353614` uses head SHA `b37d9a14ce07b3e01e65891cb8ab2e808e74984e`, which includes the upstream merge and the build-plan update. The job passed dependency installation, Gecko source checkout, patch application, idevice FFI, and ld64 patching, then remained in `Build Gecko` for more than two hours with no live logs exposed by `gh`.
- A quick GitHub release/fork audit found upstream releases only through `0.4.0`, and sampled recent forks did not expose newer release assets. No third-party IPA has better provenance than completing this fork's workflow.
- Run `27994353614` proved the Gecko build now completes, then failed in `Build Reynard app archive` after 3h6m47s. The first real archive error was in `PhaseScriptExecution Copy Gecko Stuff`: `Apple Development: no identity found`, followed by `Command PhaseScriptExecution failed with a nonzero exit code`.
- The failing script was `browser/Scripts/AddGecko.sh`. It used `SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Apple Development}}"` and invoked `codesign` unconditionally, even though the workflow archive command passed `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- Run `28001189594` was started from commit `49556ae` but was cancelled at about 10m27s before entering a long Gecko rebuild. This preserves GitHub runner time while acceleration/checkpointing is added.
- Run `28001837486` validated the new workflow shape through dependency install, `actions/cache/restore`, Gecko source checkout, patches, idevice FFI, and ld64 detection patching. It failed quickly in `Build Gecko` configure before a long rebuild.
- The first real error in run `28001837486` was `mozbuild.configure.options.InvalidOptionError: MOZ_LINKER takes 0 values`. The generated `.mozconfig` already had `--enable-linker=ld64`; the problem was leaving the `MOZ_LINKER=ld64` environment variable visible to Firefox configure.

## Decision Log

- Decision: Install Homebrew `lld` explicitly and find `wasm-ld` through `command -v`.
  - Reason: The failing log proves `wasm-ld` is missing from the LLVM formula path, and Homebrew says to install `lld`.
  - Evidence: Run `27987957678`, `Install build dependencies`, `/opt/homebrew/opt/llvm/bin/wasm-ld: No such file or directory`.
  - Consequence: The workflow keeps Apple clang for iOS/macOS while exposing LLD only to WASM wrapper commands and the WASM link preflight.
- Decision: Install Homebrew `wasi-runtimes` and pass its resource dir through the WASM wrappers.
  - Reason: The next failed log shows `wasm-ld` is now available but clang lacks WASI Compiler-RT builtins. Homebrew describes `wasi-runtimes` as the Compiler-RT and libc++ runtimes for WASI.
  - Evidence: Run `27993600431`, `Install build dependencies`, `wasm-ld --version` succeeded, then clang failed opening `libclang_rt.builtins.a`.
  - Consequence: The next run is the one further targeted WASI repair allowed before falling back to `--without-wasm-sandboxed-libraries` if WASI still fails.
- Decision: Cancel run `27993866717` and merge upstream before continuing.
  - Reason: A successful artifact from that run would not have satisfied the latest-main requirement because upstream/main was not contained in the fork.
  - Evidence: `git rev-list --left-right --count upstream/main...HEAD` returned `9 13`.
  - Consequence: The next workflow run must use a merged commit after `6190269606d3c09e97b70db08a9f85ecaf1d861e`.
- Decision: Make `browser/Scripts/AddGecko.sh` skip Gecko artifact signing for unsigned archives.
  - Reason: The workflow intentionally builds an unsigned SideStore IPA and already passes Xcode signing suppression flags; the copy script must not invent `Apple Development` when no identity exists.
  - Evidence: Run `27994353614`, `Build Reynard app archive`, `Apple Development: no identity found`.
  - Consequence: Local signed Xcode builds can still sign Gecko artifacts when Xcode provides an identity, while CI unsigned archives can proceed to IPA packaging.
- Decision: Stop rerunning the monolithic workflow and add caching/checkpointing before the next build.
  - Reason: Run `27994353614` already proved the expensive Gecko compile passes; repeating it for every archive-stage failure creates a 2.5-3 hour feedback loop.
  - Evidence: Run `28001189594` was only about ten minutes old when cancelled, while `27994353614` spent roughly 2h53m in `Build Gecko` before the later archive failure.
  - Consequence: The next workflow run must include `sccache`, a saved Gecko dist checkpoint, and an archive job/path that can retry IPA packaging without rebuilding Gecko.
- Decision: Consume and unset `MOZ_LINKER` inside `tools/development/build-gecko.sh`.
  - Reason: The script needs `MOZ_LINKER` to write durable `.mozconfig`, but Firefox configure rejects the environment variable when it remains set.
  - Evidence: Run `28001837486`, `Build Gecko`, `InvalidOptionError: MOZ_LINKER takes 0 values`.
  - Consequence: The workflow can still set `MOZ_LINKER=ld64`, while `mach build` only sees the supported `--enable-linker=ld64` configure option.

## Build Acceleration Objective

Baseline timing evidence:

- Run `27994353614`: total job time was 3h6m52s.
- `Build Gecko` started at `2026-06-23T01:01:27Z`; `Build Reynard app archive` started at `2026-06-23T03:54:26Z`, so the successful Gecko step took about 2h53m wall time on the free `macos-26` runner.
- The first post-Gecko failure was archive-stage signing in `browser/Scripts/AddGecko.sh`, proving archive and IPA debugging should not require another full Gecko compile.
- Run `28001189594` was cancelled at about 10m27s before the long Gecko build repeated.

macOS-only stages:

- Final `xcodebuild archive`, iPhoneOS SDK usage, `xcrun`, app-extension validation, `ldid` IPA packaging, and all direct use of Xcode must stay on a macOS runner.
- Gecko iOS target compilation currently depends on Apple/Xcode clang for host/target paths and must remain on macOS unless a separate toolchain experiment proves otherwise.

Cacheable/checkpointable stages:

- Gecko C/C++/Rust object compilation can use local `sccache` on the macOS runner.
- The `sccache` directory is capped at `8G` and keyed by runner OS/arch, `engine/release.txt`, the workflow file, `tools/development/build-gecko.sh`, and patch hashes.
- `engine/firefox/obj-aarch64-apple-ios/dist` plus `engine/firefox/toolkit/mozapps/extensions/default-theme` is uploaded as short-retention artifact `gecko-dist-aarch64-apple-ios` after a successful Gecko build.

WSL2 feasibility:

- The user's ThinkPad has i7-12800H, 14 cores / 20 logical processors, 64 GB RAM, and NVMe SSD, so it is a strong candidate for a Linux `sccache-dist` worker for compatible compile actions.
- WSL2 must not run Xcode, iPhoneOS SDK, `xcrun`, signing, or IPA packaging.
- WSL2 distributed compilation is not considered working until `sccache --dist-status` and `sccache -s` show useful distributed compilations. If distributed compilations remain zero, WSL acceleration has not worked.
- Tailscale or equivalent network setup would require user-provided credentials/secrets. Exact likely GitHub secrets, if pursued later, are `SCCACHE_DIST_AUTH_TOKEN`, `TAILSCALE_AUTHKEY`, and a server address/port value such as `SCCACHE_DIST_SCHEDULER_URL`; these are not guessed or added in this pass.

Exact workflow/script changes:

- `tools/development/build-gecko.sh` now honors `MOZ_BUILD_JOBS`, `MOZ_LINKER`, `WASI_SYSROOT`, and executable `SCCACHE_BIN`, writes matching `.mozconfig` options, runs `./mach build -j "$MOZ_BUILD_JOBS"`, and prints `sccache -s` before/after.
- `.github/workflows/build-latest-reynard-ipa.yml` is split into `build-gecko` and `archive-ipa` jobs.
- `build-gecko` installs `sccache`, restores/saves `.sccache`, builds Gecko, records cache size/statistics, and uploads `gecko-dist-aarch64-apple-ios`.
- `archive-ipa` downloads `gecko-dist-aarch64-apple-ios`, rebuilds idevice FFI, archives with `REYNARD_UNSIGNED_ARCHIVE=1`, creates/verifies the IPA, and uploads `Reynard-latest-main-ipa`.
- `.github/workflows/archive-reynard-ipa-from-gecko-dist.yml` is a manual archive-only diagnostic workflow with a required `run_id` input that downloads a prior Gecko checkpoint artifact.

Validation commands:

```powershell
bash -n tools/development/build-gecko.sh
bash -n tools/release/build-app.sh
bash -n browser/Scripts/AddGecko.sh
git diff --check
gh workflow run "Build Latest Reynard IPA" --repo lowestprime/reynard-browser --ref main
gh run watch <RUN_ID> --repo lowestprime/reynard-browser
gh run view <RUN_ID> --repo lowestprime/reynard-browser --log-failed
gh run download <RUN_ID> --repo lowestprime/reynard-browser --name gecko-dist-aarch64-apple-ios --dir "$env:USERPROFILE\Desktop\reynard-gecko-dist-latest"
gh workflow run "Archive Reynard IPA From Gecko Dist" --repo lowestprime/reynard-browser --ref main -f run_id=<RUN_ID>
```

Rollback path:

- If `sccache` breaks configure/build, remove the `CCACHE=$SCCACHE_BIN` `.mozconfig` option and keep the split checkpoint artifact.
- If the Gecko dist artifact is too large or incomplete, keep local `sccache` and temporarily merge the archive job back into the Gecko job while recording the artifact size/failure.
- If archive-only download cannot find the run artifact, rerun the main checkpoint workflow once to produce a fresh `gecko-dist-aarch64-apple-ios` artifact and use that run ID.
- If cache restore/save causes eviction/thrashing, reduce `SCCACHE_CACHE_SIZE` below `8G` or narrow restore keys; do not cache the full Firefox object directory without measured size evidence.

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

Additional commands after first rerun:

```powershell
gh run view 27993600431 --repo lowestprime/reynard-browser --log-failed
gh run view 27993600431 --repo lowestprime/reynard-browser --json databaseId,headSha,headBranch,conclusion,status,url,createdAt,updatedAt,workflowName,jobs
gh run cancel 27993866717 --repo lowestprime/reynard-browser
git fetch upstream main
git merge-base --is-ancestor upstream/main HEAD
git rev-list --left-right --count upstream/main...HEAD
git merge upstream/main --no-edit
gh api repos/minh-ton/reynard-browser/releases --paginate --jq '.[] | {tag_name, name, published_at, target_commitish, assets: [.assets[] | {name, browser_download_url, size}]}'
gh api repos/minh-ton/reynard-browser/forks --paginate --jq '.[] | {full_name, pushed_at, default_branch, html_url}'
gh run view 27994353614 --repo lowestprime/reynard-browser --log-failed
gh run download 27994353614 --repo lowestprime/reynard-browser --name Reynard-build-debug --dir "$env:USERPROFILE\Desktop\reynard-build-debug-latest"
gh run cancel 28001189594 --repo lowestprime/reynard-browser
gh run view 28001837486 --repo lowestprime/reynard-browser --log-failed
gh run download 28001837486 --repo lowestprime/reynard-browser --name Reynard-build-debug-gecko --dir "$env:USERPROFILE\Desktop\reynard-build-debug-28001837486"
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
