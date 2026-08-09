# AutoCue — Roadmap

Structured as **Deliverables** (D1, D2, …) — larger, coherent vertical slices — with **Tasks** nested underneath each. A Task is roughly what the original one-milestone-per-session plan called a "milestone"; a Deliverable groups the Tasks that only make sense finished together. Work sequentially — later Deliverables assume every earlier one is done unless stated otherwise.

Every Deliverable's fields, in order: **Goal**, **Dependencies**, **Tasks**, **Acceptance Criteria**, **Testing Requirements**, **Documentation Requirements**, **Suggested Commit Boundary**. See `docs/DefinitionOfDone.md` for the checklist that applies to all of them uniformly (builds, tests pass, zero warnings, docs updated, this file updated, architecture preserved) — not restated per Deliverable below.

Commit messages follow Conventional Commits, matching the style already implied by `CLAUDE.md`/`SPEC.md`'s own framing.

**Minimum deployment target: macOS 14.0 (Sonoma).** Required by `@Observable`/`SwiftData` — see `CLAUDE.md`, "Deployment Target," and `SPEC.md` §0. Every package's `Package.swift` and the App target's deployment target setting must target this; don't use an API newer than macOS 14 without updating that section first.

## Why this structure, and what changed from the original 34-milestone plan

The original plan was 34 fine-grained milestones across 12 phases, each scoped to one Claude Code session. That granularity is preserved below as **Tasks** — nothing was deleted — but two things were wrong with treating each one as an independent top-level unit:

1. **Architectural prerequisites weren't sequenced before what depends on them.** CI/lint enforcement was originally scoped for M28 territory — 27 milestones of unenforced work would have happened first. The `libxlsxwriter` feasibility spike was originally scoped for M28 too, with everything from M1 onward implicitly trusting it would work. Both are now front-loaded: CI/lint is **Deliverable D1**, and the XLSX feasibility question is **already answered** — see D11's note.
2. **Some milestones only make sense as a unit.** M26 (Review) and M27–M29 (Export) are now one combined, always-visible navigation destination (`CLAUDE.md`, "Navigation Model") — building them as unrelated milestones invited exactly the sheet-vs-tab mistake an earlier draft of this project actually made (see `docs/DECISIONS.md`).

## Overview

| Deliverable | Title | Was (old numbering) |
|---|---|---|
| D1 | Workspace, CI, Lint & Core Value Types | M1, M2 + new CI/lint work |
| D2 | Domain Identity, Setup & Cue Models | M3, M4, M5 |
| D3 | Domain Composition & Repository Protocols | M6 |
| D4 | Persistence | M7, M8 |
| D5 | Design System Foundations | M9, M10 |
| D6 | Multi-Window App Shell & Project Library | M11, M12 |
| D7 | Setup Screen & Right-Holder Directory | M13, M14, M15 |
| D8 | Audio Analysis Pipeline | M16, M17, M18, M19, M20 + waveform peak generation |
| D9 | Cue Detection | M21, M22 |
| D10 | Cue Sheet Editor | M23, M24, M25 |
| D11 | Review & Export | M26, M27, M28, M29 |
| D12 | End-to-End Integration & Performance Validation | M30 |
| D13 | UI/Integration Test Automation | new — `CONTRIBUTING.md` §7 |
| D14 | Settings | M31 |
| D15 | App Store Packaging | M32 |
| D16 | Accessibility & Keyboard Navigation | M33 |
| D17 | Final Polish | M34 |

---

## D1 — Workspace, CI, Lint & Core Value Types

**Status: Complete (2026-08-08), with one correction.** Verified locally (`swift test` × 7 packages, `swiftformat --lint`, `swiftlint lint --strict`, both architecture-boundary scripts, `xcodebuild build`/`test -scheme AutoCue`) **and** confirmed against a real, watched-to-completion CI run on PR #1 — all 9 jobs (lint + 7×`swift test` + `xcodebuild build`/`test`) passed on the actual Xcode-15.4-pinned runner. **However, `MediaDuration` — despite T1.4 below and this Deliverable's own PR #1 commit message both claiming it was implemented ahead of schedule — was never actually merged.** No `MediaDuration.swift` existed anywhere in `Packages/ACCore/Sources` at the point D1 was marked complete; only `Timecode`/`TimecodeFrameRate`/`PostalAddress`/`Party`/`ProgressUpdate`/`OperationProgress` were real. This was caught during D2 planning (cross-checking this file against the actual source tree, not trusting the prior claim) and completed as corrective work at the start of D2, before D2's own Tasks began — see `docs/DECISIONS.md` for the full account, stated plainly rather than silently patched in to make D1's history look cleaner than it was.

**Goal:** Create a compiling, CI-verified, lint-enforced workspace before any domain logic is added, so every later Deliverable inherits automated enforcement from day one instead of 27+ milestones of unverified assumptions (see "Why this structure," above, and `docs/DECISIONS.md`).

**Dependencies:** None — this is the starting point.

**Tasks:**
- **T1.1 — Workspace & package scaffolding** *(was M1)*. Create the Xcode workspace, thin app target, and empty local SPM packages wired together per `CLAUDE.md`'s folder structure. Files: `AutoCue.xcworkspace`; `AutoCue/AutoCueApp.swift`, `DependencyContainer.swift` (placeholders); `Packages/{ACCore,ACAudioKit,ACExport,ACPersistence,ACDesignSystem,ACFeatures,ACTestSupport}/Package.swift` + one placeholder source file and one placeholder test each (`ACCore`/`ACExport` already have real `Package.swift` files with real content from ahead-of-schedule work — see T1.4 — merge into this scaffolding, don't recreate); `.gitignore` (Xcode/SPM, already present). **Correction to this Task's original file list:** `AppState.swift` was previously listed here under the App target, which contradicts `CLAUDE.md`'s Folder/Package Structure section (`AppState` is per-window navigation state living in `ACFeatures`, not the App target). Resolved in favor of `CLAUDE.md`: `ACFeatures` gets a generic placeholder source file at D1 like every other new package; the real `AppState.swift` is built at D6/T6.1 as `CLAUDE.md` already specifies. See `docs/DECISIONS.md`.
- **T1.2 — CI pipeline** *(new)*. `.github/workflows/ci.yml` already exists (built ahead of schedule alongside this restructuring) running `swift test` per package plus the two architecture scripts below. This task's remaining scope: add an `xcodebuild test -scheme AutoCue` job once the workspace from T1.1 exists, and extend the `test-packages` matrix to include every package as it gains real source.
- **T1.3 — Lint & formatting config** *(new)*. `.swiftformat` and `.swiftlint.yml` already exist (ahead of schedule, verified against the two existing packages with zero violations). This task's remaining scope: nothing structural — just keep both config files current as new packages/conventions are added.
- **T1.4 — Core value types** *(was M2)*. `Timecode`/`TimecodeFrameRate` were genuinely implemented and tested ahead of schedule (`Packages/ACCore/Sources/ACCore/Models/`, `SPEC.md` §4.9, `docs/DECISIONS.md`); `PostalAddress`, `Party`, and `ProgressUpdate`/`OperationProgress` (`SPEC.md` §4.17) were built as this task's remaining scope, alongside folding the existing `ACCore`/`ACExport` spike packages into the real T1.1 workspace structure. **`MediaDuration` (`SPEC.md` §4.8) was incorrectly claimed as also already-implemented at this point — it wasn't.** It shipped only later, as corrective work at the start of D2, once the gap was caught. See the Status note above and `docs/DECISIONS.md`.

**Acceptance Criteria:**
- `xcodebuild -scheme AutoCue build` succeeds; app launches to an empty window.
- Every package target builds and its placeholder test passes; `ACCore`/`ACExport` retain their existing real tests (18 + 4 tests respectively) after the merge into the workspace.
- Every package's `Package.swift` and the App target set macOS 14.0 as the deployment target.
- CI is green on the resulting workspace: lint job (SwiftFormat check, SwiftLint `--strict`, both architecture scripts) and test job (per-package `swift test` plus, once added, `xcodebuild test`).
- Unit tests cover `hh:mm:ss`/`HH:MM:SS:FF` formatting, arithmetic, equality, and an `Equatable`-based round-trip for `MediaDuration`/`Timecode`/`TimecodeFrameRate`/`PostalAddress`/`Party` — not `Codable` (`CLAUDE.md`, "Domain Model Value-Type Conformances").
- No import beyond `Foundation` anywhere in `ACCore` (mechanically checked by `Scripts/check-import-boundaries.sh` from this point forward).

**Testing Requirements:** `ACCore` unit tests only (no I/O layer exists yet) — pure value-type tests per `CONTRIBUTING.md` §5.

**Documentation Requirements:** None expected beyond what's already been updated for `MediaDuration`/`Timecode`/CI/lint (this Deliverable's own restructuring). If `PostalAddress`/`Party`/`ProgressUpdate` need any correction to their `SPEC.md` §4.5/§4.17 descriptions once actually built, update in the same change.

**Suggested Commit Boundary:** 2–3 commits — workspace scaffolding; CI/lint wiring (if not already committed); `PostalAddress`/`Party`/`ProgressUpdate` + tests, folding in the existing spike packages.

---

## D2 — Domain Identity, Setup & Cue Models

**Status: Complete (2026-08-08).** Verified locally (`swift test` × 7 packages — ACCore 99 tests, ACExport 4, five placeholder packages 1 each, 0 failures anywhere; `swiftformat --lint`; `swiftlint lint --strict`; both architecture-boundary scripts) **and** confirmed against two real, watched-to-completion CI runs on the actual Xcode-15.4-pinned runner: all 9 jobs passed on PR #2, then all 9 jobs passed again on the post-merge run against `main` itself (run `31276476038`) after squash-merging as `9454025`. Same practice as D1 — a real CI run, not local success, is the bar. See `docs/DECISIONS.md` and `docs/REVIEW.md` for two real gaps found and fixed during this Deliverable: `MediaDuration` was missing despite D1 claiming it was done, and `SPEC.md` had no field backing `arrangementAuthorizationAttached`'s "still copyright-protected" condition (`Cue.isArrangementOfProtectedOriginal` added to close it). Also see `docs/DECISIONS.md`'s toolchain-wiring update: this session's `xcode-select` was pointed at the bare Command Line Tools (no `XCTest`/`sourcekitd`), fixed system-wide via `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` — plain `swift test`/`swiftlint` now work with no env var override, confirmed against this actual merged state.

**Goal:** Build the identity, production-header, and per-work domain types — the bulk of the SUISA-mapped schema.

**Dependencies:** D1.

**Tasks:**
- **T2.1 — Person and Label models** *(was M3)*. `Models/{Person,Label}.swift` + tests. **Complete.**
- **T2.2 — Setup model** *(was M4)*. `Models/Setup.swift`, `Models/ProductionType.swift`, `Models/AttachmentType.swift` + tests, per `SPEC.md` §4.2. **Complete.**
- **T2.3 — Cue, CueRightHolder, and share validation** *(was M5)*. `Models/Cue.swift`, `Models/CueRightHolder.swift`, `UseCases/ValidateCueRightHolderSharesUseCase.swift` + tests, per `SPEC.md` §4.3–4.6. **Complete.** Also added `Cue.isArrangementOfProtectedOriginal` (not originally listed — closes the §4.4/§4.6 schema gap noted above; see `docs/DECISIONS.md` and `docs/REVIEW.md`).

**Acceptance Criteria:**
- `Equatable`-based round-trip tests pass for `Person`/`Label`/`Setup`/`Cue` (not `Codable`); `Identifiable` conformance present on `Person`/`Label`.
- A tested helper distinguishes "has complete address" (all four `PostalAddress` parts present) per `SPEC.md` §4.5.
- Every field listed as required in `SPEC.md` §4.2 has no default value that could silently satisfy it; `ProductionType`/`AttachmentType` cases match §4.2.1/4.2.2 exactly; `Setup.timecodeFrameRate: TimecodeFrameRate` (default `.fps25`) is included per §4.2/§4.9.
- Unit tests prove the 100%-sum rule is checked independently for `performanceBroadcastShare` and `mechanicalRightsShare`, using exact `Decimal` equality against `100.00` with zero tolerance (`SPEC.md` §4.6) — include a case proving an uneven legitimate split (e.g. `33.33`/`33.33`/`33.34`) passes.
- Unit tests prove `publishingContractAttached`/`arrangementAuthorizationAttached` are flagged as missing only when their triggering role/condition applies.

**Testing Requirements:** `ACCore` unit tests only, per `CONTRIBUTING.md` §5 — no mocks needed anywhere in this Deliverable.

**Documentation Requirements:** None expected — this Deliverable implements what `SPEC.md` already fully specifies. If implementation surfaces an ambiguity `SPEC.md` didn't resolve, fix `SPEC.md` in the same change per `CLAUDE.md` rule 9, don't silently improvise.

**Suggested Commit Boundary:** 3 commits, one per Task — each is a self-contained model + its tests, and none depends on code from a later Task in this Deliverable.

---

## D3 — Domain Composition & Repository Protocols

**Status: Complete (2026-08-08).** Verified locally (`swift test` × 7 packages, `swiftformat --lint`, `swiftlint lint --strict`, both architecture-boundary scripts) **and** confirmed against a real, watched-to-completion CI run on PR #3 — all 9 jobs passed on the actual Xcode-15.4-pinned runner, then all 9 jobs passed again on the post-merge run against `main` itself (commit `72f03cb`). A real bug was found and fixed within this Deliverable, not carried forward: `DeleteRightHolderUseCase`'s internal reconstruction helper wasn't bumping `Project.updatedAt` on a successful right-holder deletion, contradicting `SPEC.md` §4.1's unqualified scope for that field — fixed, with orchestration tests added asserting the field advances on success and stays untouched when a delete is correctly blocked. Six stale cross-references to an earlier two-type `DeletePersonUseCase`/`DeleteLabelUseCase` phrasing (`ROADMAP.md`, `CLAUDE.md`, `SPEC.md`) were also corrected to name the real, shared `DeleteRightHolderUseCase` this Deliverable actually built — one of them (`ROADMAP.md` D7's own acceptance criteria) would otherwise have pointed a future session at a type that doesn't exist. This "Status" note itself was added later than D3's actual completion — see `docs/REVIEW.md`'s D3 entry (added 2026-08-09, alongside D4's own Definition-of-Done follow-up work) for the full account, including that gap's own history.

**Goal:** Compose the top-level `Project` container and declare every Data-layer boundary `ACCore` will be injected against.

**Dependencies:** D2.

**Tasks:**
- **T3.1 — AudioAsset, Settings, AnalysisSettings, WaveformPeaks, Project** *(was M6, expanded)*. `Models/{AudioAsset,EmbeddedMarker,BroadcastWaveMetadata,Settings,AnalysisSettings,WaveformPeaks,WaveformPeakBucket,Project}.swift` + tests, per `SPEC.md` §4.1, §4.7, §4.10, §4.11, §4.15.
- **T3.2 — Repository protocols**. `RepositoryProtocols/{ProjectRepository,AudioAnalysisRepository,ExportRepository}.swift`, each declared `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless."
- **T3.3 — Delete guard and PartyResolver**. `UseCases/DeleteRightHolderUseCase.swift` (`deletePerson`/`deleteLabel` methods, the shared-Use-Case option `SPEC.md` §4.12 offers), `Models/PartyResolver.swift`, per `SPEC.md` §4.12–§4.13.
- **T3.4 — In-memory test fakes**. `Packages/ACTestSupport/Sources/ACTestSupport/Fakes/InMemory{ProjectRepository,AudioAnalysisRepository,ExportRepository}.swift`.

**Acceptance Criteria:**
- `Project` composes `Setup`, `[Cue]`, `[Person]`, `[Label]`, an optional `AudioAsset`, and an optional `WaveformPeaks` (`SPEC.md` §4.1, §4.15); round-trips via an `Equatable`-based test.
- `AudioAsset` never contains raw or downsampled sample data (`SPEC.md` §4.10 invariant) — a test asserts this isn't structurally possible (no such stored property exists).
- `DeleteRightHolderUseCase`'s `deletePerson`/`deleteLabel` correctly blocks deletion and returns every `PartyReferenceLocation` when a reference exists (`SPEC.md` §4.12) — tested for all five reference sites (`Setup.producer`, `.directorOrPrincipal`, `.declarant`, `Settings.defaultDeclarant`, `Cue.rightHolders[].party`).
- `PartyResolver.resolve` returns the correct display data for both `Person`/`Label` cases and `nil` only for a dangling reference (`SPEC.md` §4.13).
- A grep check (or, from this Deliverable forward, `Scripts/check-import-boundaries.sh` in CI) confirms no Apple framework beyond `Foundation` is imported anywhere in `ACCore`.
- In-memory fake implementations of all three protocols exist in `ACTestSupport` and pass a basic CRUD smoke test.

**Testing Requirements:** `ACCore` unit tests, per `CONTRIBUTING.md` §5. `ACTestSupport` fakes get their own smoke test proving they actually behave like the protocol they fake (create → appears in fetch-all → delete → gone), so a later Deliverable's ViewModel tests can trust them.

**Documentation Requirements:** None expected — implements existing `SPEC.md` §4.1/§4.7/§4.10–§4.13/§4.15 directly.

**Suggested Commit Boundary:** 2 commits — models (T3.1) together with repository protocols (T3.2), since `Project`'s shape and the protocols that operate on it are tightly coupled; then delete-guard/resolver + test fakes (T3.3–T3.4) as a second commit.

---

## D4 — Persistence

**Status: Complete (2026-08-09), after a real investigation, not a clean first pass.** Verified locally (`swift test` × 7 packages, `swiftformat --lint`, `swiftlint lint --strict`, both architecture-boundary scripts, `xcodebuild build`/`test -scheme AutoCue`) **and** confirmed against real CI runs on PR #4 — but not on the first attempt. `swift test — ACPersistence` failed on **8 consecutive real CI runs**, always with the same fully deterministic `SIGTRAP` crash at the same point, which four separate code-level fixes (each verified clean locally first, each plausible, each wrong) failed to move at all. The actual cause — a genuine Xcode 15.4 SwiftData defect in relationship handling, not a mistake in this project's schema — was found only by abandoning code-level guessing for a systematic fixture bisection and an isolated toy-`@Model` reproduction, then confirmed by a config-only CI environment change (`macos-15`/Xcode 26.3) that took the job from 8/8 failures to a clean pass with zero source files touched. `CLAUDE.md`'s toolchain-floor statement was corrected in the same PR as a direct consequence. See `docs/DECISIONS.md`'s full sequence of D4 entries — including the entries that honestly correct its own earlier wrong diagnoses rather than silently editing them away — and the `docs/REVIEW.md` entry for this Deliverable for the complete account. All 9 CI jobs green on PR #4's final HEAD and reconfirmed green on the post-merge `main` run. One scope deviation from T4.1 below, noted here rather than silently: a `SettingsEntity` was **not** built, despite T4.1's file list naming "Settings" among the entity types — `Settings` isn't part of `Project`'s aggregate and has no repository until D14/T14.1, so nothing in this Deliverable's real Acceptance Criteria ever exercises it; building it now would have been speculative persistence-layer work ahead of a real consumer.

**Goal:** Persist the domain model without leaking persistence details into `ACCore` or `ACFeatures`.

**Dependencies:** D3.

**Tasks:**
- **T4.1 — SwiftData schema and mappers** *(was M7)*. `Packages/ACPersistence/Sources/ACPersistence/SwiftDataModels/*Entity.swift` (Project, Setup, Cue, CueRightHolder, Person, Label, Settings, plus any new types from D3), `Mappers/*.swift`; `Package.swift` updated with `SwiftData` + `ACCore` deps; tests.
- **T4.2 — ProjectRepositoryImpl** *(was M8)*. `Packages/ACPersistence/Sources/ACPersistence/ProjectRepositoryImpl.swift` + tests. Implemented as, or internally backed by, an `actor`, serializing writes **per `Project.ID`** (`CLAUDE.md`, "Document & Window Model") — not a single lock spanning every open Project.
- **T4.3 — Live-observation API**. `ProjectRepository.observeAll() -> AsyncStream<[Project]>` (or equivalent), republishing on every mutating call, per `CLAUDE.md`, "Single Source of Truth" (this is what the Library window's project list and any later live-updating UI consumes — never `@Query`).

**Acceptance Criteria:**
- A round-trip test builds a domain `Project` fixture, maps it to entities, inserts into an in-memory `ModelContainer`, fetches back, maps to domain, and asserts equality.
- No domain type is referenced directly by a `@Model` class's persisted properties — only via the mapper.
- CRUD (create, fetch all, fetch by id, update, delete) tested against an in-memory container; conforms to `ACCore.ProjectRepository` with no additional public API surface.
- A test proves two concurrent saves to the *same* `Project.ID` serialize correctly (second waits for first, neither is lost); a second test proves saves to *different* `Project.ID`s do not block each other.
- `observeAll()` (or equivalent) emits a new value after every create/update/delete performed through the same repository instance.

**Testing Requirements:** Per `CONTRIBUTING.md` §5 — Data-layer packages test against real fixtures (a real in-memory `ModelContainer`), not mocks of SwiftData itself.

**Documentation Requirements:** If the real `observeAll()` signature differs from the illustrative one in `CLAUDE.md`'s "Single Source of Truth" section, update that section to match what was actually built, in the same change.

**Suggested Commit Boundary:** 2 commits — schema/mappers (T4.1) first (it's the foundation the repository implementation depends on), then `ProjectRepositoryImpl` including live-observation (T4.2–T4.3 together, since the observation API is part of the same type).

---

## D5 — Design System Foundations

**Goal:** Define the shared visual language and the first feature-agnostic components, before any screen exists to consume them.

**Dependencies:** D1.

**Correction to this Deliverable's original scope, made during D5 planning, before implementation began:** the visual design AutoCue actually targets (brand colors, typography, sharp corners, transition timing, etc.) had never been written down anywhere in this repository — `SPEC.md` §3 correctly scopes UI/visual design out of that document, and nothing else had captured it either, so D5's Acceptance Criteria below were originally written as generic SwiftUI-best-practice placeholders ("dark-mode-safe," "both appearances") rather than against a real brief. Once the real brief was supplied and checked against that wording, it conflicted: AutoCue's palette is two deliberately **fixed** surface styles chosen per screen (Setup/Cue Sheet: white background, black text; Review & Export: black background, white text), not colors that should adapt to the system Light/Dark Mode setting. See `docs/DECISIONS.md` ("AutoCue does not adapt to system Light/Dark Mode") and `CLAUDE.md`'s new "Visual Language" subsection (under Design System) for the full, now-documented visual language. The Tasks/Acceptance Criteria below are corrected to match; two files are added to T5.2 beyond its original list (`Modifiers/SharpButtonStyle.swift`, `Theme/Motion.swift`) because the brief explicitly calls for sharp corners and the transition convention to be real, reusable, enforced components — not prose guidelines a future screen could silently violate.

**Tasks:**
- **T5.1 — Design tokens** *(was M9, expanded)*. `Packages/ACDesignSystem/Sources/ACDesignSystem/Theme/{Colors,Typography,Spacing,Motion}.swift` + a preview file (`ThemePreview.swift`). `Colors.swift` exposes fixed-value `Theme.Colors.accent` plus two named, fixed surface styles (`Surface.primary`/`Surface.reversed`) — never a `colorScheme`-adaptive pair. `Typography.swift` bundles and registers Space Grotesk (Regular/Medium/Bold, vendored from Google Fonts under OFL) via `Resources/Fonts/`. `Motion.swift` adds `Theme.Motion.standard` (the shared ~1.5s transition) beyond the originally-planned file list.
- **T5.2 — Core reusable components** *(was M10, expanded)*. `Components/{EmptyStateView,ProgressBanner}.swift`, `Modifiers/{ErrorAlertModifier,SharpButtonStyle}.swift` — `SharpButtonStyle` added beyond the original list to make "no rounded corners, ever" a real enforced component rather than a convention every future button call site has to remember.

**Acceptance Criteria:**
- Package builds for the macOS target; every color token is a fixed, documented value (`CLAUDE.md`, "Visual Language") — not a `colorScheme`-adaptive pair; no raw hex literal appears outside `Theme/` (mechanically checked by `Scripts/check-color-literals.sh`, which deliberately skips `ACDesignSystem` itself since that's where the literals are meant to live).
- A SwiftUI preview renders a token swatch sheet showing **both fixed surface styles** (primary and reversed) side by side — not "both appearances" in the system-light/dark sense, since these tokens don't adapt to that setting at all.
- Each component has a SwiftUI preview with representative sample data, rendered against both surface styles.
- `SharpButtonStyle` renders with zero corner radius — verified visually via its own preview, since SwiftUI's stock `.bordered`/`.borderedProminent` styles round by default on macOS and this component exists specifically to prevent that.
- None of these files import `ACCore` or reference any domain type — only `String`/closures/bindings (mechanically checked from this Deliverable forward by `Scripts/check-import-boundaries.sh`).

**Testing Requirements:** No unit tests expected — `ACDesignSystem` components are verified via SwiftUI previews per `CONTRIBUTING.md` §5's "Views: still not unit tested" note; this package is entirely Views/tokens.

**Documentation Requirements:** `CLAUDE.md` gains a "Visual Language" subsection (under Design System) documenting the full visual brief this Deliverable implements; `docs/DECISIONS.md` gains an entry recording the fixed-appearance-vs-adaptive-color decision. Both are corrective work done at the start of this Deliverable, not standard D5 output — see the correction note above.

**Suggested Commit Boundary:** 2 commits, one per Task — tokens are a real dependency of the components, so tokens land first.

---

## D6 — Multi-Window App Shell & Project Library

**Goal:** Give the app its real multi-window shell — the Library scene, the per-Project `WindowGroup`, and the Settings scene — and the first real feature: creating, listing, and opening Projects. Per `CLAUDE.md`'s "Navigation Model" and "Document & Window Model."

**Dependencies:** D4, D5.

**Tasks:**
- **T6.1 — Dependency container and multi-window shell** *(was M11)*. `AutoCue/DependencyContainer.swift` (real wiring), `AutoCue/OpenProjectWindowRegistry.swift` (app-wide duplicate-open guard), `AutoCueApp.swift` (declares the Library scene, the `WindowGroup(for: Project.ID.self)` Project-window scene, and the `Settings` scene), `Packages/ACFeatures/Sources/ACFeatures/AppState.swift` (per-window: `selectedSection` only — no `selectedProjectID`), `AutoCue.entitlements` (App Sandbox on).
- **T6.2 — Project Library feature** *(was M12)*. `Packages/ACFeatures/Sources/ACFeatures/ProjectLibrary/ViewModels/ProjectLibraryViewModel.swift`, `Views/ProjectLibraryView.swift`, `Components/ProjectRow.swift`.

**Acceptance Criteria:**
- App launches showing the Library scene (empty project list + placeholder empty state).
- Opening a project from the Library opens a new Project window showing an empty content/detail `NavigationSplitView`; opening the same project again from the Library focuses the existing window instead of creating a duplicate (`OpenProjectWindowRegistry`).
- A grep check confirms `ProjectRepositoryImpl` is constructed only inside `DependencyContainer`.
- App runs under App Sandbox with no violations in Console.
- Manually verified: create a named project, see it listed, open it (opens/focuses its Project window per `OpenProjectWindowRegistry`), delete it.
- The Library's project list reflects the repository live (`ProjectRepository`'s `AsyncStream`, D4/T4.3 — never `@Query`) — no stale state after create/delete in the same session.

**Testing Requirements:** `ProjectLibraryViewModel` tested against `ACTestSupport`'s fake `ProjectRepository`, per `CONTRIBUTING.md` §5. `OpenProjectWindowRegistry`'s register/unregister/lookup logic gets a direct unit test (it's plain state, not SwiftUI-dependent, so it's testable without a UI test). The multi-window behavior itself (focus-not-duplicate) is manually verified here; it's also the flow D13 automates later.

**Documentation Requirements:** None expected — implements `CLAUDE.md`'s existing Navigation Model / Document & Window Model sections directly. If real implementation reveals a gap in those sections, fix them in the same change.

**Suggested Commit Boundary:** 2 commits, one per Task — the shell (T6.1) must exist before the Library feature (T6.2) can be wired into it.

---

## D7 — Setup Screen & Right-Holder Directory

**Goal:** Build the first real content screen and let its `Party`-typed fields reference a project-scoped `Person`/`Label` directory.

**Dependencies:** D6.

**Tasks:**
- **T7.1 — Setup view model and use case** *(was M13)*. `Packages/ACCore/Sources/ACCore/UseCases/UpdateSetupUseCase.swift`; `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/ViewModels/SetupViewModel.swift`. No UI yet.
- **T7.2 — Setup view** *(was M14)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/Views/SetupView.swift`, `ProductionTypePicker.swift`, `PostalAddressFields.swift`.
- **T7.3 — Right-holder directory and party picker** *(was M15)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/ViewModels/RightHolderDirectoryViewModel.swift`, `Views/{PersonEditorSheet,LabelEditorSheet,PartyPickerView}.swift`.

**Acceptance Criteria:**
- Unit tests (against `ACTestSupport`'s fake repository) verify editing any `Setup` field triggers a debounced save; missing-required-field state is exposed as a published property, not computed ad hoc in a view.
- Manually verified: every required `Setup` field is editable, unmet-required fields are visibly indicated, `productionTypes` multi-select works, edits persist across app relaunch.
- Manually verified: picking a producer offers "create new Person/Label" inline, and the picker lists the project's existing directory.
- Manually verified: attempting to delete a `Person`/`Label` still referenced as `Setup.producer`/`.directorOrPrincipal`/`.declarant` is blocked with a message identifying exactly which field references it (D3/T3.3's `DeleteRightHolderUseCase`, `SPEC.md` §4.12).

**Testing Requirements:** `SetupViewModel`/`RightHolderDirectoryViewModel` tested against `ACTestSupport` fakes, per `CONTRIBUTING.md` §5. Views verified manually per this Deliverable's acceptance criteria — not unit tested (§5), and not yet in D13's automated flow (D13 covers Setup as the *first step* of its golden-path flow, but that's D13's job, not this Deliverable's).

**Documentation Requirements:** None expected.

**Suggested Commit Boundary:** 3 commits, one per Task, matching the natural model→view→directory dependency order.

---

## D8 — Audio Analysis Pipeline

**Goal:** Read WAV files in bounded chunks, extract embedded markers, detect silence-gap boundaries, generate waveform peak data, and let the user import a file into a project — all without ever loading a full file into memory.

**Dependencies:** D3 (for `AudioAnalysisRepository`/`AnalysisSettings`/`WaveformPeaks`), D6 (for the app shell to host the import UI).

**Tasks:**
- **T8.1 — WAV streaming reader** *(was M16)*. `Packages/ACAudioKit/Sources/ACAudioKit/Streaming/WAVStreamingReader.swift` + tests with a small fixture WAV.
- **T8.2 — RIFF/BWF chunk parser** *(was M17)*. `Packages/ACAudioKit/Sources/ACAudioKit/WAVParsing/{RIFFChunkParser,BroadcastWaveMetadata}.swift` + tests with a fixture WAV containing `cue`/`labl`/`ltxt`/`bext` chunks.
- **T8.3 — Silence/level analysis** *(was M18)*. `Packages/ACAudioKit/Sources/ACAudioKit/Analysis/SilenceDetector.swift` (vDSP-based, implementing the full contract in `SPEC.md` §4.11 — windowed RMS, manual/automatic threshold calibration, reverb-tail truncation, embedded-marker merge tolerance) + tests.
- **T8.4 — Waveform peak extraction** *(new — `SPEC.md` §4.15)*. `Packages/ACAudioKit/Sources/ACAudioKit/Analysis/WaveformPeakExtractor.swift` (vDSP min/max reduction per bucket, computed via the same streaming reader from T8.1 — never a second full-file read).
- **T8.5 — AudioAnalysisRepositoryImpl and import/waveform use cases** *(was M19, expanded)*. `Packages/ACAudioKit/Sources/ACAudioKit/AudioAnalysisRepositoryImpl.swift`; `Packages/ACCore/Sources/ACCore/UseCases/{ImportAudioUseCase,GenerateWaveformPeaksUseCase,GenerateWaveformDetailUseCase}.swift`; `DependencyContainer` update.
- **T8.6 — Audio import UI** *(was M20)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/ViewModels/AudioImportViewModel.swift`, `Views/AudioImportView.swift`.

**Acceptance Criteria:**
- Streaming reader reports sample rate, channel count, bit depth, and duration correctly for the fixture; a test asserts multiple chunk callbacks occur for a file larger than one chunk (proves it isn't loading the whole file at once).
- Chunk parser extracts all marker entries with sample-accurate positions from the fixture; returns an empty result (not a crash or throw) for a WAV with none of these chunks.
- Given a synthetic buffer with known silent/loud regions, detected boundaries fall within a defined sample tolerance; a performance test analyzing a ~10-minute synthetic buffer completes within a documented time budget, validating the approach scales toward 3 hours. Both manual and automatic `noiseFloorCalibrationMode` are covered, including the every-`noiseFloorReestimationIntervalSeconds` re-calibration behavior.
- Waveform peak extraction produces exactly `resolution` (4096) buckets regardless of source file duration; a test confirms the persisted overview's memory footprint matches the documented ~32KB bound.
- `loadAsset(from:)` returns a populated `AudioAsset` (including embedded markers) for the fixture file; `GenerateWaveformPeaksUseCase` runs immediately after import and persists to `Project.waveformPeaks` per `SPEC.md` §4.15's lifecycle rule.
- Progress is emitted via the shared `AsyncThrowingStream<OperationProgress<T>, Error>` contract (`CLAUDE.md`, "Long-Running Operations") with at least start/intermediate/complete events for a multi-chunk file — for both import and waveform generation.
- Manually verified with a real multi-minute WAV file via `fileImporter`: progress updates without blocking the UI, resulting `AudioAsset` and `WaveformPeaks` are persisted on the project; security-scoped bookmark is stored and file access survives an app relaunch (required under App Sandbox).

**Testing Requirements:** Per `CONTRIBUTING.md` §5 — `ACAudioKit` tests run against real fixture WAV files, never mocks of file I/O. `ImportAudioUseCase`/`GenerateWaveformPeaksUseCase` get `ACCore`-level tests against a fixture-backed fake `AudioAnalysisRepository`. `AudioImportViewModel` tested against `ACTestSupport` fakes.

**Documentation Requirements:** None expected — implements `SPEC.md` §4.10, §4.11, §4.15 as already specified. If the actual noise-floor-estimation statistic (left open in §4.11 as "T8.3's job") turns out to need documenting more precisely than the contract already does, add that detail to §4.11 in the same change.

**Suggested Commit Boundary:** Several commits tracking the Task boundaries above (T8.1–T8.6) — this is the largest Deliverable in the roadmap and should not be one commit; group at minimum as: streaming+parsing (T8.1–T8.2), silence detection (T8.3), waveform extraction (T8.4), repository+use cases (T8.5), import UI (T8.6).

---

## D9 — Cue Detection

**Goal:** Turn raw analysis output (embedded markers + silence-detected gaps) into `Cue` entities, let the user trigger this without blocking the app, and let them correct what detection got wrong before handing off to the general-purpose Cue Sheet Editor (D10).

**Dependencies:** D8, D2 (for `Cue`).

**Note on manual correction's architectural home:** correction happens entirely at the `Cue` level — `AudioAsset`/`EmbeddedMarker` are never mutated, preserving the immutable-snapshot invariant from D3 (`SPEC.md` §4.10, §4.19). This Deliverable owns the waveform-based correction surface (T9.3) specifically because it's the natural point in the workflow to review what detection just produced; adding/removing individual cues afterward is D10's general-purpose editing capability (`CueTableView`'s add/delete controls), not duplicated here — see `SPEC.md` §4.19 for the full reasoning and the exact division of labor between this Deliverable and D10.

**Tasks:**
- **T9.1 — DetectCuesUseCase** *(was M21)*. `Packages/ACCore/Sources/ACCore/UseCases/DetectCuesUseCase.swift` + tests.
- **T9.2 — Cue detection UI** *(was M22)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/ViewModels/CueDetectionViewModel.swift`, `Views/CueDetectionProgressView.swift`. A transient progress indicator for the run itself — not where correction happens (`SPEC.md` §4.19).
- **T9.3 — Waveform view and drag-to-reposition correction** *(new — `SPEC.md` §4.15, §4.19)*. Builds `WaveformView` (`Packages/ACDesignSystem/Sources/ACDesignSystem/Components/WaveformView.swift`) — not previously scoped as a buildable component anywhere in this roadmap despite being named in `CLAUDE.md`'s folder structure from the project's first commit. Display mode consumes `WaveformDisplayData` (`SPEC.md` §4.15); interactive mode overlays cue-boundary markers with a drag gesture, reporting `(boundaryIndex: Int, newOffsetSeconds: Double)` via closure — no domain type crosses the `ACDesignSystem` boundary. Also builds the `ACFeatures` review surface hosting it (e.g. `CueSheetEditor/Views/CueDetectionReviewView.swift`), reached from the Cue Sheet Editor once `Project.cues` has populated, mapping dragged offsets to `Timecode` and writing through `UpdateCueUseCase`'s edit path (D10/T10.1).

**Acceptance Criteria:**
- Unit tests (against a fixture-backed fake `AudioAnalysisRepository`) verify: embedded markers become `Cue`s with `source == .embeddedMarker`; silence-detected gaps fill in as `.detectedFromAudio`; overlapping detections within `embeddedMarkerMergeToleranceSeconds` are merged per `SPEC.md` §4.11's "Combining with embedded markers" rule, not double-counted.
- Manually verified on a long (multi-hour-class) file: UI stays responsive throughout, progress is visible, `Project.cues` populates on completion.
- Re-running detection warns before discarding any `Cue` not sourced as `.detectedFromAudio`. A unit test specifically proves a `.detectedFromAudio` cue that has been manually edited (title, duration, or `startTimecode` — any field) is reclassified to `source == .manual` by `UpdateCueUseCase`'s edit path and is therefore protected on re-run, per `SPEC.md` §4.11's "Re-running detection and manually-adjusted cues" and §4.3's reclassification rule — a `.detectedFromAudio` cue left untouched remains freely discardable.
- Manually verified: dragging a cue-boundary marker in `WaveformView` updates that cue's `startTimecode` (verified via the direct-field display in D10's `CueRowDetailView` once D10 exists, or via inspecting `Project.cues` state directly if verified before D10 lands) and does not move any neighboring cue's boundary (`SPEC.md` §4.19's no-ripple rule).

**Testing Requirements:** `DetectCuesUseCase` tested at the `ACCore` level against a fake `AudioAnalysisRepository`, per `CONTRIBUTING.md` §5. `CueDetectionViewModel` tested against `ACTestSupport` fakes. `WaveformView`'s interactive mode is verified via SwiftUI preview plus the manual acceptance criterion above — not unit tested, consistent with `ACDesignSystem` components generally (`CONTRIBUTING.md` §5); it's also a real candidate for D13's snapshot-testing layer once that Deliverable exists.

**Documentation Requirements:** None expected — implements `SPEC.md` §4.15/§4.19 as already specified.

**Suggested Commit Boundary:** 3 commits, one per Task — T9.3 is substantial enough (a new `ACDesignSystem` component plus its `ACFeatures` host view) to warrant its own commit, separate from T9.1/T9.2.

---

## D10 — Cue Sheet Editor

**Goal:** Full CRUD over cues and their right-holders, rendered performantly.

**Dependencies:** D9, D5 (for `CueTableView`'s design-system home).

**Tasks:**
- **T10.1 — CueSheetEditorViewModel** *(was M23)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/ViewModels/CueSheetEditorViewModel.swift`; `Packages/ACCore/Sources/ACCore/UseCases/UpdateCueUseCase.swift`. Add/delete/reorder write through to `ProjectRepository` immediately, never debounced (`SPEC.md` §4.18); field-level edits within a `Cue` remain debounced. Every edit-path mutation (any field) sets `source = .manual` per `SPEC.md` §4.3's reclassification rule. Delete also triggers `Setup.totalMusicRuntime`'s recompute per `SPEC.md` §4.14, and registers an inverse action with the environment `UndoManager` per `SPEC.md` §4.18 — no confirmation dialog.
- **T10.2 — CueTableView and editor screen** *(was M24)*. `Packages/ACDesignSystem/Sources/ACDesignSystem/Components/CueTableView.swift` (generic, `Identifiable`-row-based `Table`) with a delete control (✕ button) on each row's trailing edge, invoking `UpdateCueUseCase`'s delete path directly — no separate ad-hoc removal mechanism; and an "+ Add Cue" action creating a new `Cue` via the same Use Case's add path with `source: .manual` (`SPEC.md` §4.19). `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/Views/{CueSheetEditorView,CueRowDetailView}.swift` — `CueRowDetailView` includes a direct-edit text field for `Cue.startTimecode`, formatted/parsed via `Timecode`'s existing `HH:MM:SS:FF` formatting and `init?(components:frameRate:)` (`SPEC.md` §4.9, §4.19) — no new parsing/validation logic.
- **T10.3 — Right-holder editing per cue** *(was M25)*. `Packages/ACFeatures/Sources/ACFeatures/CueSheetEditor/Views/CueRightHolderEditorView.swift`.

**Acceptance Criteria:**
- Unit tests cover add/edit/delete/reorder of `Cue`s and of `CueRightHolder`s within a `Cue`; a test confirms add/delete/reorder write through to the fake repository *immediately* (not after a debounce delay), while a field-level edit (e.g. title text) is confirmed debounced — proving the distinction from `SPEC.md` §4.18 is actually implemented, not just documented.
- A test confirms `UpdateCueUseCase`'s delete path registers an inverse (re-insert) action with the fake/test `UndoManager`, and that invoking it restores the deleted `Cue` and its `[CueRightHolder]` entries at their original index.
- A test confirms `Setup.totalMusicRuntime` recomputes correctly per D2/T2.3's share-validation-adjacent rule and `SPEC.md` §4.14's update rule.
- Per-cue validation state is read from `ValidateCueRightHolderSharesUseCase` (D2/T2.3), not reimplemented in the view model.
- Manually verified: the ✕ button on a row deletes that cue with no confirmation prompt; ⌘Z immediately after restores it; a 100+ row cue sheet scrolls smoothly; editing one row's title/duration doesn't visibly re-render unrelated rows (checked via Xcode's SwiftUI render-count overlay).
- `CueTableView` takes no `ACCore` type as a generic parameter — only a design-system-local row protocol (`CLAUDE.md`, "Domain Model Value-Type Conformances" adapter pattern).
- Manually verified: add a cue via "+ Add Cue," confirm it appears with `source == .manual`; manually edit a `.detectedFromAudio` cue's title or timecode, confirm its provenance display updates to reflect `source == .manual` (`SPEC.md` §4.3).
- Manually verified: add multiple right-holders to a cue, assign role, pick or create a Person/Label, enter percentage shares; selecting `.publisher` prompts for `publishingContractAttached`; selecting `.arranger` on a work flagged as derivative prompts for `arrangementAuthorizationAttached`.

**Testing Requirements:** `CueSheetEditorViewModel` tested against `ACTestSupport` fakes, per `CONTRIBUTING.md` §5 — including the immediate-vs-debounced save-timing test and the undo-registration test specified above. `CueTableView` gets the snapshot-test consideration named in `CONTRIBUTING.md` §7 as a candidate — not required for this Deliverable, but flag it there if D13 hasn't landed yet.

**Documentation Requirements:** None expected — implements `SPEC.md` §4.18/§4.19 as already specified.

**Suggested Commit Boundary:** 3 commits, one per Task.

---

## D11 — Review & Export

**Goal:** Surface every outstanding validation issue and let the user export a compliant cue sheet as PDF and/or XLSX — as one combined, always-accessible "Review & Export" destination, never a modal sheet (`CLAUDE.md`, "Navigation Model").

**Dependencies:** D10, D6.

**Note on the XLSX feasibility question:** `CLAUDE.md` rule 4 requires validating a third-party dependency's App Sandbox compatibility and static-linkability before committing to it. This was originally scoped as part of the old M28 — i.e., after this Deliverable's other work. **It's already done**, ahead of schedule: `libxlsxwriter` has been verified to compile/link as an SPM C target, produce a valid workbook, and behave correctly under real, kernel-enforced App Sandbox (not just source review) — see `docs/DECISIONS.md`. T11.4 below builds the *real* writer on top of an already-cleared foundation, not an unverified assumption.

**Tasks:**
- **T11.1 — Validation summary and Review section** *(was M26)*. `Packages/ACCore/Sources/ACCore/UseCases/ValidateCueSheetUseCase.swift` (aggregates D2/T2.3's per-cue rule + Setup completeness); `Packages/ACFeatures/Sources/ACFeatures/ReviewAndExport/ViewModels/ReviewViewModel.swift`, `Views/ReviewView.swift`. A real, independently previewable/testable component — composed into the actual navigable screen in T11.5, not wired into navigation on its own yet.
- **T11.2 — CueSheetPageLayout and PDF export** *(was M27, expanded)*. `Packages/ACCore/Sources/ACCore/Models/{CueSheetPageLayout,CueSheetLayoutElement,LayoutRect}.swift` (`SPEC.md` §4.16); `Packages/ACExport/Sources/ACExport/PDF/PDFCueSheetRenderer.swift` + tests, matching the SUISA *WA Film* form layout (`SPEC.md` §2.1).
- **T11.3 — SUISA form revalidation checkpoint** *(new — `SPEC.md` §2.3)*. Before T11.2's layout work begins: re-verify the form is still `WA Film 2011-01`/`WA Film II 2011-01` against suisa.ch, confirm with `filmproduction@suisa.ch` if in doubt, and record the outcome in `docs/DECISIONS.md`. A real gate on T11.2, not an aspirational note.
- **T11.4 — XLSX export** *(was M28)*. `Packages/ACExport/Sources/ACExport/XLSX/XLSXCueSheetWriter.swift` (the real writer, wrapping `libxlsxwriter` — superseding the `XLSXFeasibilitySpike` scaffold, which was never the real feature; see the note above) + tests.
- **T11.5 — ExportRepositoryImpl and the combined Review & Export screen** *(was M29)*. `Packages/ACExport/Sources/ACExport/ExportRepositoryImpl.swift`; `Packages/ACCore/Sources/ACCore/UseCases/ExportCueSheetUseCase.swift`; `Packages/ACFeatures/Sources/ACFeatures/ReviewAndExport/ViewModels/{ReviewAndExportViewModel,ExportViewModel}.swift`, `Views/{ReviewAndExportView,ExportPanelView}.swift` — composes T11.1's `ReviewView` with export controls into the single always-accessible tab.

**Acceptance Criteria:**
- Unit tests confirm the aggregate use case reports every incomplete required field across Setup and Cues as a distinct, identifiable issue.
- **A test constructs `CueSheetEditorViewModel` (D10/T10.1) and `ReviewViewModel` (T11.1) against the same `ACTestSupport` fake `ProjectRepository` instance, both subscribed to its live-observation stream; deletes a cue via `CueSheetEditorViewModel`; and asserts `ReviewViewModel`'s observed validation state updates to reflect the deletion — awaiting the stream's next emission, never calling an explicit refresh method on either ViewModel.** This is the concrete verification for `SPEC.md` §4.18's "no manual refresh" claim — proven at the ViewModel level, not just asserted by architecture.
- **T11.3 is completed and recorded in `docs/DECISIONS.md` before T11.2's layout work begins** — do not skip this gate.
- Rendering a fixture `Project` with more than 5 cues produces a multi-page PDF whose pagination matches the form (5 works per main page, continuation pages thereafter); visually checked against the sourced SUISA form for field placement; layout is computed once via `CueSheetPageLayout` and drawn by `PDFCueSheetRenderer`, with the on-screen preview View drawing the identical computed layout, never an independently-derived one.
- Writing a fixture `Project` produces a valid `.xlsx` opening in Numbers/Excel: one row per Cue × right-holder, Setup header fields present; a round-trip test reads the generated file back and asserts cell values match the fixture.
- Export is blocked or warned per `Settings.shareValidationStrictness` when validation issues remain.
- Manually verified: the "Review & Export" tab is reachable at any time a project is open, never gated behind presenting a sheet; choose PDF/XLSX/both, pick a destination via `NSSavePanel`, export completes with progress, resulting file(s) open correctly outside the app.

**Testing Requirements:** `ValidateCueSheetUseCase`/`ExportCueSheetUseCase` at the `ACCore` level; `ACExport` renderers tested against real fixture output files (a real generated PDF/XLSX, not a mock), per `CONTRIBUTING.md` §5. `ReviewAndExportViewModel` against `ACTestSupport` fakes.

**Documentation Requirements:** `docs/DECISIONS.md` gets T11.3's revalidation-outcome entry regardless of result. If the real `CueSheetPageLayout.LayoutElementContent` case set ends up different from `SPEC.md` §4.16's sketch, update §4.16 in the same change — that section explicitly deferred the exact shape to this Deliverable.

**Suggested Commit Boundary:** Several commits, not one — T11.3 (revalidation, docs-only) first; T11.1 (Review) next since it's independently testable; T11.2 (layout + PDF) as its own commit given its size; T11.4 (XLSX) as its own commit; T11.5 (composition/wiring) last, once both renderers exist.

---

## D12 — End-to-End Integration & Performance Validation

**Goal:** Prove the full pipeline works together and scales to a real 3-hour file.

**Dependencies:** D11 (needs every prior Deliverable's real implementation to exercise end-to-end).

**Tasks:**
- **T12.1 — Full-pipeline integration test** *(was M30)*. `Packages/ACCore/Tests/ACCoreIntegrationTests/` (new test target): Import → Detect → Edit → Validate → Export exercised against one realistic long WAV fixture.
- **T12.2 — Long-file performance validation** *(was part of M30)*. A performance test measuring peak memory during import/analysis against a 3-hour-equivalent (real or documented synthetic-proxy) WAV file.

**Acceptance Criteria:**
- One automated test exercises the full pipeline end-to-end and passes.
- A performance test against a 3-hour-equivalent WAV file confirms peak memory stays under a defined budget and total processing time is within a stated target.

**Testing Requirements:** This Deliverable *is* the testing requirement — no separate note needed beyond the two Tasks above.

**Documentation Requirements:** If the performance test reveals the "never load a full WAV into memory" constraint (`CLAUDE.md`, Performance Considerations) needs a more precise stated budget than currently written, add specific numbers there in the same change.

**Suggested Commit Boundary:** 1–2 commits — this Deliverable is naturally small and cohesive.

---

## D13 — UI/Integration Test Automation

**Goal:** Automate the golden path through the app end-to-end, closing the "zero automated UI coverage" gap named in `CONTRIBUTING.md` §7 — a small, deliberately limited layer on top of (never instead of) the unit-test layer everything else in this roadmap already requires.

**Dependencies:** D11 (the full Setup → Cues → Review & Export path must exist to automate it), D6 (multi-window duplicate-open behavior is also a candidate flow here).

**Tasks:**
- **T13.1 — Golden-path XCUITest**. Automates: create a project → fill every required `Setup` field → import a fixture WAV → run cue detection → confirm `Cue`s populate → navigate to Review & Export → confirm "ready to export" → trigger a PDF export → confirm the file is produced. Per `CONTRIBUTING.md` §7.
- **T13.2 — Duplicate-open-prevention XCUITest**. Automates: open a Project window, attempt to open the same Project again from the Library, confirm the existing window is focused rather than a duplicate created (D6/T6.1's `OpenProjectWindowRegistry`).
- **T13.3 — Snapshot tests for `CueTableView` and `WaveformView`**. Per `CONTRIBUTING.md` §7's narrower snapshot-testing scope — these two components specifically, not a general snapshot-testing sweep across every View.

**Acceptance Criteria:**
- T13.1 passes reliably in CI (not flaky — a UI test that fails intermittently is worse than no UI test, since it trains reviewers to ignore red CI).
- T13.2 passes and genuinely exercises the focus-not-duplicate path, not just the happy path of opening one window.
- T13.3's snapshots are committed as reference images and CI fails on a genuine visual diff.

**Testing Requirements:** This Deliverable *is* the testing requirement. Keep it to exactly the flows named in `CONTRIBUTING.md` §7 — resist scope creep into "UI-test everything," which that section explicitly rejects.

**Documentation Requirements:** None expected, unless building this reveals the golden-path flow described in `CONTRIBUTING.md` §7 doesn't match the real app (e.g., a step got reordered) — correct that section in the same change.

**Suggested Commit Boundary:** 3 commits, one per Task.

---

## D14 — Settings

**Goal:** Make the `Settings` model (`SPEC.md` §4.7) user-editable instead of relying on hardcoded defaults.

**Dependencies:** D4 (persistence), D8 (`AnalysisSettings` defaults must exist to be editable), D11 (`shareValidationStrictness`/export-language affect export behavior already built there).

**Tasks:**
- **T14.1 — Settings repository** *(was part of M31)*. `Packages/ACCore/Sources/ACCore/RepositoryProtocols/SettingsRepository.swift`; `Packages/ACPersistence/Sources/ACPersistence/SettingsRepositoryImpl.swift`.
- **T14.2 — Settings screen** *(was part of M31)*. `Packages/ACFeatures/Sources/ACFeatures/Settings/ViewModels/SettingsViewModel.swift`, `Views/SettingsView.swift` — the root view for the `Settings` scene declared in D6/T6.1.

**Acceptance Criteria:**
- Unit tests cover `SettingsViewModel`.
- Manually verified: changing `exportLanguage`, `shareValidationStrictness`, `audioAnalysisDefaults` fields, etc. persists and is respected by subsequent analysis/export runs in the same session.

**Testing Requirements:** `SettingsViewModel` against `ACTestSupport` fakes; `SettingsRepositoryImpl` against a real in-memory `ModelContainer`, per `CONTRIBUTING.md` §5.

**Documentation Requirements:** None expected.

**Suggested Commit Boundary:** 2 commits, one per Task.

---

## D15 — App Store Packaging

**Goal:** Prepare the build for distribution.

**Dependencies:** D12 (should be functionally complete and validated before packaging for distribution).

**Tasks:**
- **T15.1 — App icon, entitlements, and packaging metadata** *(was M32)*. `Assets.xcassets/AppIcon`, `AutoCue.entitlements` (final pass), `Info.plist`, project versioning settings.
- **T15.2 — Real `NSSavePanel`-write sandbox confirmation** *(new — closes a residual gap from the XLSX validation, see `docs/DECISIONS.md`)*. Confirm the export flow's actual `NSSavePanel`-granted write (Powerbox-mediated, dynamic access to a user-chosen destination) works correctly under the app's final, real entitlements — the earlier `libxlsxwriter` verification only tested the baseline sandbox-container-write case.

**Acceptance Criteria:**
- App builds and runs fully sandboxed with no runtime sandbox violations.
- App icon present at all required sizes; version/build numbers set.
- A local `xcodebuild -exportArchive` with the App Store method succeeds.
- A real export via `NSSavePanel` to a user-chosen location (outside the app's sandbox container) succeeds with the final entitlements — T15.2's confirmation, recorded in `docs/DECISIONS.md` as closing that residual gap.

**Testing Requirements:** Manual verification per the acceptance criteria above — packaging/entitlements aren't unit-testable in a meaningful way.

**Documentation Requirements:** `docs/DECISIONS.md`'s `libxlsxwriter` entry updated to close its residual-gap note once T15.2 confirms the real save-panel flow.

**Suggested Commit Boundary:** 1–2 commits.

---

## D16 — Accessibility & Keyboard Navigation

**Goal:** Make the full workflow usable via VoiceOver and keyboard alone.

**Dependencies:** D15 (functionally complete app to retrofit accessibility onto — though see the note below).

**Tasks:**
- **T16.1 — Accessibility labels and keyboard shortcuts** *(was M33)*. Touch-ups across `Packages/ACFeatures/*/Views` and `ACDesignSystem` components (accessibility labels, keyboard shortcuts for new project / import audio / run detection / export).

**Acceptance Criteria:**
- VoiceOver can navigate the full Setup → Cue Sheet → Review & Export flow.
- Every primary action has a discoverable keyboard shortcut (visible in the menu bar).

**Testing Requirements:** Manual verification (VoiceOver walkthrough) — not meaningfully unit-testable. Consider extending D13's `XCUITest` golden path with accessibility-identifier-based assertions if this Deliverable reveals a regression risk worth guarding automatically; not required.

**Documentation Requirements:** None expected.

**Suggested Commit Boundary:** 1 commit — this is inherently a sweep across many files, not naturally splittable by concern.

---

## D17 — Final Polish

**Goal:** Close remaining rough edges before calling v1 done.

**Dependencies:** D16.

**Tasks:**
- **T17.1 — Empty/loading/error state sweep** *(was M34)*. Sweep across `Packages/ACFeatures/*` and `ACDesignSystem`.

**Acceptance Criteria:**
- Every screen has a defined empty, loading, and error state — no blank screens possible.
- `Scripts/check-color-literals.sh` (CI, since D1) finds no raw color/font literals outside `ACDesignSystem/Theme` — this is now a standing CI check, not a one-time grep at the end of the roadmap.
- A full manual walkthrough from empty app to exported PDF/XLSX surfaces no rough edges.

**Testing Requirements:** Manual walkthrough per the acceptance criteria; no new automated coverage expected specifically for this Deliverable.

**Documentation Requirements:** A final `docs/REVIEW.md` entry summarizing the whole v1 build — not just this Deliverable — is a reasonable close-out, though not a hard requirement of this Deliverable specifically.

**Suggested Commit Boundary:** 1 commit, or a small handful if the sweep naturally splits by screen.
