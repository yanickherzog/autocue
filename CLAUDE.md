# CLAUDE.md

Permanent project memory for Claude Code. Read this before making any architectural, structural, or dependency decision in this repository. If a change conflicts with something written here, stop and raise it rather than silently deviating.

## Project Overview

**AutoCue** (working title) is a native macOS application that generates film/TV cue sheets automatically from WAV audio files. It parses embedded audio metadata and performs signal analysis to detect cues, then produces formatted, exportable cue sheets.

Core constraints that shape every decision below:
- Must run fully offline — no network dependency anywhere in the pipeline.
- Must handle WAV files up to ~3 hours (multi-GB) without loading them fully into memory.
- Must stay App Store-eligible (sandboxed, no disallowed APIs, no dynamically loaded code).
- Must remain maintainable by a small team long-term — prefer fewer, well-separated moving parts over cleverness.

## Technology Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift | Single language across the whole app — no bridge layers |
| UI | SwiftUI (AppKit interop only when SwiftUI has a genuine gap) | `NavigationSplitView` as the app shell |
| State | `@Observable` (Observation framework) | Not legacy `ObservableObject`/`@Published` — finer-grained view invalidation |
| Concurrency | Swift Concurrency (async/await, actors, `AsyncStream`/`Progress`) | No GCD/completion-handler code in new work |
| Audio I/O | `AVFoundation` (`AVAudioFile`) + a custom RIFF/BWF chunk parser | AVFoundation streams; the custom parser reads `cue`/`labl`/`ltxt`/`bext` chunks it doesn't expose |
| DSP | `Accelerate` (vDSP) | Required for silence/level detection to stay fast over hours of audio |
| Persistence | `SwiftData` | Source of truth for all persisted project data |
| PDF export | `PDFKit` / Core Graphics (`PDFContext`) / Core Text | Native, no dependency |
| XLSX export | `libxlsxwriter` (C, statically linked) | No first-party or mature pure-Swift *writer* exists; this is MIT-licensed, dependency-free at runtime, sandbox-safe as a static lib |
| Modularization | Local Swift Packages in one Xcode workspace | Compiler-enforced module boundaries, not just folder convention |
| Distribution | Xcode + SPM, App Sandbox entitlements | Direct path to notarization and App Store submission |

Do not introduce a cross-platform UI framework (Electron, Flutter, Tauri, Qt, MAUI). The whole point of this stack is native performance and a frictionless App Store path — don't trade that away later for "portability" without an explicit, discussed requirement change.

## MVVM + Clean Architecture

Three layers, strict dependency direction — **outer depends on inner, never the reverse**:

```
Presentation (Views + ViewModels)
        ↓ depends on
Domain (Models + Use Cases + Repository Protocols)   ← Foundation only, no Apple frameworks
        ↑ implemented by
Data (Audio, Export, Persistence services)
```

Rules that follow from this:
- `ACCore` (Domain) never imports `AVFoundation`, `SwiftData`, `PDFKit`, or `libxlsxwriter`. If you find yourself wanting to, the abstraction (a Repository protocol) belongs in `ACCore`; the import belongs in the Data package implementing it.
- Views never talk to Repositories or Use Cases directly — only to their ViewModel.
- ViewModels never import Data-layer packages — only `ACCore` (Use Case protocols) plus `ACDesignSystem` for shared UI.
- Business rules (e.g., how detected cues merge with embedded markers) live in Use Cases, not in ViewModels. A ViewModel orchestrates and holds view state; it does not decide domain logic.
- Concrete implementations are wired once, at app launch, in `DependencyContainer`. Nothing else constructs a concrete Repository — everything is injected via protocol.

## Folder / Package Structure

```
AutoCue.xcworkspace
│
├── AutoCue (App target — thin composition root)
│   ├── AutoCueApp.swift          @main, builds DependencyContainer
│   ├── AppState.swift             app-wide state (active window/project)
│   └── DependencyContainer.swift  wires concrete services → use cases → view models
│
├── Packages/
│   ├── ACCore/                    DOMAIN — pure Swift
│   │   ├── Models/                 Project, Setup, Cue, CueRightHolder, Person, Label, Party,
│   │   │                           Settings, AudioAsset, Timecode
│   │   ├── UseCases/                ImportAudioUseCase, DetectCuesUseCase, ExportCueSheetUseCase, ...
│   │   └── RepositoryProtocols/     ProjectRepository, AudioAnalysisRepository, ExportRepository
│   │
│   ├── ACAudioKit/                DATA — audio ingestion & analysis
│   │   ├── WAVParsing/              RIFF/BWF chunk reader
│   │   ├── Streaming/               AVAudioFile-based chunked reader
│   │   ├── Analysis/                vDSP silence/level detection
│   │   └── AudioAnalysisRepositoryImpl.swift
│   │
│   ├── ACExport/                  DATA — output generation
│   │   ├── PDF/                     PDFKit/CoreGraphics/CoreText renderer
│   │   ├── XLSX/                    libxlsxwriter wrapper
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
│   └── ACTestSupport/             shared fakes/fixtures used across package test targets
│
└── Features/                      PRESENTATION — screens, live in app target
    ├── ProjectLibrary/    (Views/ ViewModels/ Components/)
    ├── CueSheetEditor/    (Views/ ViewModels/ Components/)
    ├── Export/            (Views/ ViewModels/)
    └── Settings/          (Views/ ViewModels/)
```

`SwiftDataModels` are intentionally separate types from the `ACCore` domain models. Persistence schema is a Data-layer detail; it must never leak into Domain or Presentation. Always go through the `Mappers/` folder.

## Data Model (Finalized)

AutoCue targets the **Swiss SUISA cue-sheet standard** (official "Declaration of musical works for films and audiovisual productions" / *WA Film* form) as its compliance target, plus the fields SWISSPERFORM's audiovisual participation reporting shares with it. Full field-by-field detail, optionality, and the mapping back to the source SUISA form live in `SPEC.md` — treat that file as authoritative for schema questions, not this summary.

Model shape:
- **`Setup`** — one per `Project`. Production-level header info (title, producer, director, runtimes, production year, production type, declarant, attachments). Maps almost 1:1 to the SUISA form's top section.
- **`Cue`** — many per `Project`, ordered. One SUISA "musical work" entry: title, work number, duration, and its `[CueRightHolder]` list. Carries a few app-internal-only fields (`source`, `startTimecode`, `notes`) used for the auto-detection workflow — these are never exported to the SUISA document, since SUISA wants total usage duration per work, not on-screen position or usage category.
- **`CueRightHolder`** — sub-entity of `Cue`. A `Party` (composer/author/arranger/publisher) plus performance-broadcast and mechanical-rights percentage shares. Shares must sum to 100% per Cue, per share type — validated in a Use Case, never in the struct.
- **`Person`** / **`Label`** — individual vs. corporate right-holder identity, referenced everywhere the SUISA form allows "name, first name **or publishing company**" via a `Party` enum (`.person` / `.label`), never duplicated fields.
- **`Settings`** — app-level only (export language, default declarant, validation strictness, audio-analysis defaults). Not part of the SUISA document.
- **`Project`** — the persisted container: `Setup` (1:1), `[Cue]` (1:many), a project-scoped `[Person]`/`[Label]` right-holder directory, plus `AudioAsset` from the original architecture.

There is no separate persisted `CueSheet` type — the exportable cue sheet is just `Setup` + `[Cue]`, assembled on demand by `ExportCueSheetUseCase`. Don't reintroduce a `CueSheet` model unless a real need for a distinct persisted/derived shape shows up.

## Design System (`ACDesignSystem`)

- All visually reusable pieces (buttons, `WaveformView`, `CueTableView`, empty/loading/error states) live here — never duplicated inside a `Features/*/Components/` folder.
- Theme values (color, type scale, spacing) are tokens defined once in `Theme/`. Views reference tokens, never raw hex colors or magic numbers for spacing/fonts.
- `ACDesignSystem` has no knowledge of `CueSheet`, `Project`, or any domain type — it only knows generic display types (strings, numbers, closures/bindings). This is what keeps it reusable and, longer term, portable to another app or target (e.g., an iPad companion).

## Single Source of Truth

- **Persisted data**: `SwiftData`, accessed only through `ProjectRepository`. No other layer keeps its own cached copy of saved project state. List-style views should read live via `@Query` where practical rather than through a ViewModel-held snapshot.
- **Actively edited data**: the screen's ViewModel (e.g., `CueSheetEditorViewModel`) holds the one working copy of the `Setup` and `[Cue]` list being edited, and is the only thing allowed to mutate it. Writes flow back to `ProjectRepository` explicitly (debounced autosave) — never scattered `save()` calls from multiple places.
- **Audio-derived data**: the file on disk is the source of truth for raw audio; `AudioAsset` is a derived, immutable snapshot produced by `AudioAnalysisRepository`, not something reconstructed ad hoc in a View or ViewModel.
- If you ever need the same piece of state in two places, ask "which one owns it" and inject/observe from there — do not introduce a second variable that has to be kept in sync manually.

## Naming Conventions

- Local packages: `AC<Purpose>` (`ACCore`, `ACAudioKit`, `ACExport`, `ACPersistence`, `ACDesignSystem`, `ACTestSupport`).
- Types by role, suffix communicates the role:
  - Views: `<Feature>View` (`CueSheetEditorView`), reusable pieces just `<Thing>View`/`<Thing>Component` (`WaveformView`).
  - ViewModels: `<Feature>ViewModel` (`CueSheetEditorViewModel`).
  - Use cases: `<Verb><Noun>UseCase` (`DetectCuesUseCase`, `ExportCueSheetUseCase`).
  - Repository protocols: `<Noun>Repository` (`ProjectRepository`); implementations: `<Noun>RepositoryImpl`.
  - SwiftData schema types: suffix `Entity` or `Model` distinctly from the domain type of the same concept (e.g., domain `Project` vs. persistence `ProjectEntity`), so an accidental cross-layer import is obvious at the call site, not just at the import line.
- Files are named exactly after the primary type they contain — one primary type per file.
- Folders mirror architectural role (`Models/`, `UseCases/`, `RepositoryProtocols/`, `Views/`, `ViewModels/`), not feature-then-role-then-feature nesting.

## Reusable Component Philosophy

- Default a new UI piece to living inside the feature that needs it (`Features/<Feature>/Components/`).
- Promote it to `ACDesignSystem` the moment a second feature needs the same thing, or the moment it has no dependency on feature-specific domain types to begin with (e.g., a generic progress banner belongs in the design system on day one; a cue-specific row does not, until reused).
- A component belongs in `ACDesignSystem` only if it can be previewed and reasoned about with zero knowledge of `Project`/`Setup`/`Cue`. If it needs a domain type to make sense, it stays in `Features/`.
- Prefer composition (small components combined in a screen) over configurable mega-components with many boolean flags.

## Performance Considerations

- Never load a full WAV file into memory. All reads go through the streaming reader in `ACAudioKit/Streaming`, processing in bounded-size chunks.
- All DSP (silence detection, level metering) uses `Accelerate`/vDSP — no hand-rolled sample loops over large buffers.
- Long-running work (file import, cue detection, export) always runs off the main actor and reports progress incrementally (`AsyncStream`/`Progress`); the editor UI must remain interactive during a multi-hour-file scan.
- ViewModels are `@MainActor`; anything that touches audio I/O or file I/O is not.
- Use `@Observable` fine-grained invalidation correctly: keep large collections (e.g., all cues) structured so a single-row edit doesn't force a diff over the whole list — favor `Table`/`LazyVStack`-friendly identifiable rows over recomputing whole-array transformations on every keystroke.
- Autosave is debounced, not triggered on every keystroke/edit.

## Rules for Future Development

1. **Respect the dependency rule.** `ACCore` stays framework-free. If a new feature seems to require importing `AVFoundation`/`SwiftData`/etc. into Domain or Presentation, the fix is a new Repository protocol, not an exception.
2. **New export formats** (e.g., CSV, JSON) are added as a new `ExportRepository` implementation plus a case in the domain `ExportFormat` type — never as a format-specific branch inside a ViewModel or View.
3. **New audio analysis techniques** are added inside `ACAudioKit`, behind the existing `AudioAnalysisRepository` protocol. The rest of the app should never need to change when detection heuristics improve.
4. **Don't add a third-party dependency without checking:** App Sandbox compatibility, static-linkability (no dynamic code loading), and whether it's actively maintained. `libxlsxwriter` was chosen under these constraints — any replacement must clear the same bar.
5. **The data model targets the SUISA *WA Film* declaration format** (see `SPEC.md` for the field-by-field source mapping). Any change to `Setup`/`Cue`/`CueRightHolder` fields must be checked against that source form and against `SPEC.md`, and `SPEC.md` updated in the same change. Don't add fields from other PROs' cue-sheet conventions (e.g., US-style ASCAP/BMI usage categories like "Background Instrumental") unless a real second target format is scoped — SUISA's declaration doesn't use them.
6. **Every package gets its own test target.** `ACCore` must be 100% unit-testable with no I/O. Data-layer packages are tested against real fixture WAV/output files, not mocks of the file system. ViewModels are tested against fake Use Cases via `ACTestSupport`.
7. **No premature abstraction.** Don't generalize a component or protocol for a hypothetical second use case — promote to `ACDesignSystem` or introduce a new protocol only when a second real caller exists.
8. **Keep this file current.** If an architectural decision here changes, update this file in the same change — it is the project's persistent memory, not a one-time snapshot.
