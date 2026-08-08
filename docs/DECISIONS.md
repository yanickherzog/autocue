# AutoCue — Architecture Decisions

Lightweight decision log for explicitly-approved architectural calls that aren't obvious from reading `CLAUDE.md`/`SPEC.md` alone — i.e. decisions that were deliberated, not just defaulted into. Not a full ADR process; one entry per decision, newest last. Each entry states the decision, why, and what it rules out.

---

## 2026-08-08 — Split `Features/` into its own package (`ACFeatures`)

**Decision:** `Features/` is not app-target code. It is its own local Swift package, `ACFeatures`, depending only on `ACCore` and `ACDesignSystem` — never on `ACAudioKit`, `ACExport`, or `ACPersistence`. This is the permanent structure, not a placeholder.

**Why:** The original plan kept `Features/` inside the `AutoCue` app target directly. Because the app target legitimately links `SwiftData`/`AVFoundation` (for `DependencyContainer`), nothing would have stopped a screen from importing them directly — the "ViewModels never touch the Data layer" rule would have been convention-enforced only, on exactly the layer most prone to accumulating violations across dozens of independently-built Feature milestones. Making `ACFeatures` a real package with a restricted `Package.swift` dependency list turns that into a genuine compile error instead of a code-review miss. This was the right call to make immediately, before any Feature code exists — cheap now, expensive as a retrofit once 10+ milestones' worth of Views already assume app-target placement.

**Rules out:** Feature Views/ViewModels ever depending on a Data-layer package or `DependencyContainer` directly (see `CLAUDE.md`, "Dependency Injection Pattern"). Does not fully rule out raw `import SwiftData`/`AVFoundation` inside `ACFeatures` — SPM can't gate system-framework imports regardless of package layout (see `CLAUDE.md`, "Package Dependency Graph" limitation note); that residual gap still needs a lint/CI check, not yet built.

**Full architectural detail:** `CLAUDE.md` (Package Dependency Graph, Dependency Injection Pattern, Folder/Package Structure).

---

## 2026-08-08 — Support drop-frame timecode from v1, not deferred

**Decision:** `TimecodeFrameRate` distinguishes `.fps29_97NonDrop` and `.fps29_97Drop` as of the first implementation of `Timecode`, with real SMPTE drop-frame arithmetic (not a stub), rather than shipping non-drop-only and adding drop-frame later.

**Why:** This reverses an earlier "known gap" in `SPEC.md` §4.9 that deferred drop-frame as out-of-scope for v1. The reasoning for deferring it was rule 7 (no premature abstraction / don't build for a hypothetical future need) — but drop-frame isn't a hypothetical here: cue sheets built from NTSC-derived material (29.97fps) are a realistic, known case for this app's domain, not a speculative one. More importantly, the retrofit cost is asymmetric: `Timecode`/`TimecodeFrameRate` are foundational value types that `Cue.startTimecode`, `EmbeddedMarker.position`, and the entire editor UI's position-display logic will depend on directly. Adding a second timecode "mode" after dozens of call sites already assume non-drop-only formatting math is a much larger, more error-prone change than getting the enum shape and conversion algorithm right once, before anything depends on it. This is the inverse of rule 7's usual case: rule 7 exists to prevent generalizing for a use case that might never arrive; here the use case (NTSC-sourced audio) is concrete and the cost curve clearly favors doing it now.

**Rules out:** A future migration/schema change to `TimecodeFrameRate` solely to add drop-frame support once real cue data already references the non-drop-only version.

**Full architectural + arithmetic detail:** `SPEC.md` §4.9. Implementation: `Packages/ACCore/Sources/ACCore/Models/{Timecode,TimecodeFrameRate}.swift`; verified by `Packages/ACCore/Tests/ACCoreTests/TimecodeTests.swift`.

---

## 2026-08-08 — `libxlsxwriter` validated now, via a real spike, not assumed until M28

**Decision:** `ACExport` depends on `libxlsxwriter` as a normal remote SPM package (its own upstream `Package.swift`, pinned `from: "1.2.4"`), and that decision has been verified with a real, runnable smoke test rather than left as an untested assumption inherited from `CLAUDE.md` rule 4 until `ROADMAP.md` M28.

**Why:** This dependency is a locked-in architectural choice that 27 milestones of downstream export work would otherwise be built on top of before it was ever actually compiled. That's backwards risk-ordering for the one third-party native dependency in the whole stack. Verified directly: it builds and links as an SPM C target (system `zlib` only, no other dynamic dependencies), targets macOS 14 cleanly, and a smoke test (`XLSXFeasibilitySpike` + `XLSXFeasibilitySpikeTests`) writes a real workbook with a string cell and a number cell, confirmed via the ZIP/OOXML signature and the actual `sheet1.xml`/`sharedStrings.xml` contents — not just "the build succeeded."

**App Sandbox: real kernel-enforced verification, superseding an earlier inconclusive attempt.** An initial attempt used `sandbox-exec` with a custom profile to approximate App Sandbox restrictions; that attempt was invalid, not just incomplete — `sandbox-exec` doesn't function at all in that execution environment (confirmed against a trivial control case, `/bin/echo`, which failed identically). That was correctly flagged as unresolved rather than treated as a pass, and has since been superseded by a real test: the spike binary was packaged into a minimal `.app` bundle, ad-hoc code-signed with the actual `com.apple.security.app-sandbox` entitlement (`codesign --sign - --entitlements ...`), and run directly. Results:
- A write to an unauthorized location (`~/Desktop`) was genuinely **blocked** by the kernel (`Operation not permitted`), and `libxlsxwriter` surfaced this as a normal returned error code — not a crash. This confirms the sandbox was actually active and enforced, not silently bypassed (macOS also lazily created a real container at `~/Library/Containers/com.autocue.xlsxspike/`, which only happens for a genuinely sandboxed process).
- A write to a location the sandbox always permits a sandboxed app (its own container) **succeeded**, producing a fully valid workbook with correct cell contents — confirming `libxlsxwriter`'s internal temp-file creation (which checks `TMPDIR` first, per source review) works correctly under real, not approximated, sandbox enforcement, not just in source-code theory.

**What's still open (narrower than before):** this tested the baseline case (a sandboxed process writing inside its own container). It did not test the real app's actual export flow — writing to a location the user picked via `NSSavePanel`, which grants access dynamically through the Powerbox rather than a static entitlement, and isn't practical to simulate in a headless spike. There's no specific reason to expect `libxlsxwriter` to behave differently for a Powerbox-granted path than for its own container (both are just an allowed `write()` target from the sandboxed process's point of view), but this hasn't been *tested*, so it isn't claimed as verified. **Action:** confirm the real `NSSavePanel` → write flow once the real app target and its `AutoCue.entitlements` exist (`ROADMAP.md` M11 onward) — this is a small, low-risk confirmation at that point, not a re-litigation of the dependency choice.

**Rules out:** Treating "we chose `libxlsxwriter` under CLAUDE.md rule 4" as sufficient justification without ever having compiled it, and treating an inconclusive `sandbox-exec` attempt as if it were evidence either way — it wasn't, and this entry no longer relies on it.

**Full detail:** `CLAUDE.md`, "Export Architecture (PDF & XLSX)." Spike: `Packages/ACExport/Sources/ACExport/Spike/XLSXFeasibilitySpike.swift`; tests: `Packages/ACExport/Tests/ACExportTests/XLSXFeasibilitySpikeTests.swift`. Sandbox verification artifacts (scratch, not committed to the repo): a minimal `.app` bundle + `entitlements.plist`, built and run ad hoc for this check.

---

## 2026-08-08 — Single progress/cancellation contract: `AsyncThrowingStream<OperationProgress<T>, Error>`, not Foundation `Progress`

**Decision:** Every long-running operation (WAV import, waveform generation, cue analysis, PDF/XLSX export) reports progress through one shared contract — `AsyncThrowingStream<OperationProgress<T>, Error>`, where `OperationProgress<T>` is `.progress(ProgressUpdate)` or `.completed(T)` — and cancellation is plain cooperative `Task` cancellation. Foundation's `Progress` class is not used anywhere in the app.

**Why:** `CLAUDE.md` previously referenced `AsyncStream` and `Progress` side by side as if they were interchangeable options for the same job. They aren't: `Progress` is a KVO-based Objective-C class with its own observation and cancellation model that doesn't compose with `async`/`await` — there's no way to `for await` over a `Progress`, and its cancellation tree is independent of Swift's structured-concurrency `Task` cancellation. Picking one, consistently, before any of the six operations that need this are built, avoids each milestone quietly inventing its own slightly-different progress-reporting shape (exactly the kind of drift `CONTRIBUTING.md` warns about). Native Swift Concurrency was chosen over `Progress` because nothing in `SPEC.md` currently asks for `Progress`'s main advantage (system-level UI integration — Dock icon, Finder, menu bar); if that's ever wanted, it can be layered on top of the stream-based contract later without changing it.

**Rules out:** Any future milestone introducing `Progress`, a bespoke per-operation progress enum, or a custom cancellation-token type for a new long-running operation — new operations extend the table in `CLAUDE.md`'s "Long-Running Operations" section, they don't add a new pattern to it.

**Full detail:** `CLAUDE.md`, "Long-Running Operations: Progress & Cancellation." Types: `SPEC.md` §4.17.

---

## 2026-08-08 — Waveform data: bounded overview + on-demand detail, not a full mip-map

**Decision:** `WaveformPeaks` (`ACCore`) is a fixed-resolution (4096-bucket), mono, persisted summary of the whole file, generated once at import. Zoomed-in detail views compute peaks on demand for just the visible range, uncached. No multi-resolution mip-map pyramid is built.

**Why:** `ACDesignSystem/Components/WaveformView` was named in `CLAUDE.md`'s folder structure from the start with no data model behind it — nothing in the audio pipeline (M16–M19) produced anything for it to render. A fixed bucket count keeps the persisted overview's memory cost constant (~32KB) regardless of whether the source file is 3 minutes or 3 hours, which is what lets it live as a plain bounded `ACCore` value type without violating the "never load a full WAV into memory" rule. A full mip-map (multiple cached resolutions, as some DAWs build) was considered and rejected as more machinery than this app's actual workflow needs — AutoCue is for confirming/adjusting cue boundaries, not sample-accurate waveform editing — so a two-tier design (bounded overview, cheap uncached on-demand detail) covers the real use case without the added maintenance surface of a resolution pyramid.

**Rules out:** Adding a raw/downsampled sample buffer to `AudioAsset` itself (that invariant, from an earlier revision, stands) — waveform data is a deliberate sibling field on `Project`, not folded into `AudioAsset`. Also rules out treating stereo/per-channel waveform display as in scope for v1 — mono mixdown only, flagged as a known future enhancement.

**Full detail:** `SPEC.md` §4.15; consumption pattern: `CLAUDE.md`, Design System section (`WaveformDisplayData` adapter type).

---

## 2026-08-08 — "Review & Export" is one persistent tab, not Review-tab-plus-a-sheet

**Decision:** The third navigation destination is a single, always-accessible "Review & Export" tab (`ReviewAndExportView`), showing both the validation summary and the export controls inline. Export is never presented as a `.sheet()`.

**Why this entry exists:** A prior pass at the Navigation Model made Export a modal sheet triggered from Review, reasoning that export is "a triggered action with a result," not a place to navigate to and stay. That reasoning was self-consistent but wrong for this app: the original product brief explicitly specifies **three tabs — Setup, Cues, Review & Export — always visible and accessible at any time, like browser tabs.** The sheet interpretation was never actually validated against that brief before being written down; this entry corrects it back to what was originally specified, not a new product decision being made here. Combining Review and Export into one destination (rather than four separate tabs) is independently justified on its own architectural merits too: export readiness is *derived from* validation state, so the two were never fully independent concerns, and one `ReviewAndExportViewModel` avoids two ViewModels coordinating shared state across a presentation boundary.

**Rules out:** Any milestone reintroducing a `.sheet()`-presented export flow, or treating Export as reachable only from within Review rather than as its own always-visible tab.

**Full detail:** `CLAUDE.md`, "Navigation Model." Affected milestones: `ROADMAP.md` M26, M29.

---

## 2026-08-08 — Multi-window architecture (`WindowGroup(for: Project.ID.self)`), superseding single-window

**Decision:** AutoCue is multi-window: a singleton Library scene for browsing/opening Projects, plus a `WindowGroup(for: Project.ID.self)` scene allowing any number of Project windows open simultaneously, each independently editing one `Project`. Duplicate opens of the same `Project` are prevented by an explicit app-wide `OpenProjectWindowRegistry` (focus the existing window instead of opening a second one). Save serialization in `ProjectRepositoryImpl` is per-`Project.ID`, not a single app-wide lock.

**Why this entry exists, and why the decision reversed:** A prior pass at the Document & Window Model chose single-window deliberately, reasoning that AutoCue is "a single-composer desktop tool," and that a single window eliminates the same-project-open-twice and cross-window-save-race problems *by construction* rather than by added coordination logic — a real, valid piece of reasoning at the time, not a mistake. It was reversed by an explicit product requirement, not by discovering a flaw: the ability to open two (or more) cue-sheet Projects side by side in separate windows, to compare or reference between them, which the single-window design explicitly precluded (it was even named as a "known v1 limitation" in that revision, rather than silently overlooked). That limitation is now removed as a real, deliberately-designed capability rather than a documented gap.

Reversing single-window meant the two problems it solved for free had to be solved explicitly instead, not simply left unsolved:
- **Same-project-open-twice** is now prevented by `OpenProjectWindowRegistry`, an app-wide registry checked before any window opens, focusing the existing window instead of duplicating it.
- **Cross-window save races** are now prevented by making `ProjectRepositoryImpl`'s write serialization explicitly per-`Project.ID` rather than relying on there only ever being one Project loaded at all. This is finer-grained than the single-window design's global serialization, and correctly so — under multi-window, a slow save for one Project must never block an unrelated save for a different Project in another window.

`WindowGroup(for: Project.ID.self)` was chosen over a literal `DocumentGroup` (the mechanism named in the request that prompted this reversal) because `DocumentGroup` presumes file-backed documents (`FileDocument`/`ReferenceFileDocument`), which doesn't match AutoCue's actual persistence model — `Project`s are rows in one shared SwiftData store behind `ProjectRepository`, an already-validated architectural decision from earlier in this project that this reversal does not reopen. `WindowGroup(for: Project.ID.self)` is SwiftUI's supported mechanism for the same user-facing outcome (multiple windows, one data item each) without requiring a file-per-project persistence model.

**Note on process:** the original single-window decision was written into `CLAUDE.md` directly but was never logged here at the time — an omission in the batch that made it, corrected retroactively by this entry, which records both the original reasoning and its reversal together.

**Rules out:** A future milestone reintroducing a single global `AppState`/`selectedProjectID`, or a save-serialization scheme that isn't scoped per-`Project.ID`.

**Full detail:** `CLAUDE.md`, "Document & Window Model." Affected milestones: `ROADMAP.md` M11, M12.
