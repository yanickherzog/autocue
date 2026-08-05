# AutoCue — Roadmap

Each milestone is scoped to fit in one Claude Code session: one coherent vertical slice, compiling and tested on its own. Work sequentially — later milestones assume every earlier one is done unless a milestone says otherwise. Every milestone's definition of done implicitly includes: builds clean, existing tests still pass, and `CLAUDE.md`/`SPEC.md` are updated in the same session if the milestone changes architecture or schema (per `CLAUDE.md` rule 8).

Commit messages follow Conventional Commits, matching the style already implied by `CLAUDE.md`/`SPEC.md`'s own framing.

## Overview

| Phase | Milestones |
|---|---|
| 1. Foundation — Domain Models | M1–M6 |
| 2. Foundation — Persistence | M7–M8 |
| 3. Foundation — Design System | M9–M10 |
| 4. App Shell & Project Library | M11–M12 |
| 5. Setup | M13–M15 |
| 6. Audio Analysis | M16–M20 |
| 7. Cue Detection | M21–M22 |
| 8. Cue Sheet (Editor) | M23–M25 |
| 9. Review | M26 |
| 10. Export | M27–M29 |
| 11. Testing | M30 |
| 12. Polish | M31–M34 |

Phases 4 and parts of 12 (M31) aren't named in the original phase list but are necessary connective work — an app shell to hold the Setup screen, and a Settings screen for the `Settings` model defined in `SPEC.md` §4.7 — so they're placed where they're structurally needed.

---

## Phase 1 — Foundation: Domain Models

### M1 — Workspace & package scaffolding
**Goal:** Create the Xcode workspace, thin app target, and empty local SPM packages wired together per `CLAUDE.md`'s folder structure, so every later milestone has a compilable home.
**Files:**
- `AutoCue.xcworkspace`
- `AutoCue/AutoCueApp.swift`, `AppState.swift`, `DependencyContainer.swift` (placeholders)
- `Packages/{ACCore,ACAudioKit,ACExport,ACPersistence,ACDesignSystem,ACTestSupport}/Package.swift` + one placeholder source file and one placeholder test each
- `.gitignore` (Xcode/SPM)
**Dependencies:** None
**Acceptance criteria:**
- `xcodebuild -scheme AutoCue build` succeeds
- App launches to an empty window
- Every package target builds and its placeholder test passes
**Commit:** `chore: scaffold Xcode workspace and local SPM package structure`

### M2 — Core value types
**Goal:** Implement the shared value types every domain model depends on.
**Files:** `Packages/ACCore/Sources/ACCore/Models/{Duration,Timecode,PostalAddress,Party}.swift` + tests
**Dependencies:** M1
**Acceptance criteria:**
- Unit tests cover `hh:mm:ss` formatting, arithmetic, equality, and `Codable` round-trip for each type
- No import beyond `Foundation` anywhere in `ACCore`
**Commit:** `feat(core): add Duration, Timecode, PostalAddress, and Party value types`

### M3 — Person and Label models
**Goal:** Implement individual and corporate right-holder identity.
**Files:** `Models/{Person,Label}.swift` + tests
**Dependencies:** M2
**Acceptance criteria:**
- `Codable` round-trip tests pass for both types
- `Identifiable` conformance present
- A tested helper distinguishes "has complete address" (all four `PostalAddress` parts present) per `SPEC.md` §4.5
**Commit:** `feat(core): add Person and Label right-holder models`

### M4 — Setup model
**Goal:** Implement the production-level header per `SPEC.md` §4.2.
**Files:** `Models/Setup.swift`, `Models/ProductionType.swift`, `Models/AttachmentType.swift` + tests
**Dependencies:** M2, M3
**Acceptance criteria:**
- `Codable` round-trip test passes
- Every field listed as required in `SPEC.md` §4.2 has no default value that could silently satisfy it
- `ProductionType`/`AttachmentType` enum cases match `SPEC.md` §4.2.1/4.2.2 exactly
**Commit:** `feat(core): add Setup model and production/attachment classification enums`

### M5 — Cue, CueRightHolder, and share validation
**Goal:** Implement the per-work entity and its rights-share validation rule from `SPEC.md` §4.3–4.6.
**Files:** `Models/Cue.swift`, `Models/CueRightHolder.swift`, `UseCases/ValidateCueRightHolderSharesUseCase.swift` + tests
**Dependencies:** M2, M3
**Acceptance criteria:**
- Unit tests prove the 100%-sum rule is checked independently for `performanceBroadcastShare` and `mechanicalRightsShare`
- Unit tests prove `publishingContractAttached`/`arrangementAuthorizationAttached` are flagged as missing only when their triggering role/condition applies
- `Cue` `Codable` round-trip test passes
**Commit:** `feat(core): add Cue and CueRightHolder models with share validation`

### M6 — AudioAsset, Settings, Project, and repository protocols
**Goal:** Compose the top-level container and declare the Data-layer boundaries.
**Files:** `Models/{AudioAsset,Settings,Project}.swift`, `RepositoryProtocols/{ProjectRepository,AudioAnalysisRepository,ExportRepository}.swift` + tests; `Packages/ACTestSupport/Sources/ACTestSupport/Fakes/InMemory{ProjectRepository,AudioAnalysisRepository,ExportRepository}.swift`
**Dependencies:** M3, M4, M5
**Acceptance criteria:**
- `Project` composes `Setup`, `[Cue]`, `[Person]`, `[Label]`, `AudioAsset`; round-trips via `Codable`
- A grep check confirms no Apple framework (beyond `Foundation`) is imported anywhere in `ACCore`
- In-memory fake implementations of all three protocols exist in `ACTestSupport` and pass a basic CRUD smoke test
**Commit:** `feat(core): add Project, Settings, AudioAsset models and repository protocols`

---

## Phase 2 — Foundation: Persistence

### M7 — SwiftData schema and mappers
**Goal:** Persist the domain model without leaking persistence details into `ACCore`.
**Files:** `Packages/ACPersistence/Sources/ACPersistence/SwiftDataModels/*Entity.swift` (Project, Setup, Cue, CueRightHolder, Person, Label, Settings), `Mappers/*.swift`; `Package.swift` updated with `SwiftData` + `ACCore` deps; tests
**Dependencies:** M6
**Acceptance criteria:**
- A round-trip test builds a domain `Project` fixture, maps it to entities, inserts into an in-memory `ModelContainer`, fetches back, maps to domain, and asserts equality
- No domain type is referenced directly by a `@Model` class's persisted properties — only via the mapper
**Commit:** `feat(persistence): add SwiftData schema and domain mappers for Project`

### M8 — ProjectRepositoryImpl
**Goal:** Implement the `ProjectRepository` protocol against SwiftData.
**Files:** `Packages/ACPersistence/Sources/ACPersistence/ProjectRepositoryImpl.swift` + tests
**Dependencies:** M7
**Acceptance criteria:**
- CRUD (create, fetch all, fetch by id, update, delete) tested against an in-memory container
- Conforms to `ACCore.ProjectRepository` with no additional public API surface
**Commit:** `feat(persistence): implement ProjectRepository backed by SwiftData`

---

## Phase 3 — Foundation: Design System

### M9 — Design tokens
**Goal:** Define the shared visual language before any screen exists.
**Files:** `Packages/ACDesignSystem/Sources/ACDesignSystem/Theme/{Colors,Typography,Spacing}.swift` + a preview file
**Dependencies:** M1
**Acceptance criteria:**
- Package builds for the macOS target
- Every color/font token uses semantic, dark-mode-safe definitions (no hardcoded hex without a dark variant)
- A SwiftUI preview renders a token swatch sheet in both appearances
**Commit:** `feat(design-system): add color, typography, and spacing tokens`

### M10 — Core reusable components
**Goal:** Build the first feature-agnostic components other milestones will reuse.
**Files:** `Components/{EmptyStateView,ProgressBanner}.swift`, `Modifiers/ErrorAlertModifier.swift`
**Dependencies:** M9
**Acceptance criteria:**
- Each component has a SwiftUI preview with representative sample data in both appearances
- None of these files import `ACCore` or reference any domain type — only `String`/closures/bindings
**Commit:** `feat(design-system): add EmptyStateView, ProgressBanner, and error-alert modifier`

---

## Phase 4 — App Shell & Project Library

### M11 — Dependency container and app shell
**Goal:** Give the app a real window and a single place where concrete services are wired.
**Files:** `AutoCue/DependencyContainer.swift` (real wiring), `AutoCueApp.swift` (`NavigationSplitView` shell, injects container via `Environment`), `AppState.swift` (selected project id), `AutoCue.entitlements` (App Sandbox on)
**Dependencies:** M8, M10
**Acceptance criteria:**
- App launches showing an empty sidebar + placeholder detail pane
- A grep check confirms `ProjectRepositoryImpl` is constructed only inside `DependencyContainer`
- App runs under App Sandbox with no violations in Console
**Commit:** `feat(app): wire dependency container and add NavigationSplitView app shell`

### M12 — Project Library feature
**Goal:** Let the user create, list, select, and delete projects.
**Files:** `Features/ProjectLibrary/ViewModels/ProjectLibraryViewModel.swift`, `Views/ProjectLibraryView.swift`, `Components/ProjectRow.swift`
**Dependencies:** M11
**Acceptance criteria:**
- Manually verified: create a named project, see it listed, select it (updates `AppState.selectedProjectID`), delete it
- List reflects the repository live (via `@Query` or equivalent) — no stale state after create/delete in the same session
**Commit:** `feat(project-library): add project creation, listing, and deletion`

---

## Phase 5 — Setup

### M13 — Setup view model and use case
**Goal:** Make `Setup` editable with persistence and validation plumbing, no UI yet.
**Files:** `Packages/ACCore/Sources/ACCore/UseCases/UpdateSetupUseCase.swift`; `Features/CueSheetEditor/ViewModels/SetupViewModel.swift`
**Dependencies:** M12, M4
**Acceptance criteria:**
- Unit tests (against `ACTestSupport`'s fake repository) verify editing any `Setup` field triggers a debounced save
- Missing-required-field state is exposed as a published property, not computed ad hoc in a view
**Commit:** `feat(setup): add Setup editing view model and update use case`

### M14 — Setup view
**Goal:** Build the first real screen.
**Files:** `Features/CueSheetEditor/Views/SetupView.swift`, `ProductionTypePicker.swift`, `PostalAddressFields.swift`
**Dependencies:** M13, M10
**Acceptance criteria:**
- Manually verified: every required `Setup` field is editable, unmet-required fields are visibly indicated, `productionTypes` multi-select works, edits persist across app relaunch
**Commit:** `feat(setup): add Setup editor view`

### M15 — Right-holder directory and party picker
**Goal:** Let Setup's `producer`/`directorOrPrincipal`/`declarant` fields reference `Person`/`Label` entries, creatable inline.
**Files:** `Features/CueSheetEditor/ViewModels/RightHolderDirectoryViewModel.swift`, `Views/{PersonEditorSheet,LabelEditorSheet,PartyPickerView}.swift`
**Dependencies:** M14
**Acceptance criteria:**
- Unit tests cover add/edit/remove logic in the view model
- Manually verified: picking a producer offers "create new Person/Label" inline, and the picker lists the project's existing directory
**Commit:** `feat(setup): add Person/Label directory management and party picker`

---

## Phase 6 — Audio Analysis

### M16 — WAV streaming reader
**Goal:** Read WAV files in bounded chunks, never fully in memory.
**Files:** `Packages/ACAudioKit/Sources/ACAudioKit/Streaming/WAVStreamingReader.swift` + tests with a small fixture WAV
**Dependencies:** M1
**Acceptance criteria:**
- Reports sample rate, channel count, bit depth, and duration correctly for the fixture
- A test asserts multiple chunk callbacks occur for a file larger than one chunk (proves it isn't loading the whole file at once)
**Commit:** `feat(audio-kit): add streaming WAV reader`

### M17 — RIFF/BWF chunk parser
**Goal:** Extract embedded cue markers and broadcast-wave metadata AVFoundation doesn't expose.
**Files:** `Packages/ACAudioKit/Sources/ACAudioKit/WAVParsing/{RIFFChunkParser,BroadcastWaveMetadata}.swift` + tests with a fixture WAV containing `cue`/`labl`/`ltxt`/`bext` chunks
**Dependencies:** M16
**Acceptance criteria:**
- Parser extracts all marker entries with sample-accurate positions from the fixture
- Returns an empty result (not a crash or throw) for a WAV with none of these chunks
**Commit:** `feat(audio-kit): add RIFF/BWF chunk parser for embedded cue markers`

### M18 — Silence/level analysis
**Goal:** Detect candidate cue boundaries via signal analysis, fast enough for hour-long files.
**Files:** `Packages/ACAudioKit/Sources/ACAudioKit/Analysis/SilenceDetector.swift` (vDSP-based) + tests
**Dependencies:** M16
**Acceptance criteria:**
- Given a synthetic buffer with known silent/loud regions, detected boundaries fall within a defined sample tolerance
- A performance test analyzing a ~10-minute synthetic buffer completes within a documented time budget, validating the approach scales toward 3 hours
**Commit:** `feat(audio-kit): add vDSP-based silence and level detection`

### M19 — AudioAnalysisRepositoryImpl and import use case
**Goal:** Wire streaming, parsing, and detection behind the `ACCore` protocol.
**Files:** `Packages/ACAudioKit/Sources/ACAudioKit/AudioAnalysisRepositoryImpl.swift`; `Packages/ACCore/Sources/ACCore/UseCases/ImportAudioUseCase.swift`; `DependencyContainer` update
**Dependencies:** M17, M18, M6
**Acceptance criteria:**
- `loadAsset(from:)` returns a populated `AudioAsset` (including embedded markers) for the fixture file
- Progress is emitted via `AsyncStream`/`Progress` with at least start/intermediate/complete events for a multi-chunk file
**Commit:** `feat(audio-kit): implement AudioAnalysisRepository and audio import use case`

### M20 — Audio import UI
**Goal:** Let the user attach a WAV file to a project from the app.
**Files:** `Features/CueSheetEditor/ViewModels/AudioImportViewModel.swift`, `Views/AudioImportView.swift`
**Dependencies:** M19, M11
**Acceptance criteria:**
- Manually verified with a real multi-minute WAV file via `fileImporter`: progress updates without blocking the UI, resulting `AudioAsset` is persisted on the project
- Security-scoped bookmark is stored and file access survives an app relaunch (required under App Sandbox)
**Commit:** `feat(audio-import): add WAV file import UI with progress reporting`

---

## Phase 7 — Cue Detection

### M21 — DetectCuesUseCase
**Goal:** Turn raw analysis output into `Cue` entities.
**Files:** `Packages/ACCore/Sources/ACCore/UseCases/DetectCuesUseCase.swift` + tests
**Dependencies:** M19, M5
**Acceptance criteria:**
- Unit tests (against a fixture-backed fake `AudioAnalysisRepository`) verify: embedded markers become `Cue`s with `source == .embeddedMarker`; silence-detected gaps fill in as `.detectedFromAudio`; overlapping detections within a configurable tolerance are deduplicated rather than double-counted
**Commit:** `feat(core): add DetectCuesUseCase merging embedded markers and silence detection`

### M22 — Cue detection UI
**Goal:** Let the user trigger detection and see it complete without blocking the app.
**Files:** `Features/CueSheetEditor/ViewModels/CueDetectionViewModel.swift`, `Views/CueDetectionProgressView.swift`
**Dependencies:** M21, M10
**Acceptance criteria:**
- Manually verified on a long (multi-hour-class) file: UI stays responsive throughout, progress is visible, `Project.cues` populates on completion
- Re-running detection warns before discarding any `Cue` not sourced as `.detectedFromAudio` (i.e., manual edits and embedded markers are protected)
**Commit:** `feat(cue-detection): add cue detection trigger UI with progress reporting`

---

## Phase 8 — Cue Sheet (Editor)

### M23 — CueSheetEditorViewModel
**Goal:** Full CRUD over cues and their right-holders, single source of truth for the editing screen.
**Files:** `Features/CueSheetEditor/ViewModels/CueSheetEditorViewModel.swift`; `Packages/ACCore/Sources/ACCore/UseCases/UpdateCueUseCase.swift` (add/edit/delete/reorder)
**Dependencies:** M22, M5
**Acceptance criteria:**
- Unit tests cover add/edit/delete/reorder of `Cue`s and of `CueRightHolder`s within a `Cue`, with debounced autosave through the fake repository
- Per-cue validation state is read from `ValidateCueRightHolderSharesUseCase` (M5), not reimplemented in the view model
**Commit:** `feat(cue-sheet): add CueSheetEditorViewModel with cue and right-holder CRUD`

### M24 — CueTableView and editor screen
**Goal:** Render the cue list performantly.
**Files:** `Packages/ACDesignSystem/Sources/ACDesignSystem/Components/CueTableView.swift` (generic, `Identifiable`-row-based `Table`); `Features/CueSheetEditor/Views/{CueSheetEditorView,CueRowDetailView}.swift`
**Dependencies:** M23, M10
**Acceptance criteria:**
- Manually verified: a 100+ row cue sheet scrolls smoothly; editing one row's title/duration doesn't visibly re-render unrelated rows (checked via Xcode's SwiftUI render-count overlay)
- `CueTableView` takes no `ACCore` type as a generic parameter — only a design-system-local row protocol
**Commit:** `feat(cue-sheet): add CueTableView component and cue sheet editor screen`

### M25 — Right-holder editing per cue
**Goal:** Complete the cue-sheet data entry loop for rights/shares.
**Files:** `Features/CueSheetEditor/Views/CueRightHolderEditorView.swift`
**Dependencies:** M24, M15
**Acceptance criteria:**
- Manually verified: add multiple right-holders to a cue, assign role, pick or create a Person/Label, enter percentage shares
- Selecting `.publisher` prompts for `publishingContractAttached`; selecting `.arranger` on a work flagged as derivative prompts for `arrangementAuthorizationAttached`
**Commit:** `feat(cue-sheet): add per-cue right-holder editing with role and share inputs`

---

## Phase 9 — Review

### M26 — Validation summary and Review screen
**Goal:** Surface every outstanding issue across Setup and all Cues in one place before export.
**Files:** `Packages/ACCore/Sources/ACCore/UseCases/ValidateCueSheetUseCase.swift` (aggregates M5's per-cue rule + Setup completeness); `Features/CueSheetEditor/ViewModels/ReviewViewModel.swift`, `Views/ReviewView.swift`
**Dependencies:** M23, M14
**Acceptance criteria:**
- Unit tests confirm the aggregate use case reports every incomplete required field across Setup and Cues as a distinct, identifiable issue
- Manually verified: clicking an issue navigates to the offending field; a fully valid project shows a clear "ready to export" state
**Commit:** `feat(review): add cue-sheet validation summary and review screen`

---

## Phase 10 — Export

### M27 — PDF export
**Goal:** Produce a PDF matching the SUISA *WA Film* form layout (`SPEC.md` §2.1).
**Files:** `Packages/ACExport/Sources/ACExport/PDF/PDFCueSheetRenderer.swift` + tests
**Dependencies:** M6
**Acceptance criteria:**
- Rendering a fixture `Project` with more than 5 cues produces a multi-page PDF whose pagination matches the form (5 works per main page, continuation pages thereafter)
- Visually checked against the sourced SUISA form for field placement
**Commit:** `feat(export): add PDF cue-sheet renderer matching the SUISA form layout`

### M28 — XLSX export
**Goal:** Produce a tabular export for internal use and re-editing.
**Files:** `Packages/ACExport/Sources/ACExport/XLSX/XLSXCueSheetWriter.swift` (wraps `libxlsxwriter`); `Package.swift` updated with the C target; tests
**Dependencies:** M6
**Acceptance criteria:**
- Writing a fixture `Project` produces a valid `.xlsx` opening in Numbers/Excel: one row per Cue × right-holder, Setup header fields present
- A round-trip test reads the generated file back (e.g., via CoreXLSX) and asserts cell values match the fixture
**Commit:** `feat(export): add XLSX cue-sheet writer using libxlsxwriter`

### M29 — ExportRepositoryImpl and Export UI
**Goal:** Wire both renderers behind the protocol and let the user trigger an export.
**Files:** `Packages/ACExport/Sources/ACExport/ExportRepositoryImpl.swift`; `Packages/ACCore/Sources/ACCore/UseCases/ExportCueSheetUseCase.swift`; `Features/Export/ViewModels/ExportViewModel.swift`, `Views/ExportSheetView.swift`
**Dependencies:** M27, M28, M26
**Acceptance criteria:**
- Export is blocked or warned per `Settings.shareValidationStrictness` when validation issues remain
- Manually verified: choose PDF/XLSX/both, pick a destination via `NSSavePanel`, export completes with progress, resulting file(s) open correctly outside the app
**Commit:** `feat(export): wire export use case, repository, and export UI`

---

## Phase 11 — Testing

### M30 — End-to-end integration and performance validation
**Goal:** Prove the full pipeline works together and scales to a real 3-hour file.
**Files:** `Packages/ACCore/Tests/ACCoreIntegrationTests/` (new test target): Import → Detect → Edit → Validate → Export exercised against one realistic long WAV fixture; a performance test measuring peak memory during import/analysis
**Dependencies:** M29
**Acceptance criteria:**
- One automated test exercises the full pipeline end-to-end and passes
- A performance test against a 3-hour-equivalent (real or documented synthetic-proxy) WAV file confirms peak memory stays under a defined budget and total processing time is within a stated target
**Commit:** `test: add end-to-end pipeline integration test and long-file performance validation`

---

## Phase 12 — Polish

### M31 — Settings persistence and screen
**Goal:** Make the `Settings` model (`SPEC.md` §4.7) user-editable instead of relying on hardcoded defaults.
**Files:** `Packages/ACCore/Sources/ACCore/RepositoryProtocols/SettingsRepository.swift`; `Packages/ACPersistence/Sources/ACPersistence/SettingsRepositoryImpl.swift`; `Features/Settings/ViewModels/SettingsViewModel.swift`, `Views/SettingsView.swift`
**Dependencies:** M7, M18, M29
**Acceptance criteria:**
- Unit tests cover `SettingsViewModel`
- Manually verified: changing `exportLanguage`, `shareValidationStrictness`, `silenceThresholdDb`, etc. persists and is respected by subsequent analysis/export runs in the same session
**Commit:** `feat(settings): add settings persistence and preferences screen`

### M32 — App icon, entitlements, and App Store packaging
**Goal:** Prepare the build for distribution.
**Files:** `Assets.xcassets/AppIcon`, `AutoCue.entitlements` (final pass), `Info.plist`, project versioning settings
**Dependencies:** M30
**Acceptance criteria:**
- App builds and runs fully sandboxed with no runtime sandbox violations
- App icon present at all required sizes; version/build numbers set
- A local `xcodebuild -exportArchive` with the App Store method succeeds
**Commit:** `chore: add app icon, entitlements, and App Store packaging metadata`

### M33 — Accessibility and keyboard navigation
**Goal:** Make the full workflow usable via VoiceOver and keyboard alone.
**Files:** touch-ups across `Features/*/Views` and `ACDesignSystem` components (accessibility labels, keyboard shortcuts for new project / import audio / run detection / export)
**Dependencies:** M32
**Acceptance criteria:**
- VoiceOver can navigate the full Setup → Cue Sheet → Export flow
- Every primary action has a discoverable keyboard shortcut (visible in the menu bar)
**Commit:** `polish: add accessibility labels and keyboard shortcuts across the app`

### M34 — Final UI/UX polish pass
**Goal:** Close remaining rough edges before calling v1 done.
**Files:** sweep across `Features/*` and `ACDesignSystem`
**Dependencies:** M33
**Acceptance criteria:**
- Every screen has a defined empty, loading, and error state — no blank screens possible
- A grep check finds no raw color/font literals outside `ACDesignSystem/Theme`
- A full manual walkthrough from empty app to exported PDF/XLSX surfaces no rough edges
**Commit:** `polish: finalize empty/loading/error states and visual consistency pass`
