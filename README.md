# AutoCue

**AutoCue** (working title) is a native macOS application that generates Swiss film/TV cue sheets from WAV audio files. It parses embedded audio metadata and performs signal analysis to detect musical cues, then produces a cue sheet compliant with the format SUISA (Swiss authors'/publishers' rights society) requires for royalty distribution — exportable as PDF and XLSX.

## Status

**Pre-implementation.** The architecture, domain model, and roadmap have been through a full review-and-correction pass (see `docs/DECISIONS.md`) before any application feature work begins. Two small dependency-validation spikes exist ahead of schedule — real, tested code proving out the riskiest architectural bets early — but no application feature, screen, or business logic has been built yet. See `ROADMAP.md` for what's next.

## What it does

- Imports a WAV file (up to ~3 hours) and reads its embedded markers (`cue`/`labl`/`ltxt`/`bext` chunks).
- Detects candidate musical cues via embedded markers and/or silence-gap signal analysis.
- Lets the user confirm/edit cues and attach right-holder (composer, author, arranger, publisher) information and rights shares.
- Validates the data set against SUISA's rules before export.
- Exports a cue sheet as a pixel-accurate PDF matching SUISA's *WA Film* form, and as a tabular XLSX for internal re-editing.

Full functional/data-model detail: `SPEC.md`. This is a rights-accounting declaration tool, not a US-style (ASCAP/BMI) scene-by-scene cue log — see `SPEC.md` §2.1 before assuming otherwise.

## Documentation map

Each doc in this repo has exactly one job — see `CONTRIBUTING.md`'s intro for the full reading order and reasoning. Short version:

| File | Answers |
|---|---|
| `CLAUDE.md` | *How* should the software be built — architecture, module boundaries, conventions |
| `SPEC.md` | *What* does the product do — data model, SUISA compliance target |
| `ROADMAP.md` | *What* gets implemented, and *when* |
| `CONTRIBUTING.md` | *How* development is actually performed, day to day |
| `docs/DECISIONS.md` | *Why* key architectural decisions were made |
| `docs/DefinitionOfDone.md` | *When* a piece of work counts as complete |
| `docs/REVIEW.md` | Ongoing architecture/code-quality review log, appended after each Deliverable |

## Technology

Swift, SwiftUI, SwiftData, `@Observable`, Swift Concurrency, `Accelerate`/vDSP for DSP, Core Graphics/Core Text for PDF generation, `libxlsxwriter` for XLSX. Native only — no cross-platform UI framework. Full stack rationale: `CLAUDE.md`, "Technology Stack."

Minimum deployment target: **macOS 14.0 (Sonoma)**.

## Building

No Xcode workspace exists yet (`ROADMAP.md` Deliverable D1 creates it). Two standalone SPM packages exist ahead of schedule and can be built/tested independently:

```sh
cd Packages/ACCore && swift test
cd Packages/ACExport && swift test
```

CI (`.github/workflows/ci.yml`) runs both of these plus formatting/lint/architecture-boundary checks on every push.

## License

**No license file, deliberately — not an oversight.** AutoCue is closed-source, proprietary software intended for commercial distribution via the Mac App Store, not open-source redistribution. Under copyright law, the absence of a `LICENSE` file means all rights are reserved by default: nobody may copy, modify, or redistribute this code without explicit permission. If open-sourcing part of this project (e.g., the SUISA form-layout logic) is ever wanted, that's a separate, deliberate decision requiring its own legal review — not something to default into by adding a template license file now.
