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
