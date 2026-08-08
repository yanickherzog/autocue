# CLAUDE.md

Permanent project memory for Claude Code. Read this before making any architectural, structural, or dependency decision in this repository. If a change conflicts with something written here, stop and raise it rather than silently deviating.

**This file answers *how* the software should be built** — architecture, module boundaries, conventions. It does not define *what* the product does (`SPEC.md`), *when* things get built (`ROADMAP.md`), *how* day-to-day development is performed (`CONTRIBUTING.md`), *why* a specific call was made (`docs/DECISIONS.md`), or *when* something counts as finished (`docs/DefinitionOfDone.md`). If you're about to add content here that actually belongs in one of those, put it there instead — see `README.md`'s documentation map for the full picture.

## Project Overview

**AutoCue** (working title) is a native macOS application that generates film/TV cue sheets automatically from WAV audio files. It parses embedded audio metadata and performs signal analysis to detect cues, then produces formatted, exportable cue sheets.

Core constraints that shape every decision below:
- Must run fully offline — no network dependency anywhere in the pipeline.
- Must handle WAV files up to ~3 hours (multi-GB) without loading them fully into memory.
- Must stay App Store-eligible (sandboxed, no disallowed APIs, no dynamically loaded code).
- Must remain maintainable by a small team long-term — prefer fewer, well-separated moving parts over cleverness.
- Minimum deployment target: macOS 14.0 (Sonoma) — see "Deployment Target," below, for why.

## Technology Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift | Single language across the whole app — no bridge layers |
| UI | SwiftUI (AppKit interop only when SwiftUI has a genuine gap) | `NavigationSplitView` as each Project window's shell; multi-window overall — see "Navigation Model" and "Document & Window Model" below |
| State | `@Observable` (Observation framework) | Not legacy `ObservableObject`/`@Published` — finer-grained view invalidation |
| Concurrency | Swift Concurrency (async/await, actors, `AsyncThrowingStream`) | No GCD/completion-handler code in new work. Progress/cancellation is `AsyncThrowingStream`-based project-wide, never Foundation's `Progress` — see "Long-Running Operations: Progress & Cancellation" below; this row previously listed both ambiguously, which was itself a finding this document corrects |
| Audio I/O | `AVFoundation` (`AVAudioFile`) + a custom RIFF/BWF chunk parser | AVFoundation streams; the custom parser reads `cue`/`labl`/`ltxt`/`bext` chunks it doesn't expose |
| DSP | `Accelerate` (vDSP) | Required for silence/level detection *and* waveform peak extraction to stay fast over hours of audio — see SPEC.md §4.15 |
| Persistence | `SwiftData` | Source of truth for all persisted project data |
| PDF export | Core Graphics (`PDFContext`) + Core Text for **generation**; `PDFKit` for in-app **preview only** | `PDFKit` (`PDFDocument`/`PDFView`) is a viewing/annotation framework, not a generation mechanism — it cannot produce the SUISA form's pixel-accurate layout. An earlier version of this table listed `PDFKit`/Core Graphics/Core Text as if interchangeable for generation; that was wrong and is corrected here. See "Export Architecture (PDF & XLSX)" below |
| XLSX export | `libxlsxwriter` (C, via its own upstream SPM `Package.swift`, as a remote dependency of `ACExport`) | No first-party or mature pure-Swift *writer* exists; MIT-licensed. **Verified**, not just assumed: compiles/links cleanly via SPM, produces a valid workbook, and — via a real ad-hoc-signed `.app` bundle carrying the actual `com.apple.security.app-sandbox` entitlement, not just source review — confirmed to work correctly under genuine kernel-enforced App Sandbox (unauthorized writes are really blocked; writes inside the sandbox container really succeed with correct output). See "Export Architecture (PDF & XLSX)" below and `docs/DECISIONS.md`. One narrower residual gap remains: the real app's actual `NSSavePanel`-granted write flow hasn't been tested (only the baseline container-write case has) — confirm once the real app target/entitlements exist |
| Modularization | Local Swift Packages in one Xcode workspace | Compiler-enforced **between packages** (e.g. `ACFeatures` cannot call `ACAudioKit` without declaring it); framework-import discipline *within* a package (e.g. `ACCore` avoiding `AVFoundation`) is convention/lint-enforced, not compiler-enforced — see "Package Dependency Graph" below |
| Distribution | Xcode + SPM, App Sandbox entitlements | Direct path to notarization and App Store submission |

Do not introduce a cross-platform UI framework (Electron, Flutter, Tauri, Qt, MAUI). The whole point of this stack is native performance and a frictionless App Store path — don't trade that away later for "portability" without an explicit, discussed requirement change.

## Deployment Target

**Minimum supported macOS version: 14.0 (Sonoma).** This was previously only implied — by `@Observable` and `SwiftData` both requiring it — and never actually pinned anywhere in the repository. This section fixes that.

- `SwiftData` (Persistence, above) requires macOS 14+; no fallback exists for earlier versions.
- `@Observable`/the Observation framework (State, above) requires macOS 14+.
- Both are hard architectural commitments already made elsewhere in this document, not proposals — macOS 14.0 is therefore not really a new choice being made here, it's the floor already implied by decisions already locked in. This section's job is to make that floor explicit and enforced, not to re-litigate it.
- `NavigationSplitView`'s 3-column form (see "Navigation Model," below) has shipped since macOS 13, so it imposes no additional constraint beyond the SwiftData/Observation floor.

**Why not target something newer:** macOS 14.0 is deliberately the *floor* required by frameworks already chosen, not a newer version picked for its own sake. A lower minimum means more of AutoCue's actual user base — video/audio post-production professionals, who don't always run the newest OS on a production machine — can run the app. Raising the floor later is a cheap, reversible change (loosen an availability check); lowering it after code has come to depend on a newer-OS-only API is not. If a future milestone genuinely needs a macOS 15+-only API, that's a real, concrete reason to raise the floor at that point — not a reason to preemptively target newer now.

**Toolchain implication:** targeting the macOS 14 SDK requires Xcode 15 or newer to build. This is a development-machine requirement, unrelated to the app's own "runs fully offline" constraint (Technology Stack, above), which governs the shipped app's runtime behavior, not the build toolchain used to produce it.

**Enforced at:** every package's `Package.swift` (`platforms: [.macOS(.v14)]` — already applied consistently in `Packages/ACCore/Package.swift` and `Packages/ACExport/Package.swift`, the two packages that exist ahead of schedule per earlier architecture-correction work) and the App target's deployment target setting, once it exists (`ROADMAP.md` D1). `ROADMAP.md` D1's acceptance criteria and D15's packaging pass both reference this section.

## MVVM + Clean Architecture

Three layers, strict dependency direction — **outer depends on inner, never the reverse**:

```
Presentation (Views + ViewModels)
        ↓ depends on
Domain (Models + Use Cases + Repository Protocols)   ← Foundation only, no Apple frameworks
        ↑ implemented by
Data (Audio, Export, Persistence services)
```

`ACCore` is Domain **and** Application combined — there is no separate Application package. This is deliberate, per the project's "fewer, well-separated moving parts" constraint: Use Cases need nothing an Application layer would add beyond what already lives in `ACCore` (they call Repository protocols also defined in `ACCore`). Don't split them into two packages without a real, concrete second need — see rule 7.

Rules that follow from this:
- `ACCore` (Domain) never imports `AVFoundation`, `SwiftData`, `PDFKit`, or `libxlsxwriter`. If you find yourself wanting to, the abstraction (a Repository protocol) belongs in `ACCore`; the import belongs in the Data package implementing it.
- Views never talk to Repositories or Use Cases directly — only to their ViewModel.
- ViewModels never import Data-layer packages — only `ACCore` (Use Case protocols) plus `ACDesignSystem` for shared UI.
- Business rules (e.g., how detected cues merge with embedded markers) live in Use Cases, not in ViewModels. A ViewModel orchestrates and holds view state; it does not decide domain logic.
- Concrete implementations are wired once, at app launch, in `DependencyContainer`. Nothing else constructs a concrete Repository — everything is injected via protocol.
- `Party` references (`Person.ID`/`Label.ID`) are resolved to display data (name, address) through a single domain-level `PartyResolver` (`ACCore/Models/PartyResolver.swift`) — no ViewModel re-implements that scan-and-match lookup independently. See `SPEC.md` §4.13.

### Package Dependency Graph

Compile-time dependencies point in one direction only — no cycles, no exceptions.

| Package | Depends on | Never depends on |
|---|---|---|
| `ACCore` | Foundation only | Any Apple framework beyond Foundation; any other local package |
| `ACDesignSystem` | SwiftUI/AppKit only — no local packages | `ACCore`, `ACFeatures`, any Data package |
| `ACFeatures` | `ACCore`, `ACDesignSystem` | `ACAudioKit`, `ACExport`, `ACPersistence` (Data-layer packages) |
| `ACAudioKit` | `ACCore` | `ACExport`, `ACPersistence`, `ACFeatures` |
| `ACExport` | `ACCore` | `ACAudioKit`, `ACPersistence`, `ACFeatures` |
| `ACPersistence` | `ACCore` | `ACAudioKit`, `ACExport`, `ACFeatures` |
| `ACTestSupport` | `ACCore` | linked only as a dependency of `.testTarget`s — never a dependency of any `.target`, including the App target |
| `AutoCue` (App target) | everything: `ACCore`, `ACFeatures`, `ACDesignSystem`, `ACAudioKit`, `ACExport`, `ACPersistence` | — it is the composition root; nothing depends on it |

The three Data-layer packages (`ACAudioKit`, `ACExport`, `ACPersistence`) never depend on each other. Each talks to `ACCore` only.

**Important limitation of this graph — read carefully before trusting "the compiler will catch it":** Swift Package Manager only gates access to *other local package products*. It does **not** gate access to Apple system frameworks (`Foundation`, `SwiftData`, `AVFoundation`, `PDFKit`, `Accelerate`, …) — those ship with the platform SDK and are importable from any target regardless of what `Package.swift` declares. So this graph genuinely, compiler-enforceably prevents e.g. `ACFeatures` from calling `ACAudioKit`'s public API. It does **not** prevent `import SwiftData` from compiling inside an `ACFeatures` file, or `import AVFoundation` from compiling inside `ACCore` — nothing stops those lines syntactically. That boundary is convention-enforced only, same tier as the existing "`ACCore` is Foundation-only" rule always was. Treat every "framework X isn't used in package Y" rule in this document as needing a grep/lint check in CI to actually hold over time — as of this batch, `Scripts/check-import-boundaries.sh` (run by `.github/workflows/ci.yml`) is exactly that check, covering the boundaries listed in the "Package Dependency Graph" table above. It does not cover everything this document states, though: it's a fixed set of forbidden-import patterns per package, not a general-purpose architecture linter — a new rule added to this document doesn't automatically get CI enforcement just because this section exists; the script needs updating too. See `CONTRIBUTING.md` §8.

### Data Flow vs. Dependency Direction

These point in opposite directions — don't conflate them.

- **Dependency/import direction** (compile-time — who can *see* whom): `Views → ViewModels → Use Cases / Repository Protocols (ACCore) ← Repository Implementations (Data packages)`. Presentation imports Domain; Data also imports Domain; nothing above Domain is ever imported by Domain itself.
- **Data flow direction** (runtime — who *produces* what the user sees): `Persistence (SwiftData) → Repository Implementation → Use Case → ViewModel → View`. Data flows outward to the screen while dependencies point inward toward `ACCore`. `ACCore` never imports `ACPersistence`, yet SwiftData-sourced data reaches every screen, because the Repository *protocol* — owned by `ACCore`, implemented by `ACPersistence` — is what gets injected, not a hard import.

### Dependency Injection Pattern

`DependencyContainer` is constructed exactly once, in the App target, at launch. It is the **only** place in the codebase allowed to reference a concrete Repository implementation (`ProjectRepositoryImpl`, `AudioAnalysisRepositoryImpl`, `ExportRepositoryImpl`) or construct a Use Case.

Views and ViewModels never see `DependencyContainer` — never `@Environment(DependencyContainer.self)`, never a lazy `.task { viewModel = container.make…() }` inside a Feature View. Instead:

1. `DependencyContainer` exposes one factory method per top-level Feature ViewModel — e.g. `func makeProjectLibraryViewModel() -> ProjectLibraryViewModel`, `func makeSetupViewModel(for projectID: Project.ID) -> SetupViewModel`.
2. The App target's navigation root for each scene — the Library window's root view, and each Project window's `NavigationSplitView` shell (see "Document & Window Model," below, for why there are now two kinds of navigation root instead of one) — is the only call site that ever invokes these factories, at the point a screen is navigated to (e.g. inside a `NavigationSplitView`'s `detail:` closure or a `.navigationDestination`).
3. Every `ACFeatures` View receives its ViewModel as a plain initializer parameter (`init(viewModel: ProjectLibraryViewModel)`) — it never constructs or looks one up itself.

This keeps `ACFeatures` Views trivially previewable and testable (they need only a ViewModel instance, nothing else) and removes any pathway for a View to reach a Data-layer type by accident — `ACFeatures` doesn't even depend on the packages that define those types (see the dependency graph above).

`AppState` is Presentation-layer navigation state, not Domain data — it lives inside `ACFeatures` (not the App target, not `ACCore`). Unlike `DependencyContainer`, it is **not** a single app-wide singleton: one `AppState` instance is constructed per Project window, when that window opens, and injected into that window's `ACFeatures` view hierarchy via `.environment()` — see "Document & Window Model," below, for the full reasoning (multiple windows can independently be showing different sections of different Projects, so a single shared instance doesn't make sense). It's still fine to hand around via SwiftUI `Environment` within its own window, because it holds no business data and no reference to any Repository or Use Case — only that window's `selectedSection`.

### Use Cases Are Stateless

Every Use Case type in `ACCore` is a `struct` with no mutable stored properties — only `let`-held Repository protocol references passed in at construction. All mutable state lives in exactly one of two places: a Repository implementation (Data layer — e.g. a SwiftData `ModelContext`, isolated however that package chooses internally) or a ViewModel (`@MainActor`, one instance per screen).

This matters because `DependencyContainer` builds each Use Case exactly once at launch and hands the *same instance* to every ViewModel that needs it — a Use Case must be safe to call concurrently from multiple screens at once. A stateless struct holding only `Sendable` protocol references is automatically safe under Swift's strict concurrency checking without needing to be an actor itself. Repository *protocols* in `ACCore` must therefore be declared `Sendable` (`protocol ProjectRepository: Sendable`) for this to hold; whether a given Repository *implementation* is internally an actor is a Data-layer detail Use Cases never need to know about.

`ACCore` domain models (`Project`, `Setup`, `Cue`, …) are plain structs composed entirely of `Sendable` fields and are therefore implicitly `Sendable` too — this is required for them to cross a Repository's `AsyncStream` and move between a background Use Case call and a `@MainActor` ViewModel without extra ceremony. Don't add a non-`Sendable` stored property (e.g. a closure capturing mutable state) to a domain model without stopping to reconsider the design first.

### Domain Model Value-Type Conformances

Every `ACCore` domain type follows the same conformance policy, decided once here rather than re-decided ad hoc per type as new models are added:

- **`Identifiable`** — required on every domain type with an `id` field (`Project`, `Setup`'s parent relationship aside, `Cue`, `Person`, `Label`, `AudioAsset`, `WaveformPeaks`, …). This was previously only demonstrated by usage — `Cue.ID`, `Person.ID`/`Label.ID`, `Project.ID`, `AudioAsset.ID` are all referenced elsewhere in this document and `SPEC.md` (e.g. `PartyReferenceLocation.cueRightHolder(cueID: Cue.ID)`, `WindowGroup(for: Project.ID.self)`, `WaveformPeaks.audioAssetID: AudioAsset.ID`) without ever being stated as a blanket policy — stated explicitly here so it isn't left as an unstated assumption a type could quietly be built without. **This rule is conditional on having an `id` field, not unconditional on every domain type** — a pure value type with no natural identity concept (nothing elsewhere in `SPEC.md` ever needs to reference *this particular instance* independent of the field that holds it) simply has no `id` field to begin with, so the rule doesn't engage; that's not an exception carved out of "always," it never claimed "always" in the first place. `Timecode`/`MediaDuration` (`SPEC.md` §4.8–§4.9), `PostalAddress`/`Party` (§4.5), `ProgressUpdate`/`OperationProgress<T>` (§4.17), and `AnalysisSettings` (§4.11) are all real, already-built instances of this — none has an `id` field, none conforms to `Identifiable`, and none should gain one "just in case" (that would be rule 7's premature-abstraction problem, applied to a conformance instead of a feature). See `docs/DECISIONS.md` for the `PostalAddress`/`Party` case specifically, which is what prompted stating this explicitly rather than leaving it implied.
- **`Sendable`** — always required. Established above ("Use Cases Are Stateless"): domain models cross Repository `AsyncStream`/`AsyncThrowingStream` boundaries between background Use Case calls and `@MainActor` ViewModels, which requires it.
- **`Equatable`** — always required. Needed for change-detection (e.g., "did this field actually change before scheduling an autosave") and is the basis for this project's value-type unit tests (construct → copy/mutate a copy → assert the expected equality/inequality) — see `ROADMAP.md` D1–D2.
- **`Hashable`** — added only where a type is genuinely used as a `Set` element, `Dictionary` key, or needs SwiftUI list/selection identity (e.g. `Setup.productionTypes: Set<ProductionType>` genuinely needs it). Not blanket-applied to every type regardless of use.
- **`Codable` — not applied by default.** An earlier draft of this project's domain models carried a blanket expectation that every type conform to `Codable`, visible in `ROADMAP.md`'s original (pre-restructuring) M2–M6 acceptance criteria ("Codable round-trip test passes"). On review, there is no actual interchange, export, or persistence path anywhere in `SPEC.md` that uses `Codable`: persistence goes through hand-written `ACPersistence` Mappers against SwiftData `@Model` entities (see "Folder/Package Structure," below), not `Codable` serialization of domain structs directly; there is no JSON export, drag-and-drop payload, pasteboard, or URL-scheme feature scoped anywhere. Keeping `Codable` "in case it's useful later" is exactly the premature abstraction rule 7 already warns against, so it's removed as a blanket requirement here. **Add `Codable` to a specific type only when a specific, real feature needs it** (e.g. a future "copy Cue as JSON" convenience), and document that real use case at the point the conformance is added — never blanket-reintroduced across every type at once. `ROADMAP.md` D1–D2's acceptance criteria test via `Equatable`-based round-trips instead of `Codable` round-trips.

## Folder / Package Structure

```
AutoCue.xcworkspace
│
├── AutoCue (App target — thin composition root)
│   ├── AutoCueApp.swift            @main; declares the Library scene, the per-Project
│   │                               WindowGroup(for: Project.ID.self) scene, and the Settings
│   │                               scene; builds DependencyContainer and OpenProjectWindowRegistry
│   ├── DependencyContainer.swift   wires concrete services → use cases → ViewModel factories
│   └── OpenProjectWindowRegistry.swift   app-wide duplicate-open guard — see "Document & Window Model"
│
├── Packages/
│   ├── ACCore/                    DOMAIN + APPLICATION — pure Swift
│   │   ├── Models/                 Project, Setup, Cue, CueRightHolder, Person, Label, Party,
│   │   │                           PartyResolver, Settings, AnalysisSettings, AudioAsset,
│   │   │                           EmbeddedMarker, BroadcastWaveMetadata, MediaDuration,
│   │   │                           Timecode, TimecodeFrameRate, PostalAddress,
│   │   │                           WaveformPeaks, WaveformPeakBucket,
│   │   │                           CueSheetPageLayout, CueSheetLayoutElement, LayoutRect,
│   │   │                           ProgressUpdate, OperationProgress
│   │   ├── UseCases/                ImportAudioUseCase, DetectCuesUseCase, ExportCueSheetUseCase,
│   │   │                           UpdateCueUseCase, RecalculateTotalMusicRuntimeUseCase,
│   │   │                           DeletePersonUseCase, DeleteLabelUseCase,
│   │   │                           GenerateWaveformPeaksUseCase, GenerateWaveformDetailUseCase, ...
│   │   └── RepositoryProtocols/     ProjectRepository, AudioAnalysisRepository, ExportRepository
│   │
│   ├── ACAudioKit/                DATA — audio ingestion & analysis
│   │   ├── WAVParsing/              RIFF/BWF chunk reader
│   │   ├── Streaming/               AVAudioFile-based chunked reader
│   │   ├── Analysis/                vDSP silence/level detection + waveform peak extraction
│   │   └── AudioAnalysisRepositoryImpl.swift
│   │
│   ├── ACExport/                  DATA — output generation
│   │   ├── PDF/                     Core Graphics (PDFContext) + Core Text renderer — draws the
│   │   │                           shared CueSheetPageLayout (ACCore); PDFKit not used for generation
│   │   ├── XLSX/                    libxlsxwriter wrapper (remote SPM dependency — see Technology
│   │   │                           Stack table)
│   │   ├── Spike/                   XLSXFeasibilitySpike.swift — dependency-validation smoke test,
│   │   │                           not the real writer; see "Export Architecture" below. Exists
│   │   │                           ahead of D11 deliberately; superseded once XLSXCueSheetWriter
│   │   │                           is actually built
│   │   └── ExportRepositoryImpl.swift
│   │
│   ├── ACPersistence/             DATA — project storage
│   │   ├── SwiftDataModels/         @Model schema (kept separate from ACCore domain structs)
│   │   ├── Mappers/                 SwiftData ⇄ domain model conversion
│   │   └── ProjectRepositoryImpl.swift
│   │
│   ├── ACDesignSystem/            PRESENTATION — reusable, feature-agnostic UI
│   │   ├── Components/              WaveformView, CueTableView, ProgressBanner, EmptyStateView
│   │   ├── Theme/                   colors, type scale, spacing tokens
│   │   └── Modifiers/                .errorAlert(), .loadingOverlay()
│   │
│   ├── ACFeatures/                PRESENTATION — screens; its own package, not app-target code
│   │   ├── AppState.swift           per-window navigation state (selected section) — one instance
│   │   │                           per Project window, not app-wide; see "Document & Window Model"
│   │   ├── ProjectLibrary/    (Views/ ViewModels/ Components/) — used by the Library window
│   │   ├── CueSheetEditor/    (Views/ ViewModels/ Components/) — Setup + Cue Sheet sections
│   │   ├── ReviewAndExport/   (Views/ ViewModels/) — combined Review & Export section (renamed
│   │   │                           from Export/ — no longer a sheet; see "Navigation Model")
│   │   └── Settings/          (Views/ ViewModels/)
│   │
│   └── ACTestSupport/             shared fakes/fixtures — linked only into test targets, never shipped
```

`Features/` living directly in the app target (as originally planned) meant nothing stopped a screen from `import SwiftData`/`AVFoundation` directly — the app target legitimately links both for `DependencyContainer`. Moving it to its own package, `ACFeatures`, makes the ViewModel-can't-reach-Data-layer rule *actually* compiler-enforced (see Package Dependency Graph above) — the residual gap (raw system-framework imports) is unavoidable regardless of package layout, per the limitation noted above.

`SwiftDataModels` are intentionally separate types from the `ACCore` domain models. Persistence schema is a Data-layer detail; it must never leak into Domain or Presentation — not even into `ACFeatures`. Always go through the `Mappers/` folder. There is currently no documented exception to this rule; if one is ever needed, it must be added here explicitly, with justification, not introduced silently.

## Navigation Model

Resolves an ambiguity `ROADMAP.md`'s original (pre-restructuring) M11 left unresolved: the app has more than two sibling screens per project, but that milestone's acceptance criteria only ever described a 2-column sidebar+detail shell. The original product brief is explicit: **three tabs — Setup, Cues, and Review & Export — always visible and accessible at any time, like browser tabs.** This section fixes the navigation structure to match that brief exactly. (An earlier draft of this section made Export a modal sheet triggered from Review; that contradicted the brief and has been corrected here — see `docs/DECISIONS.md` for the record of that reversal.)

Because `Project`s now open in their own windows (see "Document & Window Model," below), navigation splits across two distinct levels, each owned by a different scene:

**Level 1 — which Project. Owned by the Library window,** not by per-project navigation at all. See "Document & Window Model" for the Library scene and how a Project window is opened/focused from it.

**Level 2 — which section of *this* Project. Owned by each Project window's own `NavigationSplitView`, a 2-column shell:**

1. **Content — the three always-accessible section tabs.** A fixed, static list of exactly three co-equal destinations: **Setup**, **Cue Sheet**, and **Review & Export**. Selecting one sets that window's `AppState.selectedSection`. None of the three is ever presented as a modal sheet — all three are reachable at any time within the window, exactly like browser tabs, per the brief.
2. **Detail — the actual screen.** Renders whichever Feature View corresponds to `AppState.selectedSection` (`SetupView`, `CueSheetEditorView`, or `ReviewAndExportView`).

```swift
enum ProjectSection: CaseIterable, Equatable {
    case setup
    case cueSheet
    case reviewAndExport
}
```

(`AppState`'s full shape, including why it's per-window rather than a single app-wide instance, is defined in "Document & Window Model," below — it's inseparable from the window model now, not a Navigation Model concern on its own.)

**"Review & Export" is one combined destination, not two, and never a sheet.** `ReviewAndExportView` is a single persistent screen showing both the validation summary (`ROADMAP.md` D11/T11.1) and the export controls (`ROADMAP.md` D11/T11.2–T11.5) together, inline. This is also the architecturally cleaner choice on its own merits, independent of matching the brief: export readiness is *derived from* validation state (`Settings.shareValidationStrictness` gates export on the same issues Review surfaces), so the two were never really independent concerns — combining them into one `ReviewAndExportViewModel` avoids two ViewModels having to coordinate shared state across a presentation boundary that no longer exists.

**Settings is entirely outside this hierarchy.** It's app-level, not project-scoped (`SPEC.md` §4.7 already establishes this) — it uses SwiftUI's standard `Settings { }` scene (opened via **AutoCue ▸ Settings…**/⌘,), a separate system-managed window, with its own `DependencyContainer.makeSettingsViewModel()` call site at that scene's root. It is never reachable through a Project window's `NavigationSplitView` at all, and is unaffected by the navigation/window-model changes in this batch.

**`DependencyContainer` factory methods, one per screen:**
- `makeProjectLibraryViewModel()` — used by the Library window
- `makeSetupViewModel(for projectID: Project.ID)`
- `makeCueSheetEditorViewModel(for projectID: Project.ID)`
- `makeReviewAndExportViewModel(for projectID: Project.ID)` — one ViewModel backs the one combined, always-accessible destination
- `makeSettingsViewModel()` — called only from the `Settings` scene's root

Consistent with the existing Dependency Injection Pattern (above): each Project window's `NavigationSplitView` `detail:` closure is the only call site that switches on that window's `appState.selectedSection` and invokes the matching factory — Views never do this themselves.

## Data Model (Finalized)

AutoCue targets the **Swiss SUISA cue-sheet standard** (official "Declaration of musical works for films and audiovisual productions" / *WA Film* form) as its compliance target, plus the fields SWISSPERFORM's audiovisual participation reporting shares with it. Full field-by-field detail, optionality, and the mapping back to the source SUISA form live in `SPEC.md` — treat that file as authoritative for schema questions, not this summary.

**The domain model in `ACCore/Models/` is the stable public application model.** Once a milestone implements a type's fields, changing them requires updating `SPEC.md`, `CLAUDE.md`, and `ROADMAP.md` together, in the same change — see rule 9 below. This applies to every domain type, not only the ones mapped directly to the SUISA form.

Model shape:
- **`Setup`** — one per `Project`. Production-level header info (title, producer, director, runtimes, production year, production type, declarant, attachments, editor-display timecode frame rate). Maps almost 1:1 to the SUISA form's top section.
- **`Cue`** — many per `Project`, ordered. One SUISA "musical work" entry: title, work number, `MediaDuration`, and its `[CueRightHolder]` list. Carries a few app-internal-only fields (`source`, `startTimecode`, `notes`) used for the auto-detection workflow — these are never exported to the SUISA document, since SUISA wants total usage duration per work, not on-screen position or usage category.
- **`CueRightHolder`** — sub-entity of `Cue`. A `Party` (composer/author/arranger/publisher) plus performance-broadcast and mechanical-rights percentage shares. Shares must sum to 100% per Cue, per share type — validated in a Use Case, never in the struct.
- **`Person`** / **`Label`** — individual vs. corporate right-holder identity, referenced everywhere the SUISA form allows "name, first name **or publishing company**" via a `Party` enum (`.person` / `.label`), never duplicated fields. Deletion of either is guarded — see `SPEC.md` §4.12.
- **`Settings`** — app-level only (export language, default declarant, validation strictness, `AnalysisSettings` defaults). Not part of the SUISA document.
- **`AudioAsset`** — an immutable, metadata-only snapshot derived from the imported WAV file (`SPEC.md` §4.10); optional on a `Project` until an import has happened. Never holds raw or downsampled sample data.
- **`MediaDuration`** / **`Timecode`** — two distinct value types: `MediaDuration` is a *length* of time (`SPEC.md` §4.8); `Timecode` is a *position* within an `AudioAsset`, formatted `HH:MM:SS:FF` using `Setup.timecodeFrameRate`, a display convention with no relationship to any video file (`SPEC.md` §4.9). `MediaDuration` was chosen as the name specifically to avoid colliding with Swift's own standard-library `Duration` type, used throughout Concurrency APIs.
- **`Project`** — the persisted container: `Setup` (1:1), `[Cue]` (1:many), a project-scoped `[Person]`/`[Label]` right-holder directory, plus an optional `AudioAsset`.

There is no separate persisted `CueSheet` type — the exportable cue sheet is just `Setup` + `[Cue]`, assembled on demand by `ExportCueSheetUseCase`. Don't reintroduce a `CueSheet` model unless a real need for a distinct persisted/derived shape shows up.

## Design System (`ACDesignSystem`)

- All visually reusable pieces (buttons, `WaveformView`, `CueTableView`, empty/loading/error states) live here — never duplicated inside an `ACFeatures/*/Components/` folder.
- Theme values (color, type scale, spacing) are tokens defined once in `Theme/`. Views reference tokens, never raw hex colors or magic numbers for spacing/fonts.
- `ACDesignSystem` has no knowledge of `CueSheet`, `Project`, or any domain type — it only knows generic display types (strings, numbers, closures/bindings). This is what keeps it reusable and, longer term, portable to another app or target (e.g., an iPad companion).
- **`WaveformView` takes `WaveformDisplayData` (defined in `ACDesignSystem` itself), never `ACCore`'s `WaveformPeaks` directly.** Same "local adapter struct" pattern as `CueTableView`'s row protocol: a Feature-layer mapper (`ACFeatures`) converts the domain type to the design-system-local one at the point a screen renders it. This is now the standing convention for every `ACDesignSystem` component that displays domain-derived data, not something to redecide per component — see SPEC.md §4.15 for `WaveformPeaks` itself.

## Single Source of Truth

- **Persisted data**: `SwiftData`, accessed only through `ProjectRepository`. No other layer keeps its own cached copy of saved project state. **Views never use `@Query` and never import `SwiftData`.** `@Query` binds directly to `@Model` entity types, which would mean a View depending on a Data-layer persistence schema type — a direct violation of "Views never talk to Repositories… only to their ViewModel," above. (An earlier draft of this document said list views "should read live via `@Query` where practical," which directly contradicted that MVVM rule; this replaces it, not supplements it.) Instead, `ProjectRepository` exposes a live-observation API alongside one-shot CRUD — e.g. `func observeAll() -> AsyncStream<[Project]>`, or equivalent — where every mutating Repository method republishes the fresh domain-model result into that stream. A ViewModel subscribes once (typically via a small wrapping Use Case, e.g. `ObserveProjectsUseCase`) and republishes into an `@Observable` property the View binds to. List-style views still get live updates with no manual refresh; the mechanism is a Repository-owned `AsyncStream` of domain models instead of `@Query` against entities.
- **Actively edited data**: the screen's ViewModel (e.g., `CueSheetEditorViewModel`) holds the one working copy of the `Setup` and `[Cue]` list being edited, and is the only thing allowed to mutate it. Writes flow back to `ProjectRepository` explicitly — debounced for continuous field-level edits, immediate for structural mutations (add/delete/reorder a `Cue`) — see "Performance Considerations," below, and `SPEC.md` §4.18. Never scattered `save()` calls from multiple places either way.
- **Audio-derived data**: the file on disk is the source of truth for raw audio; `AudioAsset` is a derived, immutable snapshot produced by `AudioAnalysisRepository`, not something reconstructed ad hoc in a View or ViewModel.
- **Right-holder references**: `Party` values (`Person.ID`/`Label.ID`) are the only place a `Person`/`Label` is referenced from elsewhere in a `Project` — never copy their fields into `Setup`/`CueRightHolder`. Because these are bare-UUID references with no SwiftData cascade/nullify behavior backing them, deleting a `Person`/`Label` is a Use Case-level operation (`DeletePersonUseCase`/`DeleteLabelUseCase`), never a raw repository `delete()` call — see `SPEC.md` §4.12 for the exact delete-guard rule. Resolving a `Party` back to display data always goes through `PartyResolver`, never a ViewModel-local scan of `project.people`/`project.labels` — see `SPEC.md` §4.13.
- If you ever need the same piece of state in two places, ask "which one owns it" and inject/observe from there — do not introduce a second variable that has to be kept in sync manually. (`Setup.totalMusicRuntime` looked like exactly this trap; its resolution — a single field with one owning Use Case — is documented in `SPEC.md` §4.14.)

## Document & Window Model

**Supersedes** the single-window decision from an earlier revision of this document — reversed in response to an explicit product requirement: comparing/referencing two Projects side by side in separate windows. See `docs/DECISIONS.md` for the full record of the reversal, including why the original reasoning was sound *given the constraint at the time* and is now superseded by a real requirement, not by a discovered flaw. This section describes the resulting multi-window architecture in full, including the two problems the single-window design used to avoid for free, and how they're actually solved now that avoiding them by construction is no longer an option.

**Decision: multi-window, one `Project` per window.** `AutoCueApp` declares three kinds of scene:

1. **A singleton Library scene** — the Project Library (create/select/delete `Project`s), shown in exactly one window, never duplicated. Selecting or double-clicking a project here opens (or focuses — see below) that Project's own window. The Library window never displays a Project's Setup/Cue Sheet/Review & Export content directly — that's Level 2 navigation, owned by the Project window itself (see "Navigation Model," above).
2. **A Project window scene, `WindowGroup(for: Project.ID.self)`.** Zero or more may be open simultaneously, each scoped to exactly one `Project.ID`, each its own independent 2-column `NavigationSplitView` (content = the three section tabs, detail = the active screen — see "Navigation Model," above).
3. **The `Settings` scene** — unchanged; still app-level, still outside this hierarchy entirely.

**Why `WindowGroup(for: Project.ID.self)` rather than a literal `DocumentGroup`.** `DocumentGroup` is SwiftUI's mechanism for *file-based* documents — each window is backed by a `FileDocument`/`ReferenceFileDocument` tied to a file the system's Open/Save panels manage directly. That's a different persistence shape than AutoCue actually has: `Project`s are rows in one shared SwiftData store behind `ProjectRepository` ("Single Source of Truth," above — established, validated architecture, not being revisited here), not individual files a user opens one at a time. Adopting real `DocumentGroup` would mean either abandoning that SwiftData/`ProjectRepository` model in favor of file-per-project persistence, or fighting the framework with a synthetic `FileDocument` that doesn't represent real storage — both worse than the alternative. `WindowGroup(for: Project.ID.self)` is SwiftUI's actual supported pattern for "multiple windows of the same kind, each showing a different piece of app-managed (not file-based) data" — exactly this app's shape. This *is* the "or equivalent" a `DocumentGroup`-based architecture allowed for, applied correctly for this app's actual persistence model.

**Per-window state.** `AppState` is no longer a single app-wide singleton — with multiple Project windows able to show different sections of different Projects simultaneously, a single shared `selectedSection` value doesn't make sense. Each Project window gets its **own** `AppState` instance, constructed when that window opens (scoped to the `Project.ID` the `WindowGroup` handed it):

```swift
@Observable
final class AppState {
    var selectedSection: ProjectSection = .setup
}
```

`selectedProjectID` is gone from `AppState` entirely — which Project a given window shows is now the `Project.ID` its `WindowGroup(for:)` instance was opened with, not a separately-tracked mutable field that could drift out of sync with the window itself.

**Duplicate-open prevention: an explicit app-wide registry, not left to chance.** The problem the single-window design used to avoid by construction — the same `Project` open for editing in two places at once — is real again now that multiple windows exist, so it's solved explicitly:

- A single, app-wide `OpenProjectWindowRegistry` (constructed once in `AutoCueApp`, alongside `DependencyContainer` — the same "instantiated once at launch" tier as that container, *not* per-window like `AppState`) tracks which `Project.ID`s currently have an open window.
- Before opening a Project window (from the Library, or any other "open this project" action), the app checks the registry. If that `Project.ID` is already open, the existing window is brought to front instead of a duplicate being opened — via `NSWindow.makeKeyAndOrderFront`, the AppKit-interop escape hatch the Technology Stack table (above) already allows for "when SwiftUI has a genuine gap"; bringing an existing `WindowGroup(for:)` window to front by its data identity isn't directly exposed by SwiftUI as of this writing.
- Each Project window registers its `Project.ID` on appear and unregisters on close, so the registry always reflects reality.
- **Rule, stated plainly: a given `Project` is editable from at most one window at any time.** Multi-window means multiple *different* Projects open at once — never the same Project open twice.

**Save serialization: per-`Project.ID`, not global.** An earlier revision of this section serialized all saves through one app-wide actor — correct but coarser than necessary under the single-window design, where only one Project was ever being saved at a time anyway, so the distinction was moot. That no longer holds once multiple windows can genuinely be saving different Projects concurrently: a slow save for the Project in Window A must not delay or block a save for an unrelated Project in Window B. `ProjectRepositoryImpl` (`ACPersistence`) therefore serializes writes **per `Project.ID`** internally — e.g. one actor-isolated queue or dedicated `ModelContext` per currently-open `Project.ID`, not one lock spanning all of them. Two saves to *different* Projects run independently; two saves to the *same* Project still serialize against each other exactly as before. Combined with the duplicate-open-prevention rule above, "two saves to the same Project" can now only ever originate from the single window that legitimately owns it — so this remains a real, airtight guarantee, just correctly scoped instead of over-broadly scoped.

**Consequences:**
- Closing a Project window flushes any pending debounced autosave for that window's ViewModel before the window fully closes — a save is never silently abandoned mid-debounce. This is the equivalent, per-window guarantee to what the single-window design provided at project-switch time.
- The Library window's project list (live-observed via `ProjectRepository`, "Single Source of Truth" above) reflects edits made in any open Project window as they're saved — same live-update mechanism as before, now genuinely useful across multiple simultaneously-open Projects instead of a single one.
- `Settings` is unaffected — unchanged from the prior revision of this section.

## Naming Conventions

- Local packages: `AC<Purpose>` (`ACCore`, `ACAudioKit`, `ACExport`, `ACPersistence`, `ACDesignSystem`, `ACFeatures`, `ACTestSupport`).
- Types by role, suffix communicates the role:
  - Views: `<Feature>View` (`CueSheetEditorView`), reusable pieces just `<Thing>View`/`<Thing>Component` (`WaveformView`).
  - ViewModels: `<Feature>ViewModel` (`CueSheetEditorViewModel`).
  - Use cases: `<Verb><Noun>UseCase` (`DetectCuesUseCase`, `ExportCueSheetUseCase`).
  - Repository protocols: `<Noun>Repository` (`ProjectRepository`); implementations: `<Noun>RepositoryImpl`.
  - SwiftData schema types: suffix `Entity` or `Model` distinctly from the domain type of the same concept (e.g., domain `Project` vs. persistence `ProjectEntity`), so an accidental cross-layer import is obvious at the call site, not just at the import line.
  - Pure domain lookups/helpers with no Repository dependency (e.g. `PartyResolver`) are plain types/namespaces in `Models/`, not suffixed `UseCase` — that suffix is reserved for orchestration that actually depends on a Repository protocol.
- Files are named exactly after the primary type they contain — one primary type per file.
- Folders mirror architectural role (`Models/`, `UseCases/`, `RepositoryProtocols/`, `Views/`, `ViewModels/`), not feature-then-role-then-feature nesting.
- `ACTestSupport` is declared as a dependency of `.testTarget`s only, in every package's `Package.swift` — never a dependency of a `.target`, including the App target. A test fake leaking into a shipping build is a packaging bug, not a style nit.

## Reusable Component Philosophy

- Default a new UI piece to living inside the feature that needs it (`ACFeatures/<Feature>/Components/`).
- Promote it to `ACDesignSystem` the moment a second feature needs the same thing, or the moment it has no dependency on feature-specific domain types to begin with (e.g., a generic progress banner belongs in the design system on day one; a cue-specific row does not, until reused).
- A component belongs in `ACDesignSystem` only if it can be previewed and reasoned about with zero knowledge of `Project`/`Setup`/`Cue`. If it needs a domain type to make sense, it stays in `ACFeatures`.
- Prefer composition (small components combined in a screen) over configurable mega-components with many boolean flags.

## Performance Considerations

- Never load a full WAV file into memory. All reads go through the streaming reader in `ACAudioKit/Streaming`, processing in bounded-size chunks. This constraint also applies at the Domain boundary: `AudioAsset` (`SPEC.md` §4.10) is metadata-only by design and must never grow a raw or downsampled sample-data field.
- All DSP (silence detection, level metering) uses `Accelerate`/vDSP — no hand-rolled sample loops over large buffers.
- Long-running work (file import, cue detection, export) always runs off the main actor and reports progress incrementally via the single shared `AsyncThrowingStream<OperationProgress<T>, Error>` contract — see "Long-Running Operations: Progress & Cancellation" below; the editor UI must remain interactive during a multi-hour-file scan.
- ViewModels are `@MainActor`; anything that touches audio I/O or file I/O is not.
- Use `@Observable` fine-grained invalidation correctly: keep large collections (e.g., all cues) structured so a single-row edit doesn't force a diff over the whole list — favor `Table`/`LazyVStack`-friendly identifiable rows over recomputing whole-array transformations on every keystroke.
- Autosave is debounced, not triggered on every keystroke/edit — for continuous field-level edits (title text, share percentages) specifically. **Structural mutations (add/delete/reorder a `Cue`) are not debounced — they write through to `ProjectRepository` immediately.** These are discrete, complete actions with nothing further to type, unlike a field edit; debouncing them would leave a deleted row still persisted for up to the debounce interval, which would silently break "Review & Export reflects the current cue list with no manual refresh" (`SPEC.md` §4.18).

## Export Architecture (PDF & XLSX)

### PDF: preview and export must be pixel-identical, so layout is computed exactly once

`PDFKit` (`PDFDocument`/`PDFView`) is a viewing/annotation framework — it cannot generate the SUISA form's pixel-accurate layout. Generation is Core Graphics (`PDFContext`) + Core Text; `PDFKit` is used, if at all, only for lightweight in-app preview of an already-generated PDF (opening the finished file), never for producing it. See the Technology Stack table's corrected PDF export row.

The actual requirement — an on-screen A4 preview that matches the exported PDF exactly — rules out having two independent implementations (a SwiftUI-native preview and a separate Core Graphics/Core Text export renderer) that each decide layout for themselves; SwiftUI's text engine and Core Text can disagree on line-wrapping/metrics, which would silently break "matches the preview" the moment they do. The fix: layout is computed **once**, as data, and both the preview and the real PDF just draw that data.

- `CueSheetPageLayout` (`ACCore/Models/`, SPEC.md §4.16) is a plain, renderer-agnostic value type — a page-by-page, element-by-element description of exactly where everything goes (frames as `LayoutRect`, a Foundation-only geometry primitive — deliberately not `CGRect`, to keep `ACCore` unambiguously Foundation-only per rule 1).
- `ExportRepository` (`ACExport`) computes it, because accurate text measurement/line-breaking for pagination (5 works/page main form, 4/page continuation) genuinely requires Core Text — pure Foundation code can't do this. The *computation* is therefore a Data-layer responsibility even though the resulting *value* is a plain `ACCore` type, obtained by `ACFeatures` only through a Use Case wrapping `ExportRepository` (never `ACExport` directly — consistent with the dependency graph).
- Two consumers draw the identical computed layout: `PDFCueSheetRenderer` (`ACExport`, via Core Graphics `PDFContext` + Core Text — the real export) and the on-screen preview View (`ACFeatures`, via SwiftUI `Canvas` painting the precomputed frames directly). **The preview View deliberately does not use SwiftUI's native `Text`/`VStack` layout for the form content** — doing so would let SwiftUI's text engine silently diverge from Core Text's, defeating the entire point of sharing one layout model.

The exact visual design (fonts, column widths, table borders matching the sourced SUISA form) is real work for `ROADMAP.md` D11/T11.2 — this section fixes the *mechanism* (one computed layout, two consumers), not the visual design itself.

### XLSX: `libxlsxwriter` dependency — validated now, not at the old M28 position

`CLAUDE.md` rule 4 requires checking App Sandbox compatibility, static-linkability, and maintenance status before adopting a third-party dependency. This was previously stated as a rule but not actually exercised until `ROADMAP.md`'s original (pre-restructuring) M28 — 27 milestones of downstream work assuming it holds. That's now been done directly, ahead of schedule, rather than left as an assumption; the real writer (`ROADMAP.md` D11/T11.4) now builds on an already-cleared dependency instead of an unverified one:

- **SPM integration:** `libxlsxwriter` ships its own upstream `Package.swift` (as of v1.2.4) — `ACExport` depends on it as a normal remote SPM package (`.package(url: "https://github.com/jmcnamara/libxlsxwriter.git", from: "1.2.4")`), not a vendored copy. This is a build-time fetch (resolved by Xcode/SPM when a developer builds), unrelated to the shipped app's runtime "must run fully offline" constraint, which governs the app's behavior at runtime, not how its dependencies are obtained at build time.
- **Compiles and links as a C target:** verified — a real build succeeds, linking only against system `zlib` (no other dynamic dependencies).
- **Deployment target:** builds cleanly targeting macOS 14, no version-specific issues encountered.
- **Minimal smoke test writing a workbook with real cells:** verified — `Packages/ACExport/Sources/ACExport/Spike/XLSXFeasibilitySpike.swift` writes a string cell and a number cell and closes the workbook; `Packages/ACExport/Tests/ACExportTests/XLSXFeasibilitySpikeTests.swift` confirms the output is a genuine ZIP/OOXML file (`PK` signature) with the correct cell values in `sheet1.xml`, and that a write failure surfaces as a thrown Swift error rather than a crash.
- **App Sandbox compatibility: verified via real kernel enforcement, not just source review.** An initial `sandbox-exec`-based attempt was inconclusive (the tool doesn't function at all in that environment — confirmed against a trivial control case, `/bin/echo`, failing identically — so it was correctly reported as unresolved rather than a pass). That was superseded by an actual test: the spike binary packaged into a minimal `.app` bundle, ad-hoc code-signed with the real `com.apple.security.app-sandbox` entitlement, and run directly. A write to an unauthorized location (`~/Desktop`) was genuinely blocked by the kernel (`Operation not permitted`, handled gracefully by `libxlsxwriter` as a normal error, not a crash); a write inside the app's own sandbox container succeeded and produced a fully valid workbook. macOS creating a real container at `~/Library/Containers/<bundle-id>/` for the run is itself confirmation the sandbox was genuinely active, not approximated. **Narrower residual gap:** the real app's `NSSavePanel`-granted write flow (dynamic, Powerbox-mediated access to a user-chosen export destination) wasn't tested — only the baseline container-write case was. Confirmed at `ROADMAP.md` D15/T15.2, once the real app target and final `AutoCue.entitlements` exist; this is a small follow-up, not a reopening of the dependency decision.

Full writeup: `docs/DECISIONS.md`. No alternative is being proposed — the dependency held up under real verification, so `CLAUDE.md` rule 4's bar is met, with one flagged residual gap (sandbox runtime) rather than an open question about the dependency itself.

## Long-Running Operations: Progress & Cancellation

One contract, used everywhere a long-running operation reports progress — not reinvented per milestone.

**Why not Foundation's `Progress`:** `Progress` is a KVO-based Objective-C class with its own observation and cancellation model (`Progress.cancel()`, `isCancelled`, `.becomeCurrent()`/`.resignCurrent()` implicit tree-building). None of that composes with Swift's structured concurrency — there's no `for await` over a `Progress`, and its cancellation tree is independent of `Task` cancellation. Referencing both `AsyncStream` and `Progress` as if interchangeable (an earlier version of this document did exactly that, in the Technology Stack and Performance Considerations sections) was itself a finding this document resolves, not a real either/or choice. Per the project's own stated preference for native Swift concurrency primitives, and absent any concrete need for `Progress`'s system-level integration (Dock icon, Finder, menu-bar activity — nothing in `SPEC.md` currently asks for that), the answer is: don't use `Progress` at all.

**The contract** (`ACCore/Models/`, SPEC.md §4.17):

```swift
public struct ProgressUpdate: Sendable, Equatable {
    public let fractionCompleted: Double
    public let message: String?
}

public enum OperationProgress<Success: Sendable>: Sendable {
    case progress(ProgressUpdate)
    case completed(Success)
}
```

A Repository/Use Case method that reports progress returns `AsyncThrowingStream<OperationProgress<T>, Error>`, yielding zero or more `.progress` events followed by exactly one `.completed(T)` before finishing (or throwing). Callers consume it with `for try await event in ...`.

**Cancellation is cooperative `Task` cancellation — no separate cancel API.** The ViewModel wraps the consuming loop in a `Task` it holds onto; cancelling that `Task` (e.g. the user dismisses the import sheet) is observed inside the Data-layer implementation via `Task.isCancelled` checks at natural boundaries (chunk-by-chunk in a streaming read, page-by-page in export) and/or the stream's `onTermination` closure. This is standard structured concurrency — no bespoke cancellation-token type is introduced.

**Applied to every named long-running operation:**

| Operation | Contract | Notes |
|---|---|---|
| WAV import (`ImportAudioUseCase`) | `AsyncThrowingStream<OperationProgress<AudioAsset>, Error>` | |
| Waveform overview generation (`GenerateWaveformPeaksUseCase`) | `AsyncThrowingStream<OperationProgress<WaveformPeaks>, Error>` | runs immediately after import — SPEC.md §4.15 |
| Waveform on-demand detail (`GenerateWaveformDetailUseCase`) | plain `async throws -> [WaveformPeakBucket]`, **no progress stream** | a bounded time-range read is fast enough that a progress UI would be pointless ceremony — not every operation needs the full contract, but every operation that *does* report progress uses the same shape |
| Cue analysis (`DetectCuesUseCase`) | `AsyncThrowingStream<OperationProgress<[Cue]>, Error>` | |
| PDF export | `AsyncThrowingStream<OperationProgress<URL>, Error>` | via `ExportCueSheetUseCase`/`ExportRepository` |
| XLSX export | `AsyncThrowingStream<OperationProgress<URL>, Error>` | same Use Case/Repository as PDF — one `ExportFormat` parameter, not a separate contract per format (rule 2) |
| Autosave | plain `async throws -> Void`, **no progress stream** | small, fast, debounced writes — not long-running in the sense this contract exists for. If autosave ever becomes slow enough to need progress (unlikely), it adopts the same contract then, not a bespoke one |

## Rules for Future Development

1. **Respect the dependency rule.** `ACCore` stays framework-free. If a new feature seems to require importing `AVFoundation`/`SwiftData`/etc. into Domain or Presentation, the fix is a new Repository protocol, not an exception.
2. **New export formats** (e.g., CSV, JSON) are added as a new `ExportRepository` implementation plus a case in the domain `ExportFormat` type — never as a format-specific branch inside a ViewModel or View.
3. **New audio analysis techniques** are added inside `ACAudioKit`, behind the existing `AudioAnalysisRepository` protocol. The rest of the app should never need to change when detection heuristics improve.
4. **Don't add a third-party dependency without checking:** App Sandbox compatibility, static-linkability (no dynamic code loading), and whether it's actively maintained. `libxlsxwriter` was chosen under these constraints — any replacement must clear the same bar.
5. **The data model targets the SUISA *WA Film* declaration format** (see `SPEC.md` for the field-by-field source mapping). Any change to `Setup`/`Cue`/`CueRightHolder` fields must be checked against that source form and against `SPEC.md`, and `SPEC.md` updated in the same change. Don't add fields from other PROs' cue-sheet conventions (e.g., US-style ASCAP/BMI usage categories like "Background Instrumental") unless a real second target format is scoped — SUISA's declaration doesn't use them.
6. **Every package gets its own test target.** `ACCore` must be 100% unit-testable with no I/O. Data-layer packages are tested against real fixture WAV/output files, not mocks of the file system. ViewModels are tested against fake Use Cases via `ACTestSupport`.
7. **No premature abstraction.** Don't generalize a component or protocol for a hypothetical second use case — promote to `ACDesignSystem` or introduce a new protocol only when a second real caller exists. This includes not splitting `ACCore` into separate Domain/Application packages until a real, concrete reason exists (see MVVM section above).
8. **Keep this file current.** If an architectural decision here changes, update this file in the same change — it is the project's persistent memory, not a one-time snapshot.
9. **The domain model (`ACCore/Models/`) is the stable public application model.** Once a milestone implements it, any change to a model's fields or cases requires updating `SPEC.md`, `CLAUDE.md`, and `ROADMAP.md` together, in the same change. This generalizes rule 5 (specific to the SUISA-mapped fields) to every domain type, including app-internal ones like `AudioAsset`, `Timecode`, and `Settings`.
10. **Use Cases are stateless structs; ViewModels and Repository implementations own all mutable state.** See "Use Cases Are Stateless" above. Don't add a stored `var` to a Use Case as a shortcut — that reintroduces the shared-mutable-state race that `DependencyContainer`'s singleton-Use-Case wiring is specifically designed to avoid.
11. **ViewModels are constructed only via `DependencyContainer` factory methods, called only from the App target's navigation root.** Views never hold or look up `DependencyContainer` themselves. See "Dependency Injection Pattern" above.
12. **Every long-running operation reports progress via `AsyncThrowingStream<OperationProgress<T>, Error>`, never Foundation's `Progress`.** A new milestone that adds a long-running operation (a new export format, a new analysis pass) reuses this exact contract — see "Long-Running Operations: Progress & Cancellation" above. Don't invent a bespoke progress enum/callback per milestone.
13. **`ACDesignSystem` components that display domain-derived data take a local adapter type, never an `ACCore` type directly.** `CueTableView`'s row protocol and `WaveformView`'s `WaveformDisplayData` are the established instances of this pattern — follow it for the next one rather than deciding fresh each time. See Design System section above.
14. **Minimum deployment target is macOS 14.0 — don't lower it without updating this doc.** It's the floor required by `SwiftData` and `@Observable`, both already locked-in architectural choices (see "Deployment Target," above), not an independent decision to re-litigate per milestone. Raising it later is fine, and cheap, the moment a real newer-OS-only API is needed; lowering it isn't possible without dropping one of those two frameworks.
15. **The app is multi-window by design (one `Project` per window) — don't reintroduce a single-window/single-active-Project assumption as an incidental side effect of another milestone.** See "Document & Window Model," above, for the full architecture: the Library scene, `WindowGroup(for: Project.ID.self)`, per-window `AppState`, the `OpenProjectWindowRegistry` duplicate-open guard, and per-`Project.ID` save serialization. A milestone that touches window/navigation state must preserve all four of those, not just whichever one it happens to interact with directly.
16. **Don't add `Codable` conformance to a domain type without documenting the specific, real use case it serves, in the same change.** See "Domain Model Value-Type Conformances," above — this generalizes rule 7 (no premature abstraction) to this specific, previously-recurring case.
