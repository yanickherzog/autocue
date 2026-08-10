# AutoCue — Architecture Decision Records

The record of *why* — not every commit, only real architectural calls: a real trade-off, a library choice, a reversed earlier decision, something a later session might reasonably second-guess without this context. `CLAUDE.md` says *how* to build; `SPEC.md` says *what* to build; this file says *why* it's built that way instead of some other way that was genuinely considered.

Every entry uses the same five fields:

- **Decision** — the call, stated plainly.
- **Context** — what was true at the time that made this a real question, not a formality.
- **Alternatives Considered** — what else was genuinely on the table, including an option later reversed elsewhere in this log — reversals are recorded as new entries that reference the old one, never by silently editing the old entry.
- **Reason for Choice** — why this one, specifically, over the alternatives.
- **Consequences** — what this rules out, what it commits future work to, and any residual gap it doesn't close.

Entries are chronological, oldest first. `CONTRIBUTING.md` §2 and `docs/DefinitionOfDone.md` §4 both point back here for when a change needs an entry.

---

## 2026-08-08 — Rename `Duration` to `MediaDuration`

**Decision:** The domain's length-of-time value type is `MediaDuration`, not the originally-planned `Duration`.

**Context:** `SPEC.md`'s original schema draft named this type `Duration`. Swift's standard library ships its own `Duration` type (`Swift.Duration`), used throughout Swift Concurrency (`ContinuousClock`, `Task.sleep(for:)`) and implicitly in scope in virtually any file touching `async`/`await` timing — which is most of this codebase, given `CLAUDE.md`'s concurrency-everywhere stance.

**Alternatives Considered:**
- **Keep `Duration` and rely on module-qualification (`Swift.Duration` vs. `ACCore.Duration`) to disambiguate.** Rejected — this pushes a landmine into every future file that imports both `ACCore` and touches Concurrency APIs, rather than removing it once, before any code exists.
- **`CueDuration`.** Rejected — the type isn't cue-specific; it's also used for `Setup.productionRuntime` and `Setup.totalMusicRuntime`, neither of which is a cue.
- **`MediaDuration`.** Chosen.

**Reason for Choice:** `MediaDuration` names what the type actually represents (a length of media time) without colliding with anything in Foundation or the standard library, and without being falsely scoped to just one use site the way `CueDuration` would be.

**Consequences:** Every `SPEC.md`/`CLAUDE.md` reference to the original name was updated in the same change (`SPEC.md` §4.8 is the type's full specification). No code existed yet when this was made, so there was no retrofit cost — this is the cheapest possible time to make this call, which is exactly why it was made immediately rather than deferred.

**Full detail:** `SPEC.md` §4.8.

---

## 2026-08-08 — Module dependency graph: `ACFeatures` as its own package, with an explicit limitation noted

**Decision:** `Features/` is not app-target code. It is its own local Swift package, `ACFeatures`, depending only on `ACCore` and `ACDesignSystem` — never on `ACAudioKit`, `ACExport`, or `ACPersistence`. Separately: the Technology Stack table's claim that module boundaries are "compiler-enforced" is corrected to state precisely what SPM does and doesn't gate.

**Context:** The original plan kept `Features/` inside the `AutoCue` app target directly, and the original tech-stack table described the whole modularization scheme as giving "compiler-enforced module boundaries, not just folder convention." Both were reviewed together because they're the same underlying issue: the app target legitimately links `SwiftData`/`AVFoundation` for `DependencyContainer`, so nothing would have stopped a screen living in that target from importing them directly too — the "ViewModels never touch the Data layer" rule would have been convention-enforced only, on exactly the layer most likely to accumulate violations across dozens of independently-built Feature milestones, while the docs claimed a stronger guarantee than actually existed.

**Alternatives Considered:**
- **Leave `Features/` in the app target, rely on code review to catch violations.** Rejected — this is precisely the "convention-enforced, not compiler-enforced" gap the review flagged; review discipline erodes over a multi-year, multi-session project, which is the whole premise this document series exists to guard against.
- **Split `Features/` into its own package** *(chosen)*.
- **Leave the "compiler-enforced" claim as-is, since SPM does enforce cross-package boundaries.** Rejected as incomplete — SPM enforces cross-*package* boundaries but not system-framework imports *within* a package (nothing stops `import SwiftData` from compiling inside an `ACCore` file); stating "compiler-enforced" without that caveat is a claim the architecture doesn't actually back up.

**Reason for Choice:** Making `ACFeatures` a real package with a restricted `Package.swift` dependency list turns "ViewModels can't reach `ACAudioKit`/`ACExport`/`ACPersistence`" into a genuine compile error instead of a code-review miss — a real, load-bearing guarantee where one was previously only claimed. This was the right call to make immediately, before any Feature code exists — cheap now, expensive as a retrofit once 10+ milestones' worth of Views already assume app-target placement.

**Consequences:** Rules out Feature Views/ViewModels ever depending on a Data-layer package or `DependencyContainer` directly (`CLAUDE.md`, "Dependency Injection Pattern"). Does **not** fully rule out raw `import SwiftData`/`AVFoundation` inside an `ACFeatures` file — SPM genuinely cannot gate that regardless of package layout (`CLAUDE.md`, "Package Dependency Graph" limitation note). That residual gap is what `Scripts/check-import-boundaries.sh` (see the CI entry, below) exists to close mechanically, rather than leaving it convention-only forever.

**Full detail:** `CLAUDE.md` (Package Dependency Graph, Dependency Injection Pattern, Folder/Package Structure).

---

## 2026-08-08 — Views never use `@Query`; `ProjectRepository` exposes a live `AsyncStream` instead

**Decision:** Views never import `SwiftData` and never use `@Query`. `ProjectRepository` exposes a live-observation API (`observeAll() -> AsyncStream<[Project]>` or equivalent) alongside one-shot CRUD; a ViewModel subscribes via a wrapping Use Case and republishes into an `@Observable` property the View binds to.

**Context:** An earlier draft of `CLAUDE.md` contained a direct, internal contradiction: one section said "Views never talk to Repositories or Use Cases directly — only to their ViewModel," while the "Single Source of Truth" section said list views "should read live via `@Query` where practical." `@Query` binds directly to `@Model` (SwiftData) entity types — using it from a View means that View depends on a Data-layer persistence-schema type directly, which the first rule explicitly forbids. The two statements couldn't both hold.

**Alternatives Considered:**
- **Keep `@Query`, drop the "Views never talk to Repositories" rule for list views as a carved-out exception.** Rejected — this reopens exactly the boundary `ACFeatures`'s package split (see above) was built to close; a View importing `SwiftData` is a Data-layer dependency by definition, regardless of how convenient `@Query`'s live-update behavior is.
- **Repository-owned `AsyncStream` of domain models** *(chosen)*.

**Reason for Choice:** This keeps the live-update behavior `@Query` was being reached for (no manual refresh needed after create/delete) while keeping the dependency direction intact: `ACCore` still never imports `ACPersistence`, and a View only ever sees domain models via its ViewModel, never a SwiftData entity type. The mechanism SwiftData-sourced data reaches a screen through is the Repository *protocol* (owned by `ACCore`, implemented by `ACPersistence`) being injected — not a hard import.

**Consequences:** Every mutating `ProjectRepository` method must republish the fresh result into the shared stream — a repository implementation that forgets this silently breaks live-updating UI. Establishes the pattern for any future list-style live-updating view: wrap the stream in a small Use Case (e.g. `ObserveProjectsUseCase`), never reach for `@Query` as a shortcut.

**Full detail:** `CLAUDE.md`, "Single Source of Truth."

---

## 2026-08-08 — Support drop-frame timecode from v1, not deferred

**Decision:** `TimecodeFrameRate` distinguishes `.fps29_97NonDrop` and `.fps29_97Drop` as of the first implementation of `Timecode`, with real SMPTE drop-frame arithmetic (not a stub), rather than shipping non-drop-only and adding drop-frame later.

**Context:** An earlier revision of `SPEC.md` §4.9 explicitly deferred drop-frame as an out-of-scope "known gap" for v1, reasoning from `CLAUDE.md` rule 7 (no premature abstraction). `Timecode`/`TimecodeFrameRate` are foundational value types that `Cue.startTimecode`, `EmbeddedMarker.position`, and the entire editor UI's position-display logic depend on directly.

**Alternatives Considered:**
- **Ship non-drop-only, add drop-frame later if a real production needs it** *(the original plan)*. Rejected on reconsideration — cue sheets built from NTSC-derived material (29.97fps) are a realistic, known case for this app's actual domain, not a speculative one; rule 7 exists to prevent generalizing for a use case that *might never arrive*, and this one isn't that.
- **Build both modes now** *(chosen)*.

**Reason for Choice:** The retrofit cost is asymmetric in a way rule 7's usual reasoning doesn't capture: adding a second timecode "mode" after dozens of call sites already assume non-drop-only formatting math is a much larger, more error-prone change than getting the enum shape and conversion algorithm right once, before anything depends on it. This is the inverse of rule 7's typical case, not an exception to it.

**Consequences:** Rules out a future migration/schema change to `TimecodeFrameRate` solely to add drop-frame support once real cue data already references the non-drop-only version. Drop-frame arithmetic (the every-10th-minute exception, the classic bug in naive implementations) is implemented and verified now: 18 tests including a round-trip sweep across a 3-hour-equivalent frame range, `Packages/ACCore/Tests/ACCoreTests/TimecodeTests.swift`.

**Full detail:** `SPEC.md` §4.9. Implementation: `Packages/ACCore/Sources/ACCore/Models/{Timecode,TimecodeFrameRate}.swift`.

---

## 2026-08-08 — Waveform data: bounded overview + on-demand detail, not a full mip-map

**Decision:** `WaveformPeaks` (`ACCore`) is a fixed-resolution (4096-bucket), mono, persisted summary of the whole file, generated once at import. Zoomed-in detail views compute peaks on demand for just the visible range, uncached. No multi-resolution mip-map pyramid is built.

**Context:** `ACDesignSystem/Components/WaveformView` was named in `CLAUDE.md`'s folder structure from the project's very first commit, but no data model or generation pipeline for it existed anywhere — a real, structural gap between what the architecture named and what it actually specified.

**Alternatives Considered:**
- **A raw/downsampled sample buffer added to `AudioAsset`.** Rejected outright — `AudioAsset` has an explicit invariant (never holds raw or downsampled sample data) established specifically to keep it a small, always-in-memory-safe metadata type regardless of source file size; adding waveform data there would break that invariant for every consumer of `AudioAsset`, not just the ones that need waveform display.
- **A full multi-resolution mip-map**, as some professional DAWs build. Rejected as more machinery than this app's actual workflow needs — AutoCue is for confirming/adjusting cue boundaries, not sample-accurate waveform editing.
- **Fixed bounded overview + uncached on-demand detail** *(chosen)*.

**Reason for Choice:** A fixed bucket count (4096) keeps the persisted overview's memory cost constant (~32KB) regardless of whether the source file is 3 minutes or 3 hours — this is what lets `WaveformPeaks` exist as a plain, always-safe `ACCore` value type. The two-tier design (bounded overview, cheap uncached on-demand detail via the existing streaming reader) covers the real editing workflow without the added maintenance surface of a resolution pyramid built for a use case (sample-accurate waveform editing) this app doesn't have.

**Consequences:** `WaveformPeaks` lives as a sibling field on `Project`, never folded into `AudioAsset`. Mono mixdown only in v1 — no per-channel/stereo dual-trace representation, flagged as a real, plausible future enhancement, not designed here. `GenerateWaveformDetailUseCase` results are never cached across zoom interactions — deliberate, since the cost against a bounded time range is already negligible; revisit only if a real performance problem shows up, not preemptively.

**Full detail:** `SPEC.md` §4.15; consumption pattern: `CLAUDE.md`, Design System section (`WaveformDisplayData` adapter type).

---

## 2026-08-08 — Single progress/cancellation contract: `AsyncThrowingStream<OperationProgress<T>, Error>`, not Foundation `Progress`

**Decision:** Every long-running operation (WAV import, waveform generation, cue analysis, PDF/XLSX export) reports progress through one shared contract — `AsyncThrowingStream<OperationProgress<T>, Error>`, where `OperationProgress<T>` is `.progress(ProgressUpdate)` or `.completed(T)` — and cancellation is plain cooperative `Task` cancellation. Foundation's `Progress` class is not used anywhere in the app.

**Context:** `CLAUDE.md` previously referenced `AsyncStream` and Foundation's `Progress` side by side, in more than one section, as if they were interchangeable options for the same job. They aren't: `Progress` is a KVO-based Objective-C class with its own observation and cancellation model that doesn't compose with `async`/`await` — there's no way to `for await` over a `Progress`, and its cancellation tree is independent of Swift's structured-concurrency `Task` cancellation.

**Alternatives Considered:**
- **Foundation's `Progress`.** Rejected — its main real advantage is system-level UI integration (Dock icon, Finder progress, menu-bar activity), and nothing in `SPEC.md` currently asks for that; adopting it would mean carrying an incompatible concurrency model for a benefit the product doesn't use.
- **A bespoke progress enum/callback per operation, decided ad hoc per milestone.** Rejected — six different operations each inventing a slightly different shape is exactly the kind of drift `CONTRIBUTING.md` warns about, and provides no benefit over one shared contract.
- **`AsyncThrowingStream<OperationProgress<T>, Error>`, one contract for all six operations** *(chosen)*.

**Reason for Choice:** Native Swift Concurrency composes directly with everything else in this codebase (ViewModels are `@MainActor`, background work is `async`), and picking one contract before any of the six operations that need it are built prevents six independent inventions of the same idea.

**Consequences:** Rules out any future milestone introducing `Progress`, a bespoke per-operation progress enum, or a custom cancellation-token type. If system-level UI integration is ever genuinely wanted, `Progress` can be layered on top of the stream-based contract later without changing the contract itself — this decision doesn't foreclose that, it just declines to build it now for a need that doesn't exist yet.

**Full detail:** `CLAUDE.md`, "Long-Running Operations: Progress & Cancellation." Types: `SPEC.md` §4.17.

---

## 2026-08-08 — `libxlsxwriter` validated with a real spike, ahead of its originally-scheduled position

**Decision:** `ACExport` depends on `libxlsxwriter` as a normal remote SPM package (its own upstream `Package.swift`, pinned `from: "1.2.4"`). This dependency decision has been verified with a real, runnable smoke test — including genuine kernel-enforced App Sandbox verification — rather than left as an untested assumption inherited from `CLAUDE.md` rule 4 until the roadmap position that originally covered it.

**Context:** `CLAUDE.md` rule 4 requires checking App Sandbox compatibility, static-linkability, and maintenance status before adopting a third-party dependency. This was stated as a rule from the project's first commit but not actually exercised until deep into the original 34-milestone plan — 27 milestones of downstream export work would have been built assuming it holds, before it was ever compiled even once. That's backwards risk-ordering for the one third-party native dependency in the whole stack.

**Alternatives Considered:**
- **Trust the choice on paper, validate it when the roadmap reaches it.** Rejected — this is the exact pattern rule 4 exists to prevent, just deferred by roadmap position rather than skipped outright.
- **Validate immediately, ahead of schedule** *(chosen)*.

**Reason for Choice:** A real spike (`XLSXFeasibilitySpike` + `XLSXFeasibilitySpikeTests`) costs little and resolves the dependency question completely before anything downstream depends on the answer. Verified: builds and links as an SPM C target (system `zlib` only), targets macOS 14 cleanly, produces a genuine ZIP/OOXML workbook with correct cell contents.

**App Sandbox verification, specifically:** an initial `sandbox-exec`-based attempt was correctly reported as inconclusive rather than a pass — the tool doesn't function at all in the execution environment used (confirmed against a trivial control case, `/bin/echo`, which failed identically). That was superseded by a real test: the spike binary packaged into a minimal `.app` bundle, ad-hoc code-signed with the actual `com.apple.security.app-sandbox` entitlement, and run directly. A write to an unauthorized location (`~/Desktop`) was genuinely blocked by the kernel (`Operation not permitted`, surfaced as a normal error, not a crash); a write inside the app's own sandbox container succeeded with correct output.

**Consequences:** Rules out treating "we chose `libxlsxwriter` under rule 4" as sufficient justification without ever having compiled it, and rules out treating the inconclusive `sandbox-exec` attempt as evidence either way. **Residual gap, narrower than general sandbox compatibility:** the real app's `NSSavePanel`-granted write flow (dynamic, Powerbox-mediated access to a user-chosen destination) wasn't tested — only the baseline container-write case was. This is `ROADMAP.md` D15/T15.2's job, once the real app target and final entitlements exist — a small, low-risk confirmation, not a reopening of this decision.

**Full detail:** `CLAUDE.md`, "Export Architecture (PDF & XLSX)." Spike: `Packages/ACExport/Sources/ACExport/Spike/XLSXFeasibilitySpike.swift`; tests: `Packages/ACExport/Tests/ACExportTests/XLSXFeasibilitySpikeTests.swift`.

---

## 2026-08-08 — Minimum deployment target: macOS 14.0 (Sonoma)

**Decision:** AutoCue targets macOS 14.0 as its minimum supported version, pinned explicitly in every package's `Package.swift` and (once it exists) the App target.

**Context:** `@Observable` and `SwiftData` — both already-committed architectural choices, not proposals — require macOS 14+. No document ever actually stated a minimum deployment target; it was only ever implied by those two dependencies, which meant nothing enforced it and a stray newer-OS-only API could have been introduced without anyone noticing it silently raised the floor.

**Alternatives Considered:**
- **Target a newer macOS version** (e.g. the current release at time of writing) for access to newer APIs. Rejected — nothing in the current feature scope needs anything newer than macOS 14 offers, and a lower minimum means more of AutoCue's actual user base (video/audio post-production professionals, who don't always run the newest OS on a production machine) can run the app.
- **Leave it unstated/implicit**, as before. Rejected — this is exactly the kind of undocumented assumption that erodes over a multi-year, multi-session project.
- **macOS 14.0, the floor already required by `@Observable`/`SwiftData`** *(chosen)*.

**Reason for Choice:** macOS 14.0 isn't really a new choice being made here so much as the floor already implied by decisions already locked in — this decision's job is to make that floor explicit and enforced, not to pick a version for its own sake.

**Consequences:** Raising the floor later is cheap and reversible (loosen an availability check) the moment a real newer-OS-only API is needed. Lowering it is not possible without dropping `@Observable` or `SwiftData`, which would be a much larger reversal than this document anticipates.

**Full detail:** `CLAUDE.md`, "Deployment Target"; `SPEC.md` §0.

---

## 2026-08-08 — Navigation Model: three always-visible tabs (Setup / Cue Sheet / Review & Export), not a sheet-based flow

**Decision:** Each Project window shows exactly three co-equal, always-accessible navigation destinations — **Setup**, **Cue Sheet**, and **Review & Export** — in a 2-column `NavigationSplitView`. None is ever presented as a modal sheet. `Settings` is entirely outside this hierarchy, via SwiftUI's standard `Settings` scene.

**Context:** The original product brief specifies three tabs, always visible and accessible at any time, like browser tabs. `ROADMAP.md`'s original milestone plan (M11) only ever described a 2-column sidebar+detail shell with no explicit resolution of what the "more than two screens per project" (Setup, Cues, Review, Export) actually meant for navigation depth.

**Alternatives Considered:**
- **Four separate tabs** (Setup, Cue Sheet, Review, Export as independent destinations). Not pursued — the brief specifies three, and Export's readiness is derived from Review's validation state, so treating them as fully independent destinations doesn't reflect their actual relationship.
- **Export as a modal sheet triggered from Review**, reasoning that export is "a triggered action with a result," not a place to navigate to and stay. **This was actually built at one point**, then reversed — it directly contradicted the brief's explicit "three tabs, always visible" requirement, which was the actual, binding product specification and should have been checked against before this alternative was chosen.
- **Three tabs, Review and Export combined into one persistent destination** *(chosen, and what the brief specified from the start)*.

**Reason for Choice:** Matches the original product brief exactly. Independently, combining Review and Export is also the architecturally cleaner choice on its own merits: export readiness is *derived from* validation state (`Settings.shareValidationStrictness` gates export on the same issues Review surfaces), so the two were never fully independent concerns — one `ReviewAndExportViewModel` avoids two ViewModels coordinating shared state across a presentation boundary.

**Consequences:** Rules out any future work reintroducing a `.sheet()`-presented export flow, or treating Export as reachable only from within Review rather than as its own always-visible tab. `DependencyContainer.makeReviewAndExportViewModel(for:)` replaces what would otherwise have been two separate factory methods.

**Full detail:** `CLAUDE.md`, "Navigation Model." Affected: `ROADMAP.md` D11 (T11.1, T11.5).

---

## 2026-08-08 — Document & Window Model: multi-window (`WindowGroup(for: Project.ID.self)`), not single-window

**Decision:** AutoCue is multi-window: a singleton Library scene for browsing/creating/opening Projects, plus a `WindowGroup(for: Project.ID.self)` scene allowing any number of Project windows open simultaneously, each independently editing one `Project`. Duplicate opens of the same `Project` are prevented by an explicit app-wide `OpenProjectWindowRegistry` (focus the existing window instead of opening a second one). `ProjectRepositoryImpl` serializes writes per-`Project.ID`, not behind a single app-wide lock.

**Context:** AutoCue is a single-composer desktop tool — one person building one cue sheet at a time is the normal case — which made single-window a real, defensible option, not an obviously wrong one.

**Alternatives Considered:**
- **Single window, single active Project at a time.** **This was the original decision**, reasoned from "fewer, well-separated moving parts": a single window eliminates the same-project-open-twice and cross-window-save-race problems *by construction*, with no coordination logic needed, and was explicit about the resulting limitation (no side-by-side comparison of two Projects) rather than silently overlooking it. Reversed — not because this reasoning was wrong at the time, but because of an explicit product requirement discovered afterward: the ability to compare/reference two Projects side by side in separate windows, which single-window structurally precludes.
- **A literal `DocumentGroup`** (file-backed documents, `FileDocument`/`ReferenceFileDocument`). Considered when reversing single-window, and rejected — `DocumentGroup` presumes each document is a file the system's Open/Save panels manage directly, which doesn't match AutoCue's actual persistence model: `Project`s are rows in one shared SwiftData store behind `ProjectRepository`, an already-validated decision this reversal does not reopen. Adopting `DocumentGroup` would have meant either abandoning that persistence model or fighting the framework with a synthetic `FileDocument` that doesn't represent real storage.
- **`WindowGroup(for: Project.ID.self)`, multi-window over app-managed (non-file) data** *(chosen)*.

**Reason for Choice:** `WindowGroup(for: Project.ID.self)` gives the same user-facing outcome multi-window `DocumentGroup` apps offer (multiple windows, one data item each) without requiring a file-per-project persistence model this app doesn't have. Reversing single-window meant its two "solved by construction" problems had to be solved explicitly instead: same-project-open-twice is now prevented by `OpenProjectWindowRegistry`; cross-window save races are now prevented by scoping `ProjectRepositoryImpl`'s write serialization per-`Project.ID` rather than relying on there only ever being one Project loaded.

**Consequences:** Rules out a future milestone reintroducing a single global `AppState`/`selectedProjectID`, or a save-serialization scheme that isn't scoped per-`Project.ID`. `AppState` is now constructed once per Project window (holding only `selectedSection`), not once per app. The original single-window decision was written into `CLAUDE.md` directly at the time but never logged in this file — an omission corrected retroactively here, recording both the original reasoning and its reversal together rather than only the final state.

**Full detail:** `CLAUDE.md`, "Document & Window Model." Affected: `ROADMAP.md` D6.

---

## 2026-08-08 — CI, lint, and Definition-of-Done process introduced at D1, and the roadmap restructured into Deliverables

**Decision:** CI (`.github/workflows/ci.yml`), `SwiftFormat`/`SwiftLint` config, and two architecture-boundary scripts (`Scripts/check-import-boundaries.sh`, `Scripts/check-color-literals.sh`) are introduced at `ROADMAP.md` Deliverable D1 — the very first buildable state — rather than at the roadmap position that originally covered this (deep into the 34-milestone plan, alongside XLSX validation). The roadmap itself is restructured from 34 flat milestones into 17 Deliverables with nested Tasks, each carrying Goal/Dependencies/Tasks/Acceptance Criteria/Testing Requirements/Documentation Requirements/Suggested Commit Boundary. `docs/DefinitionOfDone.md` and `docs/REVIEW.md` are added as the checklist and running log those fields point back to.

**Context:** Every architecture rule that mattered in this project (`ACCore` importing nothing beyond Foundation, no raw color literals outside the design system, no force-unwraps) was, before this decision, checked manually exactly once — as the acceptance criterion of the milestone that introduced it — and never re-verified again. Nothing prevented a later, unrelated milestone from silently reintroducing a violation. Separately, the flat 34-milestone list didn't sequence architectural prerequisites (CI, the XLSX feasibility question) strictly before the feature work that implicitly depended on them holding.

**Alternatives Considered:**
- **Leave enforcement manual, add CI when the roadmap reaches its originally-planned position.** Rejected — this is the same backwards risk-ordering the `libxlsxwriter` entry (above) already identified and corrected for that one dependency; the same reasoning applies to every architecture rule, not just that one.
- **Keep the flat 34-milestone structure, just reorder items 15/scoped-CI earlier within it.** Rejected — some milestones (Review, Export) only make sense built as a unit once the Navigation Model decision (above) combined them; a flat list of 34 independent-looking items invites exactly that kind of mismatch again.
- **Introduce CI/lint at D1, restructure into Deliverables with nested Tasks** *(chosen)*.

**Reason for Choice:** Every later Deliverable inherits automated enforcement from day one instead of trusting 27+ Deliverables' worth of unverified assumptions — the same logic already applied to the XLSX dependency, generalized to the whole architecture. Grouping related Tasks into Deliverables (e.g., Review + Export into D11) makes the unit-that-must-be-finished-together explicit in the planning document itself, not just discovered mid-implementation the way the sheet-vs-tab mistake was.

**Consequences:** `Scripts/check-import-boundaries.sh` and `Scripts/check-color-literals.sh` are a fixed set of forbidden-import/pattern checks, not a general-purpose architecture linter — a new rule added to `CLAUDE.md` doesn't automatically get CI coverage; the scripts need updating in the same change (`CLAUDE.md`'s "Package Dependency Graph" limitation note says this explicitly). The CI workflow's pinned Xcode version (`15.4`, for GitHub-hosted `macos-14` runners) was written without access to a live runner to confirm against — flagged in the workflow file itself and in `docs/REVIEW.md`'s seed entry as something to confirm on first real run, not asserted as verified. **Update: it was run for real and did fail** — see the entry below for the actual outcome and fix, rather than treating this flag as still open.

**Full detail:** `CONTRIBUTING.md` §8; `docs/DefinitionOfDone.md`; `docs/REVIEW.md`; `ROADMAP.md` (full restructuring, D1 specifically for the CI/lint work itself).

---

## 2026-08-08 — CI's first real run failed on a Swift tools-version mismatch; fixed by lowering the manifest version, not the Xcode pin

**Decision:** `Packages/ACCore/Package.swift` and `Packages/ACExport/Package.swift` declare `// swift-tools-version: 5.10`, not `6.1`. CI's pinned Xcode version (`15.4`) is kept as-is.

**Context:** The CI workflow's Xcode pin was explicitly flagged, at the point it was written, as unverified against a live GitHub-hosted runner (see the CI/lint entry above). The first real push after it was added genuinely failed: both `swift test — ACCore` and `swift test — ACExport` errored identically — `package 'X' is using Swift tools version 6.1.0 but the installed version is 5.10.0` — diagnosed directly from `gh run view --log-failed`, not guessed at. GitHub's `macos-14` runner image ships Xcode 15.3/15.4 (default) and 16.1/16.2 (confirmed via the public `actions/runner-images` manifest) — none of which bundle a Swift 6.1 toolchain (that shipped with Xcode 16.3, not available on this image at all).

**Alternatives Considered:**
- **Bump the CI Xcode pin to 16.2** (the newest available on this runner image). Rejected — 16.2 ships Swift 6.0.x, still short of a manifest declared at 6.1; would have "fixed" the symptom while leaving the actual mismatch (declared tools-version higher than anything the runner offers) unresolved for the next dependency bump.
- **Switch `runs-on` to a newer runner image (`macos-15`) that might carry Xcode 16.3+.** Rejected without even confirming — moving the runner image is a bigger, less-targeted change than the actual problem calls for, and would abandon the deliberate choice (made when this workflow was written) to validate against `CLAUDE.md`'s documented minimum-supported Xcode version (15+), not whatever's newest.
- **Lower `swift-tools-version` in both `Package.swift` files to `5.10`** *(chosen)* — matches Xcode 15.4's actual installed Swift version exactly, and neither package's manifest uses any language/manifest feature that isn't available at 5.10 (both are plain `Package`/`.target`/`.testTarget`/`.macOS(.v14)` declarations, nothing 6.x-specific).

**Reason for Choice:** `6.1` was never a deliberate requirement — it was simply whatever `swift --version` reported in the local sandbox environment these two packages were originally built in, carried into the manifest without being chosen for a reason. Lowering it doesn't lose anything and directly fixes root cause: CI now validates against the same toolchain floor `CLAUDE.md` already documents as this project's actual minimum (Xcode 15+), rather than requiring CI to chase whatever Xcode version happens to be locally installed on a given contributor's machine.

**Consequences:** Both packages rebuilt and re-tested locally after the change (18 + 4 tests, all passing) before pushing. **Correction to this entry's original wording:** it previously claimed this fix was "confirmed against the actual failing CI run" — it wasn't, at the time of writing; that push hadn't been watched to completion yet, and local success (Swift 6.1.2) turned out not to guarantee CI success (Swift 5.10) — see the follow-up entry immediately below for what local verification actually missed, and why. Establishes the going-forward rule: `Package.swift` files in this project should declare the lowest `swift-tools-version` that's actually sufficient, not whatever the authoring environment happened to have installed — a manifest requiring a newer tools-version than CI's pinned Xcode ships is exactly this failure mode again.

**Full detail:** `.github/workflows/ci.yml`; `Packages/ACCore/Package.swift`; `Packages/ACExport/Package.swift`.

---

## 2026-08-08 — Follow-up: the tools-version fix above was necessary but incomplete; `.swiftformat`'s `--swiftversion` was the same mistake in a second place

**Decision:** `.swiftformat` declares `--swiftversion 5.10`, not `6.1`. No separate `--trailing-commas` override is needed — lowering `--swiftversion` alone correctly makes SwiftFormat stop adding trailing commas to function-call argument lists (a syntax Swift 5.10's compiler cannot parse at all, confirmed by direct local test — see below), while still applying them to genuine collection literals.

**Context:** The entry above lowered `swift-tools-version` and was pushed believing it fixed CI. It was watched through to completion this time, and CI failed again — a *different* error (`unexpected ',' separator` on lines ending `path: "Sources/ACExport",`), not the tools-version mismatch from before. `.swiftformat` had separately declared `--swiftversion 6.1` — the exact same category of mistake as the first entry (copied from the local authoring environment, never cross-checked against the documented Xcode 15.4/Swift 5.10 CI floor) — which caused SwiftFormat to add trailing commas to function-call argument lists, a real Swift language feature that a direct local test (`swiftc -swift-version 5 test.swift`, compiled with the same Xcode toolchain used elsewhere in this project) confirmed compiles fine under Swift 6.1.2 even in `-swift-version 5` compatibility mode, but is absent entirely from the Swift 5.10 compiler binary itself — a compiler-*version* gap, not a language-*mode* gap, which is why local testing (Swift 6.1.2) couldn't have caught it no matter what compatibility flags were passed.

**Alternatives Considered:**
- **Add `--trailing-commas collections-only`** to keep `--swiftversion` at `6.1` while suppressing just the problematic case. Rejected once tested — unnecessary: lowering `--swiftversion` to `5.10` alone already produces exactly this behavior (confirmed by running `swiftformat --lint` before and after the change), because SwiftFormat already knows trailing-comma-in-calls requires a newer Swift version than 5.10 and gates it internally. Keeping `--swiftversion` at a value that doesn't match the project's real floor, plus a manual override to patch around the one symptom that got caught, would have left the setting itself still wrong and likely to cause a different, uncaught mismatch later.
- **Lower `--swiftversion` to `5.10`, matching the tools-version fix above** *(chosen)* — the same root-cause fix applied to the second place the same mistake was made.

**Reason for Choice:** `--swiftversion` is SwiftFormat's own declaration of the minimum Swift version its output needs to compile under — it should have matched the project's actual documented floor from the moment `.swiftformat` was written, for exactly the same reason `swift-tools-version` should have. Fixing the setting itself, rather than adding a narrower override for the one symptom CI happened to catch, avoids leaving the same wrong assumption in place to cause a third, still-undiscovered failure mode later.

**Consequences:** This time actually verified against a real CI run before considering it closed, not just asserted: pushed, then `gh run watch` was run to completion and all three jobs (both `swift test` matrix legs plus the lint job) came back green. Both packages rebuilt and retested locally again after this second fix (still 18 + 4 passing). Going-forward rule, generalized from the narrower one in the entry above: **every SwiftFormat/SwiftLint/Package.swift setting that declares a Swift/tools version in this project must match the actual CI-pinned Xcode's toolchain (currently Xcode 15.4 → Swift 5.10), not whatever version happens to be installed in whatever environment is editing the file at the time** — this is now the second time the same category of mistake caused a real, avoidable CI failure.

**Full detail:** `.swiftformat`; `Packages/ACCore/Package.swift`; `Packages/ACExport/Package.swift`; `Packages/ACCore/Sources/ACCore/Models/Timecode.swift`.

---

## 2026-08-08 — Cue deletion: immediate save, no confirmation dialog, standard ⌘Z undo

**Decision:** `UpdateCueUseCase`'s add/delete/reorder operations write through to `ProjectRepository` immediately (never debounced) — only continuous field-level edits within a `Cue` remain debounced. Deleting a `Cue` requires no confirmation dialog, regardless of how many `CueRightHolder` entries are attached, but is undoable via standard ⌘Z through the environment `UndoManager`.

**Context:** `UpdateCueUseCase`'s delete path was already specified as a data operation (`ROADMAP.md` D10/T10.1), but nothing specified its save timing or its interaction contract. `CLAUDE.md`'s blanket "autosave is debounced" statement, read literally, would have applied to deletion too — which would have meant a deleted row could remain persisted for up to the debounce interval, directly undermining "Review & Export reflects the current cue list with no manual refresh."

**Alternatives Considered:**
- **Debounce deletion the same as field edits.** Rejected — debouncing exists to avoid a save-per-keystroke storm during continuous typing; a delete is a discrete, complete action with nothing further to type, so the same reasoning doesn't apply, and debouncing it actively breaks the "no manual refresh" requirement.
- **Immediate save for structural mutations (add/delete/reorder), debounced for field edits** *(chosen)*.
- **Require a confirmation dialog before deleting a `Cue`, especially one with multiple attached `CueRightHolder` entries.** Rejected — a confirmation dialog is the wrong safety mechanism for a common, easily-reversible action; Apple's HIG stance (no confirmation where a real, discoverable undo path exists) applies directly, and layering a dialog on top of undo would be redundant friction, not additional safety. The right-holder count doesn't change this: deletion is atomic (a `Cue` and its `[CueRightHolder]` entries are removed together), so there's no scenario where "how many right-holders" changes the actual risk.
- **No undo at all, rely on the confirmation dialog instead.** Rejected together with the dialog itself — this would have been strictly worse: no safety net *and* the friction of a dialog.
- **Standard ⌘Z via the environment `UndoManager`** *(chosen)*, rather than a bespoke undo stack — no reason to build a custom mechanism when the platform-standard one exists and is what users already expect.

**Reason for Choice:** Immediate save is what actually makes "no manual refresh" true rather than aspirational — verified concretely by a specified cross-ViewModel test (`ROADMAP.md` D11's acceptance criteria) rather than left as an architectural assertion. No-confirmation-plus-real-undo is the standard, well-understood macOS pattern for this exact situation, and is genuinely safer in practice than a confirmation dialog most users click through without reading.

**Consequences:** `CLAUDE.md`'s "autosave is debounced" statement (Performance Considerations, Single Source of Truth) was corrected in the same change to state the field-edit-vs-structural-mutation distinction explicitly — leaving the old blanket statement standing would have directly contradicted this decision. Rules out any future Deliverable reintroducing a confirmation dialog for cue deletion, or debouncing a structural mutation.

**Full detail:** `SPEC.md` §4.18. Affected: `CLAUDE.md` ("Performance Considerations," "Single Source of Truth"); `ROADMAP.md` D10 (T10.1, T10.2), D11 (cross-ViewModel propagation test).

---

## 2026-08-08 — Manual cue correction happens at the `Cue` level; `AudioAsset`/`EmbeddedMarker` stay immutable

**Decision:** Correcting a misjudged cue detection — adding a missed cue, removing a wrong one, repositioning a boundary — is entirely `Cue`-level editing via the existing `UpdateCueUseCase`. `AudioAsset.embeddedMarkers` is never edited. Editing any field of a `Cue` reclassifies its `source` to `.manual`, which is what keeps it protected on a subsequent detection re-run.

**Context:** `AudioAsset.embeddedMarkers` had no editing path, `AudioAsset` is documented as an immutable derived snapshot (established as a firm invariant from the project's first architecture-correction pass), and nothing let a user correct a detection `DetectCuesUseCase` got wrong — a real functionality gap found by direct review of `SPEC.md`/`ROADMAP.md` against each other, not a hypothetical.

**Alternatives Considered:**
- **Make `EmbeddedMarker` editable, and treat that as the correction mechanism.** Rejected — `EmbeddedMarker` is a factual record of what's literally embedded in the source WAV file's `cue`/`labl`/`ltxt` chunks, analogous to EXIF data; editing it would misrepresent the source file's actual content, and doing so would also require reopening the `AudioAsset`-is-immutable invariant this project already fought to establish and preserve.
- **Introduce a new, separate "marker correction" concept distinct from `Cue` editing.** Rejected — by the time a user would ever want to correct something, `DetectCuesUseCase` has already merged embedded markers and silence detection into `Cue` entities (per the existing "Combining with embedded markers" rule); there is no separate "marker" left to correct independently, and building one anyway would duplicate `Cue`'s already-existing edit/delete/add capability for no benefit — exactly what `CLAUDE.md` rule 7 (no premature abstraction) argues against.
- **Correction as `Cue`-level editing, reusing the existing `UpdateCueUseCase`** *(chosen)*.
- **For re-run protection: add a new state (e.g. a `hasBeenManuallyAdjusted` flag, or a fourth `source` case) to distinguish "detected, then human-confirmed" from "detected, untouched."** Rejected as unneeded precision — reclassifying to the existing `.manual` case on any edit reuses the re-run protection rule that already exists for that case, with no new state, no new rule, and no meaningfully lost information for what the UI actually needs to show.
- **Reclassify `source` to `.manual` on any edit, regardless of field or prior source** *(chosen)*.

**Reason for Choice:** `Cue` is already the app's editable interpretation of a work's usage, built from raw detection data — "correcting a detection" and "editing a `Cue`" are the same action once that merge has happened, so no new architectural surface is needed, only wiring the existing `UpdateCueUseCase` into three concrete entry points (add via `CueTableView`, remove via the same delete control as ordinary deletion, reposition via a direct timecode field or a new interactive `WaveformView` drag mode). The blanket reclassification-on-edit rule is the minimal fix that closes the actual gap (a `.detectedFromAudio` cue silently losing a manual correction on re-run) without inventing new state.

**Consequences:** `WaveformView` — named in `CLAUDE.md`'s folder structure since the project's first commit but never actually scoped as buildable work anywhere in the roadmap — now has a real home: `ROADMAP.md` D9/T9.3, both its display mode (`SPEC.md` §4.15) and this interactive drag mode. Dragging a boundary adjusts only that one `Cue`'s fields, with no automatic ripple onto a neighboring cue — a deliberate scope limit, not an oversight, since `Cue`s aren't modeled as a contiguous timeline. Rules out ever mutating `AudioAsset.embeddedMarkers` post-import, and rules out a future Deliverable reintroducing a separate provenance-tracking state beyond the existing three-case `source` enum.

**Full detail:** `SPEC.md` §4.19 (and its cross-references in §4.3, §4.10, §4.11, §4.15). Affected: `ROADMAP.md` D9 (T9.2, T9.3), D10 (T10.1, T10.2).

---

## 2026-08-08 — D1's `Party` built with `UUID`-typed cases, not deferred to D2

**Decision:** `Party` (`ACCore/Models/Party.swift`) is implemented in `ROADMAP.md` D1/T1.4 as specified, with `case person(UUID)` / `case label(UUID)` rather than `case person(Person.ID)` / `case label(Label.ID)`.

**Context:** `SPEC.md` §4.5 defines `Party`'s cases against `Person.ID`/`Label.ID`, but `Person`/`Label` aren't built until `ROADMAP.md` D2 (sequenced after D1). Taken literally, `Party` as specified can't compile until D2 lands, which looks like a real ordering conflict between T1.4's scope and D2's dependency position.

**Alternatives Considered:**
- **Move `Party` to D2, alongside `Person`/`Label`.** Rejected — unnecessary once traced through: `Person`/`Label` both declare `id: UUID` (`SPEC.md` §4.5's own field tables), so `Person.ID`/`Label.ID` resolve to the concrete type `UUID`. Swift doesn't preserve `Person.ID` as a distinct nominal type in a case's public signature — it resolves straight to whatever concrete type backs it. A case written today as `person(UUID)` is byte-for-byte identical, at the ABI/type-checking level, to what `person(Person.ID)` would be once `Person` exists.
- **Stub minimal `Person`/`Label` types in D1 just so `Party` can reference `.ID` literally.** Rejected outright — this is exactly the "half-built feature to come back to later" `CONTRIBUTING.md` §2 warns against, and would duplicate real D2 work for no benefit.
- **Build `Party` now with `UUID`-typed cases, documented as forward-compatible** *(chosen)*.

**Reason for Choice:** Zero rework once D2 lands — the case signatures are already exactly what they'd be if written against `Person.ID`/`Label.ID` directly, since both are `UUID` under the hood. Keeps D1/T1.4's scope as `ROADMAP.md` actually describes it, without a real conflict once the types are traced through.

**Consequences:** `Party.swift` carries a doc comment noting the cases are conceptually `Person.ID`/`Label.ID` (`SPEC.md` §4.5) once those types exist. No `SPEC.md`/`ROADMAP.md` correction needed for this specific point — flagged here so a future session doesn't "fix" this by prematurely stubbing `Person`/`Label` in `ACCore`, mistaking the literal `SPEC.md` wording for a real blocker.

**Full detail:** `SPEC.md` §4.5. Implementation: `Packages/ACCore/Sources/ACCore/Models/Party.swift`.

---

## 2026-08-08 — D1's Xcode project hand-authored, not generated by a third-party tool

**Decision:** `AutoCue.xcodeproj/project.pbxproj` and `AutoCue.xcworkspace/contents.xcworkspacedata` are hand-authored directly (no XcodeGen/Tuist), targeting `objectVersion = 56` / `compatibilityVersion = "Xcode 14.0"` for broad compatibility with CI's pinned Xcode 15.4, and validated with `plutil -lint` plus a checked-in shared scheme (`AutoCue.xcodeproj/xcshareddata/xcschemes/AutoCue.xcscheme`, required for `xcodebuild -scheme AutoCue` to resolve at all in CI, since user-specific schemes under `xcuserdata` are gitignored).

**Context:** D1 requires a real `xcodebuild -scheme AutoCue build` to succeed (`ROADMAP.md` D1 Acceptance Criteria), but the sandboxed environment this Deliverable was built in has no Xcode CLI tooling wired up by default (`xcode-select` points at Command Line Tools only). A full Xcode 26.3 install exists at `/Applications/Xcode.app`, invocable by full binary path without changing the global `xcode-select` setting — but a project authored/saved under it risks picking up a newer project-file format than Xcode 15.4 (CI's pin) can open.

**Alternatives Considered:**
- **Install XcodeGen via Homebrew, generate the project from a `project.yml` spec.** Considered — a well-tested generator, less hand-editing risk than raw `pbxproj`. Not pursued: adds a new dev-tooling dependency for a one-time scaffolding step, and still ultimately produces a project file whose format is tied to whatever Xcode version runs the generator — doesn't fully remove the format-drift risk, just moves who authors the raw file.
- **Scaffold only the SPM packages, leave Xcode project creation to manual GUI work.** Considered — zero project-file risk, but slower and defeats the point of automating D1.
- **Hand-author `pbxproj`, validate with `plutil -lint` + real `xcodebuild`** *(chosen)*.

**Reason for Choice:** No new tooling dependency; full control over `objectVersion`/`compatibilityVersion` to target the actual CI floor rather than whatever a generator run under Xcode 26.3 would default to.

**Consequences — a real, residual verification gap, stated plainly rather than over-claimed:** the local Xcode 26.3 install this Deliverable had access to turned out to be broken independent of anything in this project — `xcodebuild` fails to load `IDESimulatorFoundation` (missing `/Library/Developer/PrivateFrameworks/DVTDownloads.framework`) on every invocation, including `-list`, before ever reaching our project file. Fixing it requires `sudo xcodebuild -runFirstLaunch`, an interactive, password-prompting, admin-privileged step that can't be run from an unattended session. `plutil -lint` confirms `project.pbxproj` is syntactically valid property-list data, which is necessary but not sufficient — it does not confirm Xcode's project model actually parses the file's semantics (target graph, package references, build phases). Per this project's own established discipline (see the two `swift-tools-version`/`--swiftversion` CI-fix entries above — "verified locally" was asserted prematurely twice before, and both times the real CI run caught what local testing missed), this entry does **not** claim local `xcodebuild` verification succeeded — only that `plutil -lint` passed and that a real CI run against the Xcode-15.4-pinned runner is the actual bar D1 is verified against, same as always.

**Update — local verification subsequently completed:** the user ran `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch` in their own interactive terminal (this session couldn't run it — no TTY for the password prompt). After that, `xcodebuild -workspace AutoCue.xcworkspace -list` correctly resolved the full local package graph and listed all 7 schemes (6 packages + `AutoCue`), and both `xcodebuild ... -scheme AutoCue build` and `... test` genuinely succeeded — `AutoCue.app` links against all 6 local packages, and `AutoCueTests` ran and passed. The hand-authored `objectVersion = 56` / `compatibilityVersion = "Xcode 14.0"` project parsed correctly under Xcode 26.3.

**Update — real CI run confirmed green:** pushed as PR #1 (`d1-workspace-ci-lint-core-value-types` → `main`), watched to completion via `gh pr checks --watch`. All 9 jobs passed on the actual Xcode-15.4-pinned `macos-14` runner: the lint job, all 7 `swift test — <package>` legs, and `xcodebuild build/test — AutoCue` (51s) — the one this whole entry exists to be honest about not having pre-confirmed. The hand-authored `project.pbxproj` parses and builds identically under both Xcode 26.3 (local) and Xcode 15.4 (CI). This closes the residual gap the entries above deliberately left open rather than over-claiming.

**Update — D2 surfaced a second, narrower instance of the same root cause, now fixed system-wide:** `sudo xcodebuild -runFirstLaunch` (above) fixed `xcodebuild` itself, but plain `swift test`/`swift build` invoked from this sandboxed session still failed with `no such module 'XCTest'` — a different symptom of the same underlying gap, not a new one. `xcode-select -p` still pointed at the bare Command Line Tools (`/Library/Developer/CommandLineTools`), which don't carry `XCTest.framework` wired for SPM test targets; even invoking Xcode 26.3's own `swift` binary directly by full path didn't help, because SDK/framework resolution still goes through `xcode-select`'s active pointer, not the path of the binary being invoked. Prefixing commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` worked around it per-invocation and confirmed the new D2 code itself had zero compile errors (`XCTest.framework` genuinely exists at `/Applications/Xcode.app/Contents/SharedFrameworks/XCTest.framework` once that env var forces resolution to it) — but a per-invocation env var is a workaround, not a fix, and would have had to be rediscovered by the next session. The user fixed it properly at the system level instead: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, confirmed via `xcode-select -p`. **Re-verified after that fix, with plain `swift test` and no env var override:** all 7 packages pass — `ACCore` 99 tests (0 failures), `ACAudioKit`/`ACPersistence`/`ACDesignSystem`/`ACFeatures`/`ACTestSupport` 1 placeholder test each (0 failures), `ACExport` 4 tests (0 failures) — and `swiftlint lint --strict` across the whole repo (49 files) also now runs cleanly without the env var (it had been crashing on `sourcekitd` loading before `xcode-select` was corrected, same root cause). `CONTRIBUTING.md` isn't updated with this as a general setup step, since it's specific to this one sandboxed session's starting state, not something every contributor's machine would hit — flagged here instead, where the rest of this session's toolchain-wiring history already lives.

**Full detail:** `AutoCue.xcodeproj/project.pbxproj`; `.github/workflows/ci.yml`'s `xcodebuild-app` job.

---

## 2026-08-08 — `PostalAddress`/`Party` don't conform to `Identifiable`; `CLAUDE.md`'s conformance policy wording tightened to make this unambiguous

**Decision:** `PostalAddress` and `Party` (`ACCore/Models/`) conform to `Equatable, Sendable` only — no `Identifiable`, and no `id: UUID` added to either type to enable it. `CLAUDE.md`'s "Domain Model Value-Type Conformances" section is amended, in the same change, to state explicitly that the `Identifiable` rule is conditional on a type already having an `id` field, not an unconditional "every domain type must be `Identifiable`."

**Context:** Raised as a direct question before this Deliverable was approved: `CLAUDE.md`'s `Identifiable` bullet reads "required on every domain type with an `id` field" — conditional wording — but the surrounding prose lists concrete examples (`Project`, `Cue`, `Person`, …) without ever showing a type that's exempt, which left real room to misread it as "every domain type, always." `PostalAddress` (`street`/`postalCode`/`city`/`country`) and `Party` (a reference enum wrapping another type's `UUID`) both lack an `id` field in `SPEC.md`'s schema entirely — there's nothing to make identifiable in the first place.

**Alternatives Considered:**
- **Add `id: UUID` to `PostalAddress`/`Party` so they can conform.** Rejected — nothing in `SPEC.md` or `CLAUDE.md` ever needs to reference *a specific `PostalAddress` instance* or *a specific `Party` instance* independent of the field that holds it (unlike `Person`/`Label`, which are referenced *by id* from multiple places via `Party` itself). Adding an unused `id` field purely to satisfy a conformance would be rule 7's premature-abstraction problem applied to a protocol conformance instead of a feature.
- **Leave `CLAUDE.md`'s wording as-is, treat this as already correctly scoped.** Considered, since the literal text is technically already conditional — but the fact that this required stopping and checking at all (rather than being obviously correct on a first read) is itself evidence the wording was under-specified in practice, even if not wrong in theory. Rejected as insufficient on its own.
- **Tighten `CLAUDE.md`'s wording to state the conditional explicitly, with real examples of types that don't engage the rule** *(chosen, alongside not adding `id` to either type)*.

**Reason for Choice:** This isn't a new policy — `Timecode`/`MediaDuration` (already real, shipped, tested code from before this Deliverable) already follow exactly this reading: no `id` field, no `Identifiable`, built and merged without controversy. `PostalAddress`/`Party` are the same shape of type. What changed is only the documentation's precision, not the rule itself — making the existing rule harder to misread costs nothing and prevents the same question from being re-litigated by a future session that doesn't have this conversation's context.

**Consequences:** `CLAUDE.md`'s `Identifiable` bullet now names `Timecode`, `MediaDuration`, `PostalAddress`, `Party`, `ProgressUpdate`, `OperationProgress<T>`, and `AnalysisSettings` as the standing list of "no `id` field, no `Identifiable`, and that's correct" examples — a future domain type in the same shape (a pure value with no independent identity need) should look here first rather than re-deriving the reasoning. Rules out adding `id: UUID` to any of these types "just in case" without a specific, real, documented need per rule 7.

**Full detail:** `CLAUDE.md`, "Domain Model Value-Type Conformances." Implementation: `Packages/ACCore/Sources/ACCore/Models/{PostalAddress,Party}.swift`.

---

## 2026-08-08 — D1 claimed `MediaDuration` was shipped; it wasn't. Corrected at the start of D2, not silently patched in.

**Decision:** `MediaDuration` (`Packages/ACCore/Sources/ACCore/Models/MediaDuration.swift`) is implemented now, at the start of D2, as corrective work completing `ROADMAP.md` D1/T1.4's actual scope. `ROADMAP.md`'s D1 section is corrected in the same change to state plainly that this was missing at D1's close, rather than rewritten to look like it was always fine.

**Context:** D1/T1.4 and its own PR #1 commit message both asserted `MediaDuration`, `Timecode`, and `TimecodeFrameRate` were "already implemented and tested ahead of schedule." Only `Timecode`/`TimecodeFrameRate` were real. When D2 planning began, the source tree was checked directly against the claim (per this project's own established discipline — see the two `swift-tools-version`/`--swiftformat` entries above, where "verified locally" was asserted prematurely and the real check caught what was missed) — `grep`/`find` across `Packages/ACCore/Sources` and the whole repository turned up no `MediaDuration.swift`, no `struct MediaDuration` anywhere. D2's own scope (`Setup.productionRuntime`, `Setup.totalMusicRuntime`, `Cue.duration` — SPEC.md §4.2–§4.3) depends on it directly, so this was a real blocker, not a paperwork nit.

**Alternatives Considered:**
- **Silently add `MediaDuration` as part of D2's normal work, without correcting D1's record.** Rejected — this is exactly the kind of quiet history-rewriting this project's documentation discipline has consistently refused to do elsewhere (e.g. the CI-run entries above correct their own prior "verified" claims rather than editing them away). Leaving D1 saying "complete, MediaDuration included" when it demonstrably wasn't would mislead the next session reading `ROADMAP.md` at face value.
- **Build `MediaDuration` now, correct D1's status/history to admit the gap plainly** *(chosen)*.

**Reason for Choice:** The same transparency standard already applied to every other correction in this log (the tools-version fixes, the `pbxproj` verification-gap entry) — state what actually happened, including the parts that don't look clean, rather than editing the past to look tidier than it was.

**Consequences:** `ROADMAP.md` D1's Status note and T1.4 description now both flag this correction explicitly rather than reading as originally written. No retrofit cost beyond the corrective commit itself — `MediaDuration` had no dependents yet (D2 is its first real consumer), so this is caught at essentially the cheapest possible point, same reasoning as the `MediaDuration`-naming decision at the top of this log.

**Full detail:** `ROADMAP.md` D1 (Status, T1.4). Implementation: `Packages/ACCore/Sources/ACCore/Models/MediaDuration.swift`; `Packages/ACCore/Tests/ACCoreTests/MediaDurationTests.swift`.

---

## 2026-08-09 — D4: `WaveformPeaksEntity` stores two `[Float]` attributes, not a hand-packed `Data` blob — reversed after a real CI crash, not a local review

**Decision:** `WaveformPeaksEntity` (`ACPersistence`) persists `WaveformPeaks.buckets` as two parallel SwiftData `[Float]` attributes (`minValues`/`maxValues`, index-aligned), not a single manually byte-packed `Data` blob.

**Context:** D4's original design (proposed and approved before implementation) packed `[WaveformPeakBucket]` into one `Data` blob — `min`/`max` `Float` pairs written via `withUnsafeBytes(of:)` and read back via `data[offset..<offset+4].withUnsafeBytes { $0.load(as: Float.self) }` — specifically to avoid 4096 separate child `@Model` rows for a type whose whole reason for existing is a bounded ~32KB memory footprint (SPEC.md §4.15). This passed every local check: `swift test` (25 consecutive clean runs of the concurrency-sensitive suite, plus the full suite), `swiftformat --lint`, `swiftlint lint --strict`, both architecture scripts, and a full local `xcodebuild build`/`test`. It then genuinely failed on PR #4's real CI run, on the Xcode-15.4-pinned runner specifically: `swift test — ACPersistence` crashed with `signal 5` (SIGTRAP) partway through `ProjectRoundTripTests`, diagnosed directly from `gh run view --log-failed`, not guessed at. The crash was in `unpack`'s `load(as:)` call — that API has a strict alignment precondition, and a `Data` value fetched back out of SwiftData's persisted representation isn't guaranteed to satisfy it the way a freshly-built in-memory `Data` (the only kind exercised locally) happens to. The same fail-fast matrix strategy that surfaced this real failure also cancelled five sibling `swift test` matrix legs mid-run (including `ACFeatures`, a package this Deliverable never touched) — confirmed via `gh api .../jobs/<id>` showing `conclusion: "cancelled"` despite every one of that job's own steps reporting `"success"`; not a second real bug, just `fail-fast: true`'s normal effect on a matrix once one leg fails.

**Alternatives Considered:**
- **Patch the existing `Data`-blob design with `loadUnaligned(fromByteOffset:as:)`** (available since Swift 5.7/macOS 13, so within this project's macOS 14 floor) instead of `load(as:)`, keeping the hand-rolled packing scheme otherwise unchanged. Rejected — this would have fixed the one instance of the bug CI happened to catch, but not the underlying pattern (manual byte-level (de)serialization of a type crossing a persistence boundary) that produced it; the same class of mistake could recur the next time this code is touched.
- **Two parallel `[Float]` attributes, no manual byte packing** *(chosen)*.

**Reason for Choice:** A `[Float]` SwiftData attribute is still one flat column per entity, not a per-bucket relationship row — the actual property this design needs (bounded footprint, no 4096-row overhead) holds exactly as well as the `Data`-blob version did, without reinventing serialization SwiftData already does correctly. Letting SwiftData own that encoding removes the whole class of bug (alignment, endianness, cross-version `Data`-representation assumptions), not just the one instance of it a real CI run happened to expose. This is the same standing lesson this log has recorded multiple times before for this project (the two `swift-tools-version`/`--swiftversion` CI-fix entries above): local success — even a thorough one — is not proof; only a real run on the actual CI-pinned toolchain is.

**Consequences:** `WaveformPeaksEntity.bucketsData: Data` → `minValues`/`maxValues: [Float]`; `WaveformPeaksMapper.pack`/`unpack` (manual byte manipulation) removed entirely in favor of plain `.map(\.min)`/`.map(\.max)`/`zip`. `MappingError.corruptWaveformPeaksData`'s associated values changed from byte counts to element counts, matching the new shape. No `ACCore` change — this was entirely internal to `ACPersistence`'s persistence-schema layer, exactly the boundary D4 exists to keep intact. Establishes a going-forward rule for this Deliverable's own pattern: a persistence entity that needs to store a domain array of scalars should default to a native SwiftData array attribute, not a hand-packed `Data` blob, unless a real, demonstrated reason rules that out.

**Full detail:** `Packages/ACPersistence/Sources/ACPersistence/SwiftDataModels/WaveformPeaksEntity.swift`; `Packages/ACPersistence/Sources/ACPersistence/Mappers/WaveformPeaksMapper.swift`. PR #4.

**Correction, recorded once the real cause was found (see the entry below):** this entry's diagnosis was wrong. The `[Float]`-attribute change is still kept — it's a real, independent improvement (removes hand-rolled byte (de)serialization for no offsetting benefit) — but it did **not** fix PR #4's crash. The next CI run after this change crashed identically: same test, same point, unchanged. That's strong evidence in hindsight (two structurally different implementations of the same entity producing an identical crash) that this entity was never the actual cause — evidence this entry didn't have yet when it was written, since it stopped at "the crash was in `unpack`'s `load(as:)` call" without verifying that diagnosis against a second real CI run before committing to it. Left standing rather than deleted, per this log's own standing rule (record what actually happened, including the parts that don't look clean) — see the two `swift-tools-version`/`--swiftversion` entries earlier in this log for the same practice.

---

## 2026-08-09 — D4: the real cause of PR #4's crash — a Swift exclusivity violation in the mapper's inverse-relationship assignment, found via a real crash report after two more wrong guesses

**Decision:** Every mapper that assembles a parent entity together with a to-many child collection (`ProjectMapper.toEntity` for `cues`/`people`/`labels`, `CueMapper.toEntity` for `rightHolders`, `AudioAssetMapper.toEntity` for `embeddedMarkers`) now fully materializes the child array into a local variable **first**, assigns it to the parent's relationship property, and only **then**, in a separate subsequent loop, sets each child's inverse back-reference. Previously, the back-reference was set from inside the very `.map` closure that produced the array being assigned to the parent property — e.g. `entity.rightHolders = cue.rightHolders.map { ...; rightHolderEntity.cue = entity; return rightHolderEntity }`.

**Context:** The entry above records a wrong diagnosis of PR #4's `ACPersistence` CI crash (`signal 5`/SIGTRAP, 100% reproducible, always at the exact same point: the first test of `ProjectRoundTripTests`, immediately after `ProjectRepositoryImplTests` finishes). Three targeted fixes were tried in sequence, each based on a plausible-looking correlation rather than a confirmed cause, and each had **zero effect** on an identical crash:
1. Redesigning `WaveformPeaksEntity` (the entry above) — ruled out once fixing it changed nothing.
2. Removing `@Attribute(.unique)` from `PersonEntity`/`LabelEntity.id` (multiple unique constraints across `@Model` types in one schema is a documented early-SwiftData crash source) — also independently justified (nothing in `ProjectRepositoryImpl` queries by those IDs) but also had zero effect.
3. Replacing a shared `static let Schema` with a fresh `Schema` built per `ModelContainer` (a single `Schema` instance reused across ~11 containers in one process being a plausible corruption source) — also zero effect.

After three misses, continuing to guess stopped being defensible. A temporary diagnostic step was added to `.github/workflows/ci.yml` (`if: failure()`, dumps `~/Library/Logs/DiagnosticReports`/`/Library/Logs/DiagnosticReports` after a short wait for `ReportCrash` to finish writing) — removed again in this same change once it had done its job. The first attempt found only stale, pre-baked VM-image reports; a second attempt (waiting 20s, filtered to recently-modified files) found the real one: `xctest-2026-08-09-131719.ips`. It showed `"exception": {"type":"EXC_BREAKPOINT","signal":"SIGTRAP"}`, crashing thread 0 inside `swift_beginAccess`, with register values naming `type metadata for CueEntity` and `type metadata for CueRightHolderEntity`, at a frame inside `@__swiftmacro_...CueRightHolderEntityC3cue..._PersistedProperty` — SwiftData's `@Model`-macro-generated accessor for `CueRightHolderEntity.cue`.

That pointed directly at a real bug: setting `rightHolderEntity.cue = entity` (the inverse side of a declared `inverse:` relationship pair) while `entity.rightHolders = <array still being computed>` (the forward side) is still mid-assignment is a genuine Swift exclusivity violation — SwiftData's macro-generated relationship accessors can touch the other side of an `inverse:` pair when one side is written, and doing that while the forward assignment's RHS closure is still executing overlaps two accesses to the same stored property. `swift_beginAccess` traps exactly this. It explains every observation at once: why it only reproduced with a non-empty child array (`[].map { ... }` never runs the closure body, so `ProjectRepositoryImplTests`'s minimal-fixture tests — 10 of them, all passing — never hit the code path at all); why none of the three earlier fixes moved it (none touched this code); and why it didn't reproduce locally on a newer toolchain (exclusivity-check/relationship-accessor behavior differs enough between Swift 5.10 and 6.2 that the same code traps on one and not the other).

**Alternatives Considered:**
- **Keep guessing at further plausible SwiftData-version quirks.** Rejected after the third miss — three misses in a row is the signal to get real evidence, not to keep pattern-matching against SwiftData folklore.
- **Get a real crash report from the CI runner and diagnose from it directly** *(chosen)*.
- **Fix the ordering (materialize children, assign, then set back-references) in all five affected call sites** *(chosen, once the cause was confirmed)*, over e.g. suppressing exclusivity checking for these files (`-Onone`-style enforcement flags) — rejected, since that would silence the compiler's own correctness check rather than fix the actual overlapping-access bug, and exclusivity checking exists precisely to catch bugs like this one.

**Reason for Choice:** This is the same lesson the tools-version/`--swiftversion` entries and the (wrong) entry above all point at, sharpened one step further: not just "a real CI run is the only real verification," but "a plausible-looking correlation is not a diagnosis — when the first fix based on one doesn't work, get real evidence before trying a second." A crash report naming the exact crashing function and the exact types involved is unambiguous in a way three rounds of "this looks like it could be the cause" never were.

**Consequences:** `CueMapper.swift`, `AudioAssetMapper.swift`, `ProjectMapper.swift` all changed to the materialize-then-assign-then-backreference pattern, each with a doc comment pointing back to this entry so a future change to these mappers doesn't reintroduce the interleaved version by "simplifying" it back. The `.unique`-removal and fresh-`Schema`-per-container changes from the two wrong-guess attempts are kept (both independently correct, per their own entries/comments) but are not what fixed this. The temporary CI diagnostic step is removed — not a permanent addition, its job was done once it produced the real crash report.

**Full detail:** `Packages/ACPersistence/Sources/ACPersistence/Mappers/{Cue,AudioAsset,Project}Mapper.swift`. PR #4.

**Correction, recorded once the real cause was found (see the entry below):** this entry's diagnosis was *also* wrong — a fourth wrong guess, not the third's replacement. Two things proved it, in order: (1) a deliberate fixture bisection found the crash already reproduces at the simplest possible case — one `Cue` with **zero** `CueRightHolder`s — which never executes the `rightHolders`-array closure body at all, meaning the exclusivity scenario this entry describes physically cannot occur there; (2) pinning CI to a newer Xcode made the crash disappear entirely, with this exact reordering still present and unchanged, on code that had never needed it. The reordering itself is harmless and stays in place, but it fixed nothing — recorded here rather than silently correcting the entry above, per this log's standing practice.

---

## 2026-08-09 — D4's real, confirmed root cause: a genuine Xcode 15.4 SwiftData relationship-handling defect — CI repinned to macos-15/Xcode 26.3

**Decision:** `.github/workflows/ci.yml`'s three jobs move from `runs-on: macos-14` / `xcode-version: "15.4"` to `runs-on: macos-15` / `xcode-version: "26.3"`. The PR #4 `ACPersistence` crash was never a bug in this project's code — it is a real defect in Xcode 15.4's SwiftData framework, specifically in handling a `@Model` to-many relationship with an explicit `@Relationship(deleteRule:inverse:)` on one side and a bare, un-annotated inverse `var` on the other (exactly `CLAUDE.md`'s and this codebase's own established pattern, used correctly).

**Context:** Four consecutive code-level fixes (`WaveformPeaksEntity` redesign, dropping duplicate `@Attribute(.unique)` constraints, a fresh `Schema` per `ModelContainer`, and the mapper exclusivity-violation reordering — the four entries directly above) each had **zero effect** on a fully deterministic `SIGTRAP`/`EXC_BREAKPOINT` crash, always at the same point, always on the first non-empty-`cues` `Project` inserted in the process. At the user's direction, the investigation stopped guessing at code fixes and instead isolated the actual variable, in three further steps, each confirmed on the real CI runner before moving to the next:

1. **Fixture bisection.** Seven staged tests, each adding one piece of complexity on top of the last (bare `Cue` → `+CueRightHolder` → `+Person` → `+Label` → `+AudioAsset`/`EmbeddedMarker` → `+WaveformPeaks` → the full fixture). The crash hit at **stage 1** — one `Cue`, zero `CueRightHolder`s, nothing else — immediately, as the very first test in the process. This ruled out every one of the four prior "fixes" outright: none of them touch code that stage 1 even reaches.
2. **Isolated toy reproduction.** Two brand-new `@Model` types (`ToyParent`/`ToyChild`) with zero connection to any real entity in this codebase, structurally identical in shape to `ProjectEntity.cues`/`CueEntity.project` (explicit `@Relationship(deleteRule:inverse:)` on the to-many side, bare optional on the inverse side). One insert, one save. Crashed identically on CI, every time; passed locally under Xcode 26.3 every time, under both `swift test` and a from-scratch `xcodebuild test` run against the bare package (Xcode natively infers a scheme for an un-wrapped SPM package — no hand-authored `.xcodeproj` needed). This ruled out the real schema's specific shape as the cause and ruled out the SPM-CLI-vs-Xcode-test-runner distinction as the explanation (both harnesses agreed, on both toolchains).
3. **Environment isolation.** Per GitHub's own `runner-images` documentation (github.com/actions/runner-images): `macos-14` offers Xcode 15.0.1–16.2 (15.4 default, this project's pin since D1); `macos-15` offers Xcode 16.0–26.3 (16.4 default). `26.3` is available on `macos-15` and is the exact local Xcode version already confirmed never to reproduce this crash. A config-only change (`ci.yml` only, zero source/test files touched, so the result cleanly isolates one variable) repinned all three CI jobs to `macos-15`/`26.3`. Result: **every job passed**, including `swift test — ACPersistence` (19/19 tests, including the toy test, `test_arrayOrderSurvivesRoundTrip`, and every other previously-crashing test) — the first fully green `ACPersistence` CI run in this entire investigation.

**Alternatives Considered:**
- **Keep trying code-level fixes against the real schema.** Rejected after the fourth miss — by that point the evidence (bisection reaching a trivially simple case; an isolated toy model reproducing identically) already pointed away from this project's code entirely; continuing to edit `ProjectEntity`/`CueEntity` would have been debugging the wrong layer.
- **Bisect the fixture data instead of the code, then isolate the toolchain as its own variable, only then change CI** *(chosen)* — each step was a single, cheap, reversible experiment that either confirmed or ruled out one specific hypothesis before the next was tried, rather than another round of plausible-looking correlation.
- **Pin to an intermediate Xcode version (e.g. 16.2, the newest available on `macos-14`) rather than jumping to 26.3.** Not tried — 26.3 was chosen specifically because it's the exact version already confirmed clean locally, giving the cleanest possible signal; a narrower bisection of *which* Xcode version between 15.4 and 26.3 first fixes it was not attempted and isn't needed to close this out, though it would be a reasonable follow-up if this project ever wants to pin the oldest-safe version rather than the newest-available one.

**Reason for Choice:** This closes out real, load-bearing uncertainty rather than papering over a symptom. `CLAUDE.md` rule 4's spirit (verify a dependency rather than trust it) applies here too, generalized to the toolchain itself: Xcode 15.4 was pinned at D1 specifically *because* it was `CLAUDE.md`'s documented minimum-supported-Xcode floor, on the assumption that "the documented minimum" and "actually works" were the same claim. D4 is the first Deliverable to build a real, relationship-heavy SwiftData schema, and it's what exposed that assumption was false for this specific SwiftData/Xcode combination.

**Consequences:** `CLAUDE.md`'s "Deployment Target"/"Toolchain implication" section currently states "Xcode 15 or newer" as the build-toolchain floor. That statement is now known to be actively wrong for any contributor doing real `ACPersistence`-style SwiftData relationship work: Xcode 15.4 doesn't just lack some newer convenience, it produces a genuine runtime crash on correct, ordinary relationship code. **This needs a real, explicit correction to `CLAUDE.md` in a follow-up change** (raising the stated minimum Xcode floor, not just the CI pin) — flagged here rather than silently left stale, per rule 8, but deliberately not made in this same commit since it wasn't part of what was asked for here. The four "fix" commits already in `ACPersistence`'s mapper/entity code (D4's other `docs/DECISIONS.md` entries) are harmless and stay as-is — none of them caused a problem, they just weren't the actual fix. The temporary bisection/toy-model test files (`BisectionTests.swift`, since removed; `AAAToyRelationshipTests.swift`, still present) — whether to delete the latter now that its job is done is an open question for whoever picks this up next, not decided here.

**Full detail:** `.github/workflows/ci.yml`. PR #4.

---

## 2026-08-09 — AutoCue does not adapt to system Light/Dark Mode; color tokens are fixed-value

**Decision:** AutoCue's three brand colors (Carbon Black `#202020`, White `#FFFFFF`, Burgundy `#93032E`) are fixed-value tokens, identical regardless of the system Light/Dark Mode setting. `ACDesignSystem` does not use SwiftUI's `Color(light:dark:)`-style adaptive color mechanism anywhere. Setup and Cue Sheet use a fixed "primary" surface (White background, Carbon Black foreground); Review & Export uses a fixed "reversed" surface (Carbon Black background, White foreground) — the surface style is chosen per screen, not per system appearance.

**Context:** `ROADMAP.md` D5's Acceptance Criteria, as originally written, stated "every color/font token uses semantic, dark-mode-safe definitions (no hardcoded hex without a dark variant)" and required a SwiftUI preview showing a token swatch sheet "in both appearances" — generic SwiftUI-best-practice phrasing written before the project's actual visual brief had been captured anywhere in the repository (`SPEC.md` §3 correctly scopes UI/visual design out of that document, and nothing else had captured it either — see the D5 planning session that surfaced this gap directly). Once the real brief was checked against that wording, they turned out to conflict: the brief specifies two deliberately fixed, screen-scoped palettes (white-on-black-text for Setup/Cue Sheet, black-on-white-text for Review & Export), not a palette that should shift with the user's OS-level appearance preference.

**Alternatives Considered:**
- **Standard adaptive tokens** (`Color(light:dark:)`, each of the three brand colors given a computed counterpart for the opposite system appearance), matching `ROADMAP.md` D5's originally-written Acceptance Criteria literally. Rejected — this would fabricate light/dark counterparts for colors that were never designed to have any; the two fixed surface styles are a real part of the product's visual identity (Review & Export deliberately reading as a distinct, "final output" screen via its reversed palette), not an incidental byproduct of whatever the system appearance happens to be set to.
- **Fixed-value tokens, two named surface styles selected per screen** *(chosen)*.

**Reason for Choice:** Matches the original product brief exactly, the same standard already applied elsewhere in this log (e.g. the Navigation Model entry, above) for reconciling a generically-written placeholder against a real, later-clarified requirement. `ROADMAP.md` D5's Acceptance Criteria are corrected in the same change this entry belongs to, rather than left contradicting a decision the team actually wants.

**Consequences:** `Theme.Colors` (`ACDesignSystem`) exposes `Surface.primary`/`Surface.reversed` plus a constant `accent` — never a `colorScheme`-driven pair. Rules out a future Deliverable reintroducing adaptive system-appearance colors for these three tokens without a real, separately-discussed reason to reverse this decision. `ROADMAP.md` D5's Acceptance Criteria corrected to require a swatch preview of the two surface styles, not "both appearances" in the light/dark sense. Full visual-language detail (ghost-text tint, sharp corners, dividers, transition timing, default window size) recorded in `CLAUDE.md`'s new "Visual Language" subsection, not duplicated here.

**Full detail:** `CLAUDE.md`, "Design System" → "Visual Language." Implementation: `Packages/ACDesignSystem/Sources/ACDesignSystem/Theme/Colors.swift`.

---

## 2026-08-10 — `Setup`'s three `Party` fields become optional: `producer`/`directorOrPrincipal`/`declarant`

**Decision:** `Setup.producer`, `.directorOrPrincipal`, and `.declarant` change from `Party` to `Party?`, each defaulting to `nil`. Their export-required-ness (SPEC.md §4.2) is enforced by `ValidateCueSheetUseCase` (`ROADMAP.md` D11), not by the type or at `Project`-creation time.

**Context:** Found during `ROADMAP.md` D6 planning, before `CreateProjectUseCase` was written. `Setup` requires a `Party` value for these three fields, but `Party` (`ACCore/Models/Party.swift`) is `enum { case person(Person.ID); case label(Label.ID) }` — it has no case representing "none." A brand-new `Project` (D6/T6.2's "create a named project" flow) has an empty `people`/`labels` directory at the moment of creation, so there is no real `Person`/`Label` yet for these fields to reference. The first proposal considered — auto-creating one placeholder, empty-named `Person` in the new project's directory and pointing all three fields at it — was rejected before implementation began: it directly reproduces the exact pattern D2's own acceptance criterion already rules out ("every §4.2-required field has no default value that could silently satisfy it"), just introduced at D6 instead of D2. A fabricated `Person` with an empty name pointed at by three required fields is precisely that kind of silently-satisfying default, not a real value.

**Alternatives Considered:**
- **Auto-create a placeholder `Person` at Project-creation time.** Rejected, per the reasoning above — it satisfies the type system without satisfying the actual requirement, and looks done in a diff review without being done.
- **Make the three fields `Party?`, validate non-`nil`-ness at export-readiness time instead of construction time** *(chosen)*.

Before choosing, every field in `SPEC.md` §4.2 was checked individually against the same question ("does a brand-new `Project` have an honest, non-deceptive value for this required field already, within its current type?"), not just the three `Party` fields already suspected — see the full field-by-field table below. Every other required field already has one: `title`/`knownOrFutureBroadcasts`-style `String`s can honestly start `""`; `productionRuntime`/`totalMusicRuntime: MediaDuration` can honestly start `.zero`; `productionTypes: Set<ProductionType>` can honestly start `[]`; `containsAdditionalUndeclaredWorks` has a real `.notKnown` case built for exactly this; `timecodeFrameRate`'s `.fps25` default and `declarationDate`'s "defaults to today" are both already explicitly sanctioned in SPEC.md itself, and neither stands in for missing SUISA-export data the way a fabricated `Party` reference would (`timecodeFrameRate` is never exported at all). Only `Party` has no such value. This rules out the alternative reading of D2's acceptance criterion as inconsistently applied — it was checked exhaustively, not assumed to apply narrowly to just these three fields.

| Field | Honest "not yet entered" value already representable? |
|---|---|
| `title: String` | Yes — `""` |
| `producer`/`directorOrPrincipal`/`declarant: Party` | **No** — fixed by this entry |
| `productionRuntime`/`totalMusicRuntime: MediaDuration` | Yes — `.zero` |
| `productionYear: Int` | Yes — `0` (see Consequences: implementation must use `0`, not a calendar-derived guess) |
| `containsAdditionalUndeclaredWorks: enum` | Yes — `.notKnown` is a real SUISA-form answer, not a fake default |
| `productionTypes: Set<ProductionType>` | Yes — `[]`; the ≥1 rule is already a §4.6 Use Case check, not a type constraint |
| `timecodeFrameRate: TimecodeFrameRate` | Yes — `.fps25`, already SPEC-sanctioned, never exported |
| `declarationDate: Date` | Yes — "defaults to export date," already SPEC-sanctioned |
| everything else in §4.2 | already `Optional` or conditionally-required |

**Reason for Choice:** `Optional<Party>` represents the real state honestly — a brand-new `Project` genuinely has no producer/director/declarant chosen yet — and defers the "is this actually filled in" check to exactly where every other required-but-not-yet-type-enforced field in `Setup` already gets checked (`ValidateCueSheetUseCase`, D11), rather than inventing a construction-time special case just for these three fields.

**Consequences:** `Setup`'s memberwise initializer gains `producer`/`directorOrPrincipal`/`declarant` defaults of `nil`; `DeleteRightHolderUseCase.referenceLocations` (D3, `ACCore/UseCases/DeleteRightHolderUseCase.swift`) needed **no code change** — `project.setup.producer == party` already compiles and behaves correctly comparing `Party?` to a `Party` parameter via Swift's standard non-optional-to-optional promotion in `==`. `ACPersistence`'s `SetupEntity`/`SetupMapper`/`PartyMapper` (D4) needed real changes: the three kind+id column pairs become optional, and `PartyMapper` gained optional-aware `kind(for:)`/`id(for:)`/`party(kind:id:)` variants. No existing D2–D4 test fixture broke — all of them already construct `Setup` with concrete `Party` values, which promote into the new `Party?` parameters unchanged. Rules out reintroducing a placeholder-`Person`-style default for any future required-but-referential field that hits this same "the type has no honest empty value" shape — check for a real `Optional` fix first, the same way this entry did, before reaching for a fabricated stand-in value. **Implementation note, worth keeping visible in code, not just here:** `CreateProjectUseCase`'s `productionYear` default must be `0`, not a `Calendar`-derived current year — a plausible-looking guessed year would be exactly the silently-satisfying default this whole entry exists to avoid, even though `productionYear`'s type didn't need to change.

**Full detail:** `SPEC.md` §4.2, §4.6. Implementation: `Packages/ACCore/Sources/ACCore/Models/Setup.swift`; `Packages/ACPersistence/Sources/ACPersistence/SwiftDataModels/SetupEntity.swift`; `Packages/ACPersistence/Sources/ACPersistence/Mappers/{SetupMapper,PartyMapper}.swift`. `ROADMAP.md` D6.

---

## 2026-08-10 — Per-`Project` window frame persistence: explicit `Project.ID`-keyed store, not `NSWindow.setFrameAutosaveName`

**Decision:** A Project window's size and position are persisted and restored via a custom mechanism — `ProjectWindowFrameStore` (a `Project.ID`-keyed `UserDefaults` entry, stored as a human-readable `"x,y,width,height"` string) plus `ProjectWindowFrameSaver` (an `NSWindow.willCloseNotification` observer scoped to the specific window). `NSWindow.setFrameAutosaveName` — AppKit's own, standard, built-in mechanism for exactly this purpose — is not used.

**Context:** Manual verification during D6 found that a Project window's size didn't survive being resized, closed, and reopened for the same `Project` — it reopened at the app's default size every time. The first implementation used `NSWindow.setFrameAutosaveName("ProjectWindow-\(projectID.uuidString)")` inside `WindowAccessor`'s window-resolution callback — the textbook-correct AppKit API for "remember this window's frame across close/reopen," and the obvious first thing to reach for. It was reported back as still not working. Rather than trust that the "correct" API must be working somehow, the actual `UserDefaults` state was inspected directly: `defaults read com.autocue.AutoCue` after a real resize-then-quit cycle showed **no** `"NSWindow Frame ProjectWindow-<uuid>"` key anywhere — the call had never persisted anything. What *was* present: keys like `"NSWindow Frame SwiftUI.PresentedWindowContent<Foundation.UUID, Swift.Optional<AutoCue.ProjectWindowView>>-2-AppWindow-1"` — SwiftUI's own `WindowGroup(for:)` already runs an internal frame-restoration system of its own, keyed by an auto-generated name tied to window-open *ordinal*, not `Project.ID`. That's the most plausible reason `setFrameAutosaveName` never actually engaged (SwiftUI already owns frame restoration for this window kind) and, independently, it's exactly the kind of ordinal-vs-identity mismatch that explains the observed symptom: reopening the same `Project` doesn't reliably map back to the same saved entry.

**Alternatives Considered:**
- **`NSWindow.setFrameAutosaveName`.** Rejected — empirically confirmed, not assumed, not to persist anything in this `WindowGroup(for:)` context. Kept as a documented dead end specifically so a future session doesn't lose the same time re-discovering this: it looks correct, compiles without error, and produces no visible failure — it just silently doesn't work.
- **A custom `Project.ID`-keyed `UserDefaults` store, written explicitly on `NSWindow.willCloseNotification` and read explicitly when the window is created** *(chosen)*.

**Reason for Choice:** Full, direct control removes SwiftUI's competing restoration system from the equation entirely, rather than trying to coexist with or override it. Storing the frame as a plain `"x,y,width,height"` string (not `NSStringFromRect`/a binary blob) was a deliberate choice too — it stays directly inspectable via the same `defaults read` method that caught the original failure, so the next time something in this area doesn't work, the state is checkable in one command rather than requiring another investigation to even see what's stored. The fix was verified the same way the bug was found — empirically, not by re-trusting a "should work" API: a real `NSWindow`, real `NotificationCenter` delivery, and real `UserDefaults` (`ProjectWindowFrameStoreTests`) confirm a window's frame is actually captured and persisted when its close notification fires, and manual testing with two Project windows open simultaneously confirmed both position and size are correctly remembered per-window.

**Consequences:** Rules out reaching for `NSWindow.setFrameAutosaveName` again for any future window-frame-persistence need in this app without first checking whether the same `WindowGroup(for:)`-restoration conflict applies — check this entry first. `ProjectWindowFrameSaver` observes `NSWindow.willCloseNotification` rather than becoming `window.delegate`, deliberately: `WindowGroup(for:)` may already be using that single delegate slot internally, and overwriting it wholesale risked silently breaking whatever else relies on it — a notification observer coexists safely regardless. A real, unrelated bug was caught while building the verifying test, not carried forward: calling `.close()` on a programmatically-created `NSWindow` inside the `AutoCueTests` host reliably crashed (`EXC_BAD_ACCESS` inside XCTest's own post-test memory-deallocation checker, confirmed via a real crash report) — worked around by posting `NSWindow.willCloseNotification` directly instead of calling `.close()`, which exercises the same observed code path without triggering AppKit's real window-close teardown inside the test host.

**Full detail:** `docs/REVIEW.md`'s D6 entries. Implementation: `AutoCue/ProjectWindowFrameStore.swift`, `AutoCue/ProjectWindowFrameSaver.swift`, `AutoCue/ProjectWindowView.swift`; tests: `AutoCueTests/ProjectWindowFrameStoreTests.swift`. `ROADMAP.md` D6.

---

## 2026-08-10 — `Setup` gains `beitrag`/`exploitationTypes`/`broadcastDetails` — three fields missing from the finalized §4.2 schema, found during D7 planning

**Decision:** `Setup` (`SPEC.md` §4.2) gains three fields: `beitrag: String?`, `exploitationTypes: Set<ExploitationType>` ("Verwertung," a new enum: `.cinema`/`.tv`/`.festival`/`.other`) plus `otherExploitationTypeDescription: String?`, and `broadcastDetails: BroadcastDetails?` ("Sendedatum," a new struct: `broadcaster`/`programmeName`/`date`, all optional). `broadcastDetails` sits alongside `Setup.knownOrFutureBroadcasts`, not replacing it — one specific, structured broadcast record vs. general free-text notes.

**Context:** While cross-checking D7's (`ROADMAP.md`, Setup Screen) planned UI field-by-field against `SPEC.md` §4.2 and the original product brief's field list (Filmprojekt, Start Timecode, Frame-Rate, Genre, Beitrag, Regie, Produktion, Verwertung, Jahr, Sendedatum), most terms mapped cleanly onto already-finalized fields (Filmprojekt → `title`, Frame-Rate → `timecodeFrameRate`, Regie → `directorOrPrincipal`, Produktion → `producer`, Jahr → `productionYear`, Genre → `productionTypes`). Three did not: Beitrag, Verwertung, and Sendedatum had no counterpart anywhere in the finalized schema. Flagged rather than silently mapped onto an approximate existing field (e.g. folding Sendedatum into `knownOrFutureBroadcasts`) — the project owner confirmed these are specific, named fields required to render correctly, under these exact terms, on the exported PDF/XLSX, not loose stylistic overlap with existing fields.

**Alternatives Considered:**
- **Fold all three into existing fields** (Beitrag → `episodeTitle`, Verwertung → `knownOrFutureBroadcasts`, Sendedatum → unmodeled/covered by `knownOrFutureBroadcasts`'s free text). Rejected — the project owner confirmed these need to appear as their own distinct, correctly-labeled data on the exported cue sheet, not folded into a semantically-different field.
- **Sendedatum as a single `Date` field.** Rejected once the original brief's own fuller phrasing ("Sender, Sendung, Datum der Sendung") was checked — this is a compound broadcaster/programme/date concept, not a bare date. A `BroadcastDetails` struct with three independently-optional sub-fields was chosen over a repeatable `[BroadcastDetails]` list or replacing `knownOrFutureBroadcasts` outright — both considered, per the project owner's explicit direction: a single instance, additive to the existing free-text field, not a replacement.
- **Verwertung as free text**, matching `knownOrFutureBroadcasts`'s shape. Rejected — the brief's own example values ("Cinema/TV/Festival") indicate a small, fixed, potentially-multi-valued set, the same shape `ProductionType`/`AttachmentType` already establish for exactly this kind of checkbox-grid field on this form; `Set<ExploitationType>` (`.cinema`/`.tv`/`.festival`/`.other`, `CaseIterable`) was chosen to match that established pattern rather than introduce a new shape for a structurally identical need. Distinct from `productionTypes`: that describes *what kind* of production this is, this describes *how/where it's being distributed* — a production can be both `.featureFilm` and use more than one exploitation channel over its lifetime.
- **Add the three fields as proposed, all optional at the type level** *(chosen)*.

**Reason for Choice:** Matches the `Setup`'s three `Party` fields precedent (immediately above in this log) — an honest "not yet entered" value already representable within the existing type shape (`nil`/empty `Set`), no fabricated default. None of the three was in this document's original field-by-field mapping from the physical WA Film form, so none is asserted as export-required with any confidence.

**Consequences — export-required-ness explicitly flagged as unresolved, not silently decided.** Whether any of the three should actually block export when absent, matching SUISA's real form requirements, isn't known — treated as export-optional (renders when present, doesn't block when absent, matching `isanNumber`/`seriesTitle`'s existing behavior) until confirmed. `ROADMAP.md` D11/T11.3's already-scheduled SUISA form revalidation checkpoint is extended to cover this alongside its existing form-version re-verification, rather than adding a separate checkpoint. `ACPersistence`'s already-shipped D4 code needed real changes in the same commit as this decision: `SetupEntity` gains `beitrag`/`exploitationTypesRawValues`/`otherExploitationTypeDescription`/three flat `BroadcastDetails` columns; `SetupMapper` gains the corresponding round-trip logic, including reconstructing `BroadcastDetails?` as `nil` only when all three flat columns are `nil` (partial data — e.g. a confirmed broadcaster before an exact date — must round-trip correctly, not force all-or-nothing). `ROADMAP.md` D7 is gated on this schema correction landing first, as its own commit, per `CONTRIBUTING.md` §4 ("never bundle a refactor and a feature"). **A real, purely local finding during verification, not a code defect:** a real `xcodebuild ... test` run initially crashed at launch (`SwiftDataError.loadIssueModelContainer`, `Cannot migrate store in-place: Validation error missing attribute values on mandatory destination attribute` naming `SetupEntity.exploitationTypesRawValues`) — the local sandbox container (`~/Library/Containers/com.autocue.AutoCue/`) still held a SQLite store from an earlier pre-this-change build, and SwiftData's automatic lightweight migration can't backfill a new non-optional array attribute for existing rows. Not a schema design flaw and not a CI risk (a CI runner starts with no such store); resolved by clearing the local stale store (a local dev artifact, not repo content or real user data — no migration plan exists anywhere in this codebase yet, expected for pre-release schema evolution), after which build and test both genuinely passed.

**Full detail:** `SPEC.md` §4.2, §4.2.3, §4.2.4, §6. Implementation: `Packages/ACCore/Sources/ACCore/Models/{Setup,ExploitationType,BroadcastDetails}.swift`; `Packages/ACPersistence/Sources/ACPersistence/SwiftDataModels/SetupEntity.swift`; `Packages/ACPersistence/Sources/ACPersistence/Mappers/SetupMapper.swift`. `ROADMAP.md` D7.

---

## 2026-08-10 — `CueRightHolderRole` gains `.performer` — reversing §2.2's original performer-exclusion decision

**Decision:** `CueRightHolderRole` (`SPEC.md` §4.4) gains a fifth case, `.performer` ("Interpret*in"), alongside the existing `composer`/`author`/`arranger`/`publisher`. `.performer` is informational only within AutoCue: excluded from both of `ValidateCueRightHolderSharesUseCase`'s 100%-sum checks, excluded from the PDF export's SUISA-form rendering, and included in the XLSX export.

**Context:** Found during the same D7-planning cross-check as the `Setup` fields above (`docs/DECISIONS.md`, immediately preceding entry): the original product brief's repeatable right-holder rows named Komponist\*in/Arrangeur\*in/**Interpret\*in**/Label. The first three map onto `CueRightHolderRole.composer`/`.arranger` and the `Party`/`Label` reference mechanism already in place; Interpret\*in (performer) has no counterpart — `CueRightHolderRole` is a closed four-case enum, and `SPEC.md` §2.2 explicitly and deliberately excluded performers from AutoCue's data model, reasoning that SWISSPERFORM's audiovisual-participation reporting is performer-centric and self-service, with no per-production document for AutoCue to populate the way SUISA's WA Film form works. This is therefore a genuine reversal of a previously-deliberate architectural boundary, not a quiet gap-fill — treated with the corresponding rigor: checked against real code before deciding a shape, not assumed.

**Alternatives Considered:**
- **Leave performers out of scope, per §2.2's original reasoning.** Considered and offered as the default option, since it required no reversal of already-documented architecture. Rejected by the project owner — the original brief always included Interpret\*in; the earlier scoping pass under-weighted that when §2.2 was written.
- **Add `.performer` with full share-sum participation, identical to the other four roles.** Rejected once the actual physical form was checked: SUISA's WA Film form has no percentage-share column for performers at all — the C/A/AR/E legend and its two share columns (`SPEC.md` §4.4) are composer/author/arranger/publisher only. Including `.performer` rows in the 100%-sum checks would produce false-positive validation failures (e.g. a composer legitimately at 100% plus a performer row at any nonzero value would read as "over 100%") for a role the form was never designed to account for in that column.
- **Restructure `CueRightHolder` so the two share fields become role-conditionally-optional**, rather than keeping them non-optional `Decimal` (defaulting to `0`) for `.performer` rows. Rejected as a larger, separate change than this role addition calls for — it would touch every existing `CueRightHolder` call site across D2/D9/D10 for a structural cleanliness gain this addition doesn't need; the exclusion is instead handled entirely at the validation layer (`ValidateCueRightHolderSharesUseCase` filters `.performer` rows out of both `.reduce` sums before summing).
- **Add `.performer`, excluded from share validation, excluded from PDF export, included in XLSX export** *(chosen)*.

**Reason for Choice:** Answers both technical questions the reversal required, checked against real code rather than assumed: (1) share participation — excluding `.performer` from the sum is the direct, minimal fix, verified by finding and confirming the actual silent-inclusion risk in `ValidateCueRightHolderSharesUseCase.validate`'s plain `.reduce` calls before proposing the fix, not guessed at; (2) export scope — excluding `.performer` from the PDF (no slot on the physical form) while including it in the XLSX (unconstrained tabular format, "for internal use," `SPEC.md` §3) extends §2.2's existing "reference data for SWISSPERFORM self-registration" framing rather than contradicting it — the conclusion of §2.2 (AutoCue doesn't produce an official SWISSPERFORM filing) is unchanged; only the inventory of data supporting that reuse grows by one.

**Consequences:** `CueRightHolderMapper.role(from:)` (`ACPersistence`) — a `String`-match `switch` with `default: throw`, **not compiler-exhaustive** unlike the forward `rawValue(for:)` direction — needed an explicit `"performer"` case added by hand; a dedicated `CueRightHolderMapperTests.swift` was added specifically to round-trip every `CueRightHolderRole.allCases` case (a new conformance added alongside `.performer`, for exactly this purpose) through the mapper, so this direction's lack of compiler exhaustiveness-checking doesn't go unverified. `SPEC.md` §2.2 revised (not just §4.4) to reflect `.performer` as a third instance of the same "collected as SWISSPERFORM reference data" story already told for `Person.swissPerformNumber` and `Setup`'s production-identity fields. `CLAUDE.md`'s `CueRightHolder` summary bullet updated in the same change. Rules out any future Deliverable treating `CueRightHolderRole` as a closed four-case set, or re-including `.performer` in a share sum or PDF layout without revisiting this entry first.

**Full detail:** `SPEC.md` §2.2, §4.4, §4.16. Implementation: `Packages/ACCore/Sources/ACCore/Models/CueRightHolder.swift`; `Packages/ACCore/Sources/ACCore/UseCases/ValidateCueRightHolderSharesUseCase.swift`; `Packages/ACPersistence/Sources/ACPersistence/Mappers/CueRightHolderMapper.swift`; tests: `Packages/ACPersistence/Tests/ACPersistenceTests/CueRightHolderMapperTests.swift`. `ROADMAP.md` D7.
