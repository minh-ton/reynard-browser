# Reynard latest IPA and Page Zoom

This ExecPlan follows the repository root `PLANS.md`. It must remain current as work proceeds.

## Purpose / Big Picture

Produce a verified latest-main Reynard IPA from the `lowestprime/reynard-browser` fork and then add a discoverable Page Zoom feature that works through Reynard's Gecko-based browsing stack.

## Success Criteria

- [x] The fork is synchronized with or verified against latest upstream `minh-ton/reynard-browser@main`.
- [x] GitHub Actions workflow `Build Latest Reynard IPA` completes successfully on `main`.
- [x] Artifact `Reynard-latest-main-ipa` is uploaded and downloaded locally.
- [x] Downloaded artifact contains `Reynard.ipa`.
- [x] IPA contents include `Payload/Reynard.app/Reynard` plus required app extensions.
- [x] Build identity is post-0.4.0 and not only public build `63836c3`.
- [x] Page Zoom supports zoom out, zoom in, reset, displayed percentage, per-site persistence where feasible, and a default/global zoom where feasible.
- [x] Page Zoom applies to the active tab without restarting the app.
- [x] Relevant local checks and final GitHub Actions build are run and recorded.

## Current State

Working directory: `C:\Users\Cooper\Desktop\reynard-browser`.

Branch: `main`, tracking `origin/main`.

Initial `git status --short --branch`:

```text
## main...origin/main
?? .codex/
```

## Verified Baseline IPA

- Patch commit: `5f2bfd48b5611b3601c0b2ff6db040b7d5320e57` (`ci: make Gecko checkpoint inspection pipefail-safe`).
- Archive-only workflow run: `28036622785`, `https://github.com/lowestprime/reynard-browser/actions/runs/28036622785`.
- Archive-only run result: success in `7m15s`.
- Archive job source checkout: `5f2bfd48b5611b3601c0b2ff6db040b7d5320e57`.
- Reused Gecko checkpoint: `gecko-dist-aarch64-apple-ios` from run `28002185987`.
- Uploaded artifact: `Reynard-latest-main-ipa`.
- Local downloaded artifact path: `C:\Users\Cooper\Downloads\Reynard-latest-main-28036622785\Reynard.ipa`.
- Workflow verification: `dist/Reynard.ipa` existed, was about `105M`, and had SHA-256 `a62f30094cdafe43e426823e961b0d2b98ed59e4f418de8ba3f9265c703b9aab`.
- Local verification command: `unzip -Z1 C:\Users\Cooper\Downloads\Reynard-latest-main-28036622785\Reynard.ipa`.
- Verified IPA entries:
  - `Payload/Reynard.app/Reynard`
  - `Payload/Reynard.app/PlugIns/Reynard Helper.appex/Info.plist`
  - `Payload/Reynard.app/PlugIns/OpenIn.appex/Info.plist`
- Build identity evidence: archive log showed `CURRENT_BUILD=5f2bfd4` and `CURRENT_PROJECT_VERSION=5f2bfd4`, so this is a post-0.4.0 build identity, not only public build `63836c3`.
- Page Zoom can begin from this verified baseline IPA. The full split `Build Latest Reynard IPA` workflow still has not been rerun after the pipefail-safe patch because the user explicitly prioritized archive-only reuse of the existing Gecko checkpoint.

## Page Zoom Implementation

Current implementation state:

- Reynard's tab/session/settings/menu architecture has been inspected. The feature is wired through the existing `SessionSettingsManager`, `GeckoSessionSettings`, address-bar page menu, and browsing settings screens.
- The page menu exposes `Page Zoom` controls for host-backed pages: zoom out, current percentage, zoom in, and reset to the configured default.
- Zoom levels are normalized to `50%, 75%, 85%, 100%, 115%, 125%, 150%, 175%, 200%, 250%, 300%`.
- Default zoom is stored under `Prefs.BrowsingSettings.defaultPageZoomPercent`.
- Site-specific overrides are stored under `Prefs.BrowsingSettings.pageZoomOverrides`, keyed by normalized host and matched through existing `DomainMatcher` behavior.
- Active-tab changes are applied immediately by sending updated `GeckoSessionSettings` to the selected `GeckoSession`.
- Durable Gecko source behavior is represented as a root-level patch: `patches/mobile/shared/modules/geckoview/GeckoViewSettings.sys.mjs.patch`. The patch applies `settings.pageZoom` to `browsingContext.fullZoom`.
- Local Windows validation has confirmed `git diff --check` for tracked changes and `git -C engine/firefox apply --check` for the Gecko patch. Swift/Xcode compilation is deferred to GitHub Actions because this Windows host does not provide `swift` or `xcodebuild`.

## Verified Page Zoom IPA

- Feature commit: `ac7c446aa4a8831579945e4d4cb49a33ce8cf670` (`feat(app): add page zoom controls`).
- Workflow run: `28038685786`, `https://github.com/lowestprime/reynard-browser/actions/runs/28038685786`.
- Run result: success in `26m51s`.
- Build job: `Build Gecko checkpoint`, job ID `82998916130`, success in `20m42s`.
- Archive job: `Archive IPA from Gecko checkpoint`, job ID `83003479854`, success in `5m52s`.
- Gecko checkpoint artifact: `gecko-dist-aarch64-apple-ios`, artifact ID `7826642917`, size `124047999` bytes, downloaded by the archive job with SHA-256 `ec43c3d1c73cd81329a8f1a8cb27b7a4722c5e14a7649f036a3867f72a4ef0fa`.
- IPA artifact: `Reynard-latest-main-ipa`, artifact ID `7826779137`, uploaded artifact zip size `107718673` bytes, uploaded artifact zip SHA-256 `4b75cd47758365e733580b2829234c75af61432d29c451678da1cab718b3be48`.
- Local downloaded IPA path: `C:\Users\Cooper\Downloads\Reynard-latest-main-28038685786\Reynard.ipa`.
- Local IPA size: `109612923` bytes.
- Local IPA SHA-256: `5ee4c3d7259ca22c7b1ce61c072da2a67c328b32137c24e58c02adae9c573291`.
- Local IPA verification with `unzip -Z1` found `3032` entries and confirmed:
  - `Payload/Reynard.app/Reynard`
  - `Payload/Reynard.app/PlugIns/Reynard Helper.appex/Info.plist`
  - `Payload/Reynard.app/PlugIns/OpenIn.appex/Info.plist`
- Workflow verification also found the main app binary, `Reynard Helper.appex`, and `OpenIn.appex`.
- Build identity evidence: archive log showed `CURRENT_BUILD = ac7c446` and `CURRENT_PROJECT_VERSION=ac7c446`, so the IPA is a post-0.4.0 build and not only public build `63836c3`.
- Acceleration evidence: `actions/cache/restore` restored a `2.44GB` sccache archive from run `28002185987`; `Build Gecko` reported `4645` cache hits, `71` misses, and `98.49%` hit rate. The `.sccache` directory was about `2.7G`; sccache reported `3 GiB` used with an `8 GiB` max.
- Checkpoint evidence: `engine/firefox/obj-aarch64-apple-ios/dist` was `299M` and uploaded as the `gecko-dist-aarch64-apple-ios` artifact before archive work began.

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
- [x] Checkpointed workflow rerun succeeds through Gecko artifact upload.
- [x] IPA artifact downloaded and inspected.
- [x] Page Zoom architecture inspected.
- [x] Page Zoom implemented.
- [x] Final Page Zoom build and artifact verified.
- [x] Final outcome recorded.

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
- Run `28038685786` validated the final Page Zoom build through the full split workflow. Gecko completed in about nine minutes after restoring sccache, the Gecko dist checkpoint was uploaded, the archive job consumed that checkpoint, and `Reynard-latest-main-ipa` uploaded successfully.

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
- Decision: Reuse the Gecko checkpoint from run `28002185987` and repair archive checkpoint inspection only.
  - Reason: Run `28002185987` completed `Build Gecko checkpoint` and uploaded `gecko-dist-aarch64-apple-ios`; rebuilding Gecko would waste the artifact and reintroduce the slow feedback loop.
  - Evidence: The archive job downloaded the checkpoint, `engine/firefox/obj-aarch64-apple-ios/dist/bin` existed, `engine/firefox/toolkit/mozapps/extensions/default-theme` existed, and `du -sh engine/firefox/obj-aarch64-apple-ios/dist` reported about `414M`.
  - Evidence: First-run `sccache` was cold/low-value: restore missed, post-build `sccache -s` showed `Cache hits 0`, `Cache misses 4716`, and the cache directory was about `2.7G`.
  - Evidence: The archive job then failed after the nonessential diagnostic listing `find engine/firefox/obj-aarch64-apple-ios/dist -maxdepth 2 | head -100` under `set -euo pipefail`.
  - Consequence: The next action is an archive-only rerun from `run_id=28002185987` after making the diagnostic listing pipefail-safe; Page Zoom remains deferred until the baseline IPA artifact is verified.

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

## Feature-Complete UX Batch After Page Zoom Release

Purpose: continue from the verified Page Zoom prerelease and add the next native UX/functionality batch while keeping upstream PR `minh-ton/reynard-browser#153` as the merge path. The previous prerelease remains immutable evidence for the Page Zoom baseline; the next deliverable must be a new verified fork prerelease and an updated PR branch.

Current verified source state:

- Local branch: `main`, tracking `origin/main`.
- Upstream PR: `https://github.com/minh-ton/reynard-browser/pull/153`.
- PR source: `lowestprime:main`.
- PR base: `minh-ton:main`.
- PR state checked after release: open, non-draft, mergeable.
- Local `HEAD`: `6f2a03d44c51bd36cc7a836dbd94a5ee33559392` (`docs: record verified Page Zoom IPA build`).
- Verified app-code release commit: `ac7c446aa4a8831579945e4d4cb49a33ce8cf670`.
- Verified release: `https://github.com/lowestprime/reynard-browser/releases/tag/reynard-page-zoom-2026-06-23`.
- Verified run: `28038685786`.
- Verified artifact: `Reynard-latest-main-ipa`.
- Verified local IPA: `C:\Users\Cooper\Downloads\Reynard-latest-main-28038685786\Reynard.ipa`.
- Verified SHA-256: `5ee4c3d7259ca22c7b1ce61c072da2a67c328b32137c24e58c02adae9c573291`.

Feature classification:

- A. Page Zoom refinement: native-app UI/settings logic unless new Gecko behavior is discovered. Expected build path: archive-only using the `gecko-dist-aarch64-apple-ios` checkpoint from run `28038685786`.
- B. Keyboard/page-content behavior: native UIKit/GeckoView layout and lifecycle logic unless focused-input geometry from Gecko is required. Expected build path: archive-only.
- C. Background/session preservation and stability: native lifecycle/session/preferences/JIT-state handling with manual physical-device validation for OS/JIT behavior. Expected build path: archive-only.
- D. Bookmark/history import/export/sync: native app data/storage/UI work. Real Firefox Sync is out of scope unless existing account/protocol support is discovered. Expected build path: archive-only.
- E. Address bar autocomplete: native address bar suggestions sourced from local bookmarks/history/open tabs/common URL parsing/search fallback. Expected build path: archive-only.
- F. OLED jet-black theme and accent customization: native settings/theme/accent/resource work. Expected build path: archive-only.

Progress for this continuation:

- [x] New goal objective file read.
- [x] Root `AGENTS.md` reread.
- [x] Root `PLANS.md` reread.
- [x] Existing ExecPlan reread.
- [x] Local branch and upstream PR source checked.
- [x] Existing Page Zoom, keyboard, lifecycle/session, bookmark/history, address bar, and theme code inspected.
- [x] Page Zoom slider refinement implemented.
- [x] Keyboard/page-content behavior improved.
- [x] Background/session preservation improvements implemented.
- [x] Bookmark/history import/export entry points implemented or documented where unsupported.
- [x] Address bar autocomplete implemented.
- [x] OLED black theme and accent customization implemented.
- [x] Local static checks passed.
- [x] Archive-only workflow run completed using an existing Gecko checkpoint, or exact evidence recorded for why a full checkpoint run was required.
- [x] New IPA downloaded and verified.
- [x] New fork prerelease published without overwriting `reynard-page-zoom-2026-06-23`.
- [x] Upstream PR `#153` updated and confirmed open/mergeable where possible.

Implemented native-only changes in this continuation:

- Page Zoom: the address-bar page menu now opens a persistent Page Zoom sheet with a slider, zoom out, reset, zoom in, live percent display, and live `GeckoSessionSettings` refresh. Slider mapping/clamping is centralized in `PageZoomLevel`.
- Keyboard/page content: focused-input relocation clamps Gecko focused-input ratios and uses actual keyboard/content intersection, avoiding unnecessary shifts for non-overlapping/floating keyboard frames.
- Background/session preservation: app and scene lifecycle notifications now capture the visible tab thumbnail, flush tab/session state, reactivate the selected Gecko session, refresh chrome/navigation state, and reapply page zoom on foreground.
- Bookmark/history transfer: bookmarks can be imported from Firefox/Netscape-style HTML and exported to HTML; history can be imported/exported as local CSV with privacy confirmations. This is local transfer only and does not claim Firefox Sync.
- Address bar autocomplete: suggestions now always include local common-domain/URL fallback completions, search-engine suggestions are opt-in in Search settings and debounced, and private browsing no longer surfaces regular history matches.
- Appearance: Appearance settings now include theme mode, OLED Black, and accent color choices; app windows/chrome/settings/library surfaces apply the selected theme/accent without restart.

Archive-only validation attempt:

- Run `28058053384` used archive-only workflow `Archive Reynard IPA From Gecko Dist` at commit `7fe5048ecbbbe89873970a144aed0d7e07de53c3` with Gecko checkpoint run `28038685786`.
- The checkpoint path was proven: checkout, archive dependency install, Gecko dist artifact download, checkpoint inspection, and idevice FFI all succeeded without a Gecko rebuild.
- The archive failed in `Build Reynard app archive` with Xcode exit `65`.
- First real source error: `ContentView.swift:184` attempted to call `min(max(bottomRatio, 0), 1)` where `GeckoSession.focusedInputBottomRatio()` returns `CGFloat?`.
- Fix: handle `nil` focused-input geometry by clearing/resetting focused-input relocation, then clamp only non-optional ratios.
- Repeated local validation after the fix: `git diff --check`, `bash -n tools/development/build-gecko.sh`, `bash -n tools/release/build-app.sh`, and `bash -n browser/Scripts/AddGecko.sh` all returned zero.

Final feature-complete UX IPA validation:

- Final commit: `240928640a1adbab8f9353cc07f35563f10a922b` (`fix(app): handle missing focused input metrics`).
- Successful archive-only workflow run: `28058553866`, `https://github.com/lowestprime/reynard-browser/actions/runs/28058553866`.
- Run result: success in `4m26s`.
- Reused Gecko checkpoint: `gecko-dist-aarch64-apple-ios` from run `28038685786`.
- Archive job source checkout: `240928640a1adbab8f9353cc07f35563f10a922b`.
- Uploaded artifact: `Reynard-latest-main-ipa`.
- Local downloaded IPA: `C:\Users\Cooper\Downloads\Reynard-latest-main-28058553866\Reynard.ipa`.
- Local IPA size: `109647473` bytes.
- Local IPA SHA-256: `6c73eb30b8307f82768ad13a20b169ea2ab334e5fea8d37d731d7b2b47593961`.
- `unzip -tq` passed with no compressed-data errors.
- ZIP inspection found `3032` entries and `0` duplicate paths.
- Required packaged entries were present:
  - `Payload/Reynard.app/Reynard`
  - `Payload/Reynard.app/PlugIns/Reynard Helper.appex/Info.plist`
  - `Payload/Reynard.app/PlugIns/OpenIn.appex/Info.plist`
  - `Payload/Reynard.app/Frameworks/GeckoView.framework/GeckoView`
- `CFBundleVersion` was `2409286` for the main app, `Reynard Helper.appex`, and `OpenIn.appex`; `CFBundleShortVersionString` was `0.4.0`.
- Main app, helper extension, OpenIn extension, and GeckoView binaries had Mach-O 64-bit little-endian headers.
- Feature string scan found `Page Zoom`, `Zoom Out`, `Zoom In`, `Reset`, `OLED Black`, `Search Suggestions`, `Local Suggestions`, `Import Bookmarks`, `Export Bookmarks`, `Site override`, `Firefox/Netscape`, and `Reynard-History.csv`. `Import History` and `Export History` did not appear as plain UTF-8/UTF-16 byte strings even though the history CSV code path compiled and the history CSV filename was present.
- New fork prerelease: `https://github.com/lowestprime/reynard-browser/releases/tag/reynard-feature-complete-ux-2026-06-23`.
- Release assets:
  - `Reynard.ipa`, size `109647473`, digest `sha256:6c73eb30b8307f82768ad13a20b169ea2ab334e5fea8d37d731d7b2b47593961`.
  - `Reynard.ipa.sha256`, size `77`, digest `sha256:55dfcce7e25e8b0df1adf1b4467c1c18ca19cd0a2301a31c02466148e2f95fff`.
- Upstream PR `https://github.com/minh-ton/reynard-browser/pull/153` remains open, non-draft, and mergeable with head `240928640a1adbab8f9353cc07f35563f10a922b`.

Build strategy:

- Avoid Gecko edits for this batch unless inspection proves they are necessary.
- Reuse a valid `gecko-dist-aarch64-apple-ios` artifact from run `28038685786` through the archive-only workflow for native-only changes.
- If that checkpoint is expired or unavailable, record the exact artifact lookup/download failure and run the checkpointed full workflow once.
- Do not leave a long full Gecko build running as passive polling work; if a long build is unavoidable, record a handoff in this ExecPlan.

Validation gates for this continuation:

- `git diff --check`.
- `bash -n tools/development/build-gecko.sh`.
- `bash -n tools/release/build-app.sh`.
- `bash -n browser/Scripts/AddGecko.sh`.
- YAML parse checks for workflow files if changed.
- `git -C engine/firefox apply --check <patch>` only if a Gecko patch changes.
- GitHub Actions archive/build run.
- Download produced `Reynard.ipa`.
- `unzip -tq` on the IPA.
- Verify main app, `Reynard Helper.appex`, `OpenIn.appex`, and `GeckoView.framework/GeckoView` are packaged.
- Verify feature strings/symbols for new UI where possible.
- Verify main app and extension build versions match the expected short SHA.
- Record new IPA SHA-256.

Manual physical-device validation that must not be claimed without evidence:

- Install the new unsigned IPA through the intended sideload flow.
- Page Zoom slider and plus/minus controls at 75%, 100%, 150%, and 200%.
- Focus text inputs, textareas, contenteditable fields, and forms with the keyboard visible at 75%, 100%, 150%, and 200%.
- Background app for 1 minute and return.
- Background app for 10+ minutes and return.
- Switch between several tabs after resume.
- Resume with JIT disabled.
- Resume with JIT previously enabled.
- Low-memory or forced relaunch if testable.
- Verify pages, tabs, zoom, theme/accent, and navigation state remain stable.

## Keyboard Obstruction Regression Fix

Purpose: repair the remaining real-device regression where bottom-fixed page composers and focused page inputs can stay hidden behind the iOS keyboard and Reynard bottom chrome on the latest feature-complete IPA. This is a targeted native-only continuation; Page Zoom, bookmark/history transfer, autocomplete, theme work, and release plumbing should not be reimplemented except where validation requires it.

User evidence to preserve:

- `https://chatgpt.com`: the ChatGPT input composer/page content remains partly hidden behind the iOS keyboard and/or bottom browser chrome when the keyboard opens.
- `https://gemini.google.com`: the Gemini bottom composer is visible with the keyboard closed, but keyboard open leaves page composer/content obscured instead of repositioned into the visible viewport.
- This affects bottom-fixed modern web-app composers, not only ordinary scrollable form fields.
- The prior focused-input relocation batch is incomplete because it depends on Gecko focused-input geometry and resets when that geometry is nil.

Current inspected implementation:

- `BrowserViewController.keyboardFrameWillChange(_:)` computes keyboard overlap and only calls `ContentView.relocateFocusedInput(above:)` for page keyboard events.
- `ContentView.relocateFocusedInput(above:)` asks Gecko for `focusedInputBottomRatio()` and translates the content with `focusedInputOffset` when a focused editable metric exists.
- If Gecko returns nil focused-input geometry, `ContentView` resets focused-input relocation, so bottom-fixed SPA composers get no fallback.
- The normal phone content bottom is anchored to `browserChrome.bottomToolbarTopAnchor`; when the software keyboard covers the bottom of the app, that anchor can still sit underneath the keyboard, leaving the Gecko viewport too tall for bottom-fixed page UI.

Fix design:

- Keep the change native-only so the archive-only workflow can reuse Gecko checkpoint run `28038685786`.
- Add a real page viewport bottom inset to `ContentView` and drive it from the actual intersection between the root view, current content view frame, and keyboard frame.
- Treat focused-input metrics as a secondary correction. Values above `1.0` are allowed because Gecko's patch reports a viewport-relative bottom ratio up to `2.0`; values above `1.0` mean the focused editable is below the currently visible viewport.
- Keep native address bar/search keyboard behavior separate: when the native address bar is focused, reset page keyboard avoidance and keep docking the address bar above the keyboard.
- Recompute keyboard avoidance on keyboard show/hide/frame changes, layout changes, foreground restore, and Page Zoom preference changes.

Manual test checklist for the fixed IPA:

- Gemini keyboard closed: bottom composer visible.
- Gemini keyboard open: composer remains above keyboard and bottom chrome.
- ChatGPT keyboard open: composer remains above keyboard and bottom chrome.
- Repeat at 75%, 100%, 150%, and 200% page zoom.
- Rotate device if feasible.
- Background/foreground after keyboard use.
- JIT disabled.
- JIT previously enabled if available.
- Native address bar editing still works.
- Autocomplete overlay still works.
- Page Zoom sheet stays open while pressing plus/minus or moving the slider.

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

- What changed: the workflow now uses sccache restore/save and a Gecko dist checkpoint; Reynard now has Page Zoom controls in the address-bar page menu, default zoom settings, per-host zoom persistence, and a GeckoView patch that applies `pageZoom` through `browsingContext.fullZoom`.
- What passed: local static checks, Gecko patch application check, the final `Build Latest Reynard IPA` GitHub Actions workflow, artifact upload, artifact download, IPA hash verification, and IPA payload checks.
- What failed or remains unknown: no current build failure. Physical iOS 26.6 / iPhone 15 Pro Max JIT/TXM behavior and hands-on Page Zoom UX remain device checks.
- Artifact/run/commit identifiers: feature commit `ac7c446aa4a8831579945e4d4cb49a33ce8cf670`; successful run `28038685786`; IPA artifact `Reynard-latest-main-ipa` ID `7826779137`; local IPA `C:\Users\Cooper\Downloads\Reynard-latest-main-28038685786\Reynard.ipa`.
- Recommended next action: install the verified IPA on the target device and manually check JIT/TXM behavior plus Page Zoom controls on several sites.
