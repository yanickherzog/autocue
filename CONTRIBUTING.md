# Contributing to AutoCue

This guide assumes you're comfortable on macOS but relatively new to Swift and to working with Claude Code. It tells you *how to work* on this project day to day. For everything else, each doc in this repo has exactly one job — read them in this order before touching code:

1. `CLAUDE.md` — **how** the software should be built: architecture rules, module boundaries, naming conventions. This is also Claude Code's persistent memory for this repo — if you and Claude ever disagree about how something should be structured, `CLAUDE.md` is the tiebreaker.
2. `SPEC.md` — **what** the product does: the finalized data model and SUISA compliance target. Not concerned with UI flows or code structure at all.
3. `ROADMAP.md` — **what gets implemented and when**: the Deliverable/Task list this whole workflow is built around.
4. `docs/DECISIONS.md` — **why** the key architectural calls were made — the record of what was considered and rejected, so a later session doesn't silently re-litigate a decision that already has a reason behind it.
5. `docs/DefinitionOfDone.md` — **when** a piece of work actually counts as finished. The checklist this document's own rules point back to.
6. `docs/REVIEW.md` — an ongoing log appended after each Deliverable: architecture/code-quality observations, technical debt, refactoring suggestions. Read the most recent few entries before starting new work — they're often more current than this file.

This document (`CONTRIBUTING.md`) is the odd one out on purpose: it's process, not product — it doesn't define architecture, schema, milestones, or decisions, only how those other documents get used day to day. If you find yourself wanting to state an architecture rule here, it belongs in `CLAUDE.md` instead.

---

## 1. Work on one Deliverable at a time

`ROADMAP.md` isn't a wish list — it's the unit of work, structured as **Deliverables** (D1, D2, …), each with nested **Tasks** underneath. A Deliverable is the real "one coherent vertical slice" unit; a Task is the sub-step within it. Roughly: one Deliverable = one Claude Code session (sometimes two, for a large one) = the Deliverable's own **Suggested Commit Boundary** (each Deliverable states how many commits it's worth — see `ROADMAP.md`).

- Before starting, read the Deliverable's Goal, Dependencies, Tasks, Acceptance Criteria, Testing Requirements, and Documentation Requirements in full. If a dependency Deliverable isn't actually done, stop and finish that first — don't skip ahead "because it's quick," you'll just end up debugging two half-finished things at once.
- Don't let a session drift into the next Deliverable. If you're mid-D7 (Setup screen) and realize you also want to fix something in D5 (design tokens), that's a *second* session/branch, even if it's small. Finishing one thing cleanly beats two things half-done.
- A Deliverable is done when `docs/DefinitionOfDone.md`'s checklist is satisfied for it, not when it "looks right." Several Acceptance Criteria explicitly say "manually verified" — actually run the app and do that step, don't assume the code is correct because it compiles.
- If a Deliverable turns out to be bigger than it looked once you're in it, stop and split it along its own Task boundaries rather than pushing through — a 400-line commit is much harder to review than two 150-line ones.
- After finishing a Deliverable, append an entry to `docs/REVIEW.md` per its template — this is part of the Deliverable, not an optional extra step, and it's how the next session (yours or Claude's) inherits what you actually noticed while building it.

**With Claude Code specifically:** open a session by pointing it at the Deliverable (e.g. "let's do D7 from ROADMAP.md"), not by describing the feature from memory — the roadmap entry already encodes the task list, acceptance criteria, and documentation requirements, so re-describing it invites drift from what was actually planned.

## 2. Avoiding technical debt

Debt on this project almost always means one thing: a shortcut that breaks the dependency rule in `CLAUDE.md` ("outer depends on inner, never the reverse"). It's easy to introduce by accident because it still compiles — Swift won't stop you from importing `AVFoundation` into `ACCore`, only your discipline (and, as of this batch, CI — see §8 below) will.

Concrete rules:
- **Don't stub something "to come back to later."** If a Task needs a `Person` picker, build the real (if minimal) picker — don't hardcode a fake person and leave a comment. Half-built features are where debt hides, because they look done in a diff review.
- **No `// TODO` without a `ROADMAP.md` Deliverable/Task ID next to it.** A bare TODO is a promise nobody's tracking. `// TODO(D11.3): handle arranger authorization flag` is fine because it's traceable; `// TODO: fix this later` is not.
- **Don't skip a test to move faster.** This is more important with AI-assisted coding, not less — Claude can produce a lot of plausible-looking code quickly, and untested code you didn't personally verify is exactly where debt compounds silently.
- **Don't add a field, enum case, or dependency that isn't in `SPEC.md`/`CLAUDE.md` without updating those files in the same change.** An undocumented schema change is debt the moment it's committed, because the next session (yours or Claude's) will trust the doc over the code.
- **Don't make an architectural call without logging it, if it's the kind of thing a future session might reasonably second-guess.** Not every decision needs an entry in `docs/DECISIONS.md` — see that file's own guidance on what qualifies — but a real trade-off (a library choice, a reversed earlier decision, a "we considered X and rejected it because Y") does.

## 3. When to refactor instead of adding code

Default to adding code. Refactor when one of these is true, not on a hunch:

- **The rule of three.** You're about to write the third near-identical version of something (a third row-building function, a third "fetch and map" block). The first two times, duplication is fine and even preferable — you don't know the right abstraction yet. The third time, extract it.
- **You can't meet the Deliverable's acceptance criteria without touching unrelated code.** E.g., D10 needs `CueTableView` in `ACDesignSystem` to take no `ACCore` type — if the existing draft component was written with a `Cue` parameter baked in, that's not a new feature, it's a pre-existing violation you need to fix first.
- **A file already violates `CLAUDE.md`.** If you open a file to add one field and notice it's importing something it shouldn't, fix the violation before adding to it — don't build new work on a broken foundation.

When you do refactor, **keep it a separate commit from the feature work**, even in the same session. "Move X" and "add Y" reviewed together hides both.

Don't refactor for a hypothetical future ("this might need to support more formats someday"). `CLAUDE.md` rule 7 already says this: promote/generalize only when a second real caller exists.

## 4. Organizing commits

One commit per logical change, matching Conventional Commits (`type(scope): summary`), the same style `ROADMAP.md`'s suggested commit messages use:

```
feat(cue-sheet): add per-cue right-holder editing with role and share inputs
fix(audio-kit): correct off-by-one in silence-gap boundary detection
refactor(core): extract share-sum validation into its own use case
test(export): add PDF pagination test for >5 cues
chore: bump minimum deployment target to macOS 14
```

Rules:
- **Never bundle a refactor and a feature in one commit.** If you had to reshape something to add the feature, that's two commits: the reshape, then the addition on top of it.
- **The message explains *why*, not *what*** — the diff already shows what changed. "fix(audio-kit): correct off-by-one in silence-gap detection" is useful; "fix bug" or "update SilenceDetector.swift" is not.
- **A commit should leave the tree buildable and tests passing, and CI green.** Don't commit "part 1 of 3" if part 1 doesn't compile — squash locally before committing if you were exploring.
- Match commits to a Deliverable's stated **Suggested Commit Boundary** in `ROADMAP.md` where possible — it already tells you whether that Deliverable is naturally one commit or several (e.g., model + tests, then wiring).

## 5. Writing tests

If you're new to Swift testing: a test is a function that calls the code under test and asserts on the result, in a `Tests/<Target>Tests/` folder mirroring `Sources/<Target>/`. This project uses `XCTest` for everything below — see §7 for the small, separate layer of UI/integration tests that use `XCUITest` instead.

What to test, by layer (this follows directly from `CLAUDE.md`'s architecture):
- **`ACCore` (Domain):** the easiest and most important tests in the project — pure functions/structs, no I/O, no mocking needed. Every use case and every validation rule (share sums, required fields) needs a direct unit test. If an `ACCore` test needs a mock, something's wrong — it should need nothing but plain values.
- **Data-layer packages (`ACAudioKit`, `ACExport`, `ACPersistence`):** test against *real* fixtures, not mocks of the file system — a real small WAV file, a real in-memory `ModelContainer`. Mocking the thing you're supposed to be testing (file I/O, SwiftData) just proves your mock works, not your code.
- **ViewModels:** test against the fakes in `ACTestSupport` (`InMemoryProjectRepository`, etc.), never against real `AVFoundation`/`SwiftData`. A ViewModel test should be fast and shouldn't touch disk.
- **Views:** still not *unit* tested — see §7 for why a small number of them get *integration/UI* test coverage instead, which is a different tool for a different purpose, not a contradiction of this rule.

Practical habits:
- Write the test in the same sitting as the code, not after the whole Deliverable is "done" — if you write `ValidateCueRightHolderSharesUseCase` and its test back to back, you'll catch the boundary cases (0 right-holders, shares summing to 99.9%) while you still remember them.
- Name tests after the behavior, not the method: `sharesNotSummingTo100PercentFailsValidation`, not `testValidate2`.
- Test the public protocol/behavior, not private internals — if you find yourself needing `@testable import` to reach into internals to test something, that's usually a sign the public API is missing something, not that you need deeper access.

## 6. Rules for keeping the architecture clean

These are restated from `CLAUDE.md` because they're the ones most likely to get bent under time pressure — treat any violation as a bug, not a style nit. CI now checks the first two mechanically (§8) — a human review should never be the *only* thing catching these, but don't rely on CI alone either; it only catches what its two scripts are written to catch, not the whole of `CLAUDE.md`.

- **`ACCore` never imports `AVFoundation`, `SwiftData`, `PDFKit`, or `libxlsxwriter`.** If domain code needs one of these, the fix is a new Repository protocol in `ACCore`, implemented in the relevant Data package — never an exception.
- **Views call ViewModels only.** Never a Repository, never a Use Case, never `AVFoundation`/`SwiftData` directly from a View.
- **ViewModels call Use Cases only**, never Data-layer packages directly, and hold no business logic — a ViewModel orchestrates and holds view state; a Use Case decides.
- **One source of truth per piece of state.** Persisted data lives in `SwiftData` behind `ProjectRepository`; the actively-edited `Setup`/`[Cue]` lives in the screen's ViewModel. If you ever find yourself keeping the "same" value in two places and syncing them by hand, that's the bug to fix, not a pattern to repeat.
- **`ACDesignSystem` components take no domain types.** If a component needs to know what a `Cue` is to make sense, it belongs in `ACFeatures/`, not the design system.

## 7. UI and integration testing strategy

Unit tests (§5) remain the primary testing layer and cover the overwhelming majority of this codebase's logic. But "Views are never automated, only verified manually" — this document's stance until this batch — is a real, accumulating risk over a multi-year horizon: zero automated coverage of the thing the user actually interacts with means a regression in the one place that matters most to them can ship silently.

**Resolution: a small, deliberately limited set of end-to-end flows get real automated coverage, via `XCUITest`, on top of (never instead of) the unit-test layer above.** This is not "start UI-testing everything" — most individual Views still have no automated test of their own, verified manually per their Deliverable's acceptance criteria, same as before. The difference is that the *critical path through the whole app* — the sequence a real user actually depends on working — gets automated, so it can't silently regress across 17 Deliverables' worth of future changes without a green CI run catching it.

**At minimum, the following flow is automated:** Setup → Cue creation (via detection or manual add) → Review & Export. This is the golden path named directly in `ROADMAP.md`'s own Deliverable D13 ("UI/Integration Test Automation") — build it there, not opportunistically bolted onto an unrelated Deliverable. Concretely, that means:
1. Create a project, fill in every required `Setup` field, confirm it persists.
2. Import a fixture WAV, run cue detection, confirm `Cue`s populate.
3. Navigate to the Review & Export tab, confirm a fully-valid project shows "ready to export," trigger a PDF export, confirm the file is produced.

**Snapshot testing** (rendering a View to an image and diffing against a reference) is the second tool in this layer, used narrower than `XCUITest`: for visually load-bearing components whose *appearance*, not just behavior, matters and is easy to regress silently — `CueTableView` and `WaveformView` are the two named candidates, since both are custom-rendered (`Canvas`/`Table`) rather than assembled from stock SwiftUI controls a system update might visually adjust for you. Not applied to every screen — most Views don't need a pixel-level regression guard, only ones where a subtle rendering bug (misaligned columns, a clipped waveform peak) wouldn't be caught by any behavioral test.

**What this doesn't change:** Views still aren't unit tested (§5); this is a separate, coarser-grained layer with a different failure mode (catches "the golden path broke," not "this one function has a bug"). Don't reach for `XCUITest` for something a unit test could catch faster and more precisely — UI tests are slower and more brittle by nature, which is exactly why this section keeps their scope small and named, rather than "wherever it seems useful."

## 8. Formatting, linting, and CI

Two tools, wired into CI, catching mistakes automatically instead of relying on review discipline alone — see `.swiftformat`/`.swiftlint.yml` at the repo root and `.github/workflows/ci.yml`.

- **SwiftFormat** (`swiftformat .` to apply, `swiftformat --lint .` to check without changing anything) — formatting only: indentation, import ordering, trailing commas, and similar. Run it before committing; CI runs it in check-only mode and fails the build if it would have changed anything.
- **SwiftLint** (`swiftlint lint`, or `swiftlint lint --strict` to match what CI runs) — catches real mistakes, not just style: force-unwraps/force-casts/force-tries are configured as **errors**, directly enforcing this document's own "don't force-unwrap" rule (§9) mechanically instead of relying on a reviewer noticing. Line length and identifier-length are set as gentle guardrails, not strict style enforcement.
- **Install both locally:** `brew install swiftformat swiftlint`. Run them before every commit — CI will catch what you miss, but catching it locally is faster.
- **Architecture-boundary scripts** (`Scripts/check-import-boundaries.sh`, `Scripts/check-color-literals.sh`) — the CI-side enforcement of two `CLAUDE.md` rules SPM itself can't check (see `CLAUDE.md`, "Package Dependency Graph," for why): no forbidden imports in `ACCore`/`ACDesignSystem`/`ACFeatures`/the Data-layer packages, and no raw color literals outside `ACDesignSystem/Theme`. Run them locally the same way CI does: `./Scripts/check-import-boundaries.sh` and `./Scripts/check-color-literals.sh` from the repo root.
- **CI (`.github/workflows/ci.yml`)** runs all of the above plus `swift test` for every existing package, on every push and PR to `main`. It was deliberately introduced at `ROADMAP.md` Deliverable D1 — the very first buildable state — rather than left until the export milestones, so every later Deliverable inherits automated enforcement from day one instead of 27 Deliverables' worth of unverified assumptions. See `docs/DECISIONS.md` for the full reasoning.

None of this replaces `docs/DefinitionOfDone.md`'s checklist — a green CI run is necessary for a Deliverable to be done, not sufficient on its own (manual acceptance criteria still need actually doing).

## 9. Common mistakes to avoid

**Swift-specific (if you're coming from another language):**
- Don't force-unwrap (`!`) to make the compiler happy. `let name = person.firstName!` will crash the app the first time it's `nil`. Use `guard let` / `if let` / a default value instead — the compiler is warning you about a real case, not being pedantic. `SwiftLint` now enforces this as a CI error (§8) — but fix the actual code, don't just silence the warning.
- Swift models are `struct`s (value types) by default in this project's domain layer — `Project`, `Cue`, `Setup`, etc. are all structs. Assigning one to a new variable copies it; mutating the copy doesn't touch the original. This is deliberate (it's what makes "single source of truth" tractable) — don't reach for `class` out of habit unless you specifically need reference semantics (ViewModels are the exception: they're reference types on purpose, since a View needs to observe one shared instance).
- Use `async`/`await`, not completion-handler closures or `DispatchQueue.main.async`. Long-running work (audio analysis, export) is written as an `async` function reporting progress via the shared `AsyncThrowingStream<OperationProgress<T>, Error>` contract (`CLAUDE.md`, "Long-Running Operations"), not nested callbacks and not Foundation's `Progress`.
- Watch for retain cycles in closures that capture `self` (e.g., inside a `Task { }` or an `AsyncStream` continuation) — use `[weak self]` when the closure outlives the call, same idea as avoiding retain cycles anywhere else, just spelled differently.

**Working with Claude Code specifically:**
- Don't accept a diff without reading it. Claude Code can generate a full Deliverable's worth of code in one turn — that's the point — but "it compiled" isn't the same as "it's correct." Actually check the diff against the Deliverable's acceptance criteria before committing.
- Don't let one session silently do two Deliverables' worth of work. If Claude starts touching files outside the current Deliverable's task list, that's worth a pause, not an automatic yes.
- Ask for tests alongside the implementation, not as an afterthought — "add D8's silence detector with its tests" in one request, not "add the detector" now and "now add tests" three sessions later after you've forgotten the edge cases.
- If Claude's suggested approach conflicts with `CLAUDE.md`, say so and point at the specific rule — don't assume it's automatically right just because it's confidently written. Update `CLAUDE.md` explicitly (and log the decision in `docs/DECISIONS.md` if it's a real trade-off, not just a typo fix) if you two decide to change a rule; don't let the code and the doc quietly diverge.

**Architecture/domain-specific to this project:**
- Don't add cue-sheet fields from other countries' conventions (US-style usage categories like "Background Instrumental," in/out timecodes as required fields, etc.). `CLAUDE.md` rule 5 exists specifically because this is an easy mistake if you've seen a US cue-sheet template before — SUISA's form doesn't work that way; check `SPEC.md` §2.1 before adding any field.
- Don't reintroduce a persisted `CueSheet` type. It was deliberately dropped — the exported cue sheet is `Setup` + `[Cue]`, assembled on demand.
- Don't add a third-party dependency without checking App Sandbox compatibility and static-linkability first (`CLAUDE.md` rule 4) — a dependency that works great in a normal macOS app can still break App Store submission.
- Don't load a full WAV file into memory "just to get something working." At 3-hour file sizes this isn't a performance nitpick, it's the difference between the app running and the app crashing — always go through the streaming reader from the start, even in a rough first pass.
- Don't add blanket `Codable` conformance to a new domain type "just in case." `CLAUDE.md`'s "Domain Model Value-Type Conformances" section explains why this was removed as a default — add it to a specific type only when a specific, real feature needs it, and say what that feature is at the point you add it.
- Don't reintroduce a single global `AppState`/`selectedProjectID` or a global save-serialization lock. `CLAUDE.md`'s "Document & Window Model" is multi-window by design (one `Project` per window) — see there for the full architecture before touching window/navigation state.
