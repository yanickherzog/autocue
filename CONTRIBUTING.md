# Contributing to AutoCue

This guide assumes you're comfortable on macOS but relatively new to Swift and to working with Claude Code. It tells you *how to work* on this project day to day. For *what* to build and *why it's structured this way*, read these first, in this order:

1. `CLAUDE.md` — architecture rules (this is also Claude Code's persistent memory for this repo — if you and Claude ever disagree about how something should be structured, `CLAUDE.md` is the tiebreaker)
2. `SPEC.md` — the finalized data model and SUISA compliance target
3. `ROADMAP.md` — the milestone list this whole workflow is built around

Everything below assumes you have those three open.

---

## 1. Work on one milestone at a time

`ROADMAP.md` isn't a wish list — it's the unit of work. One milestone = one Claude Code session = one branch = (usually) one commit.

- Before starting, read the milestone's Goal, Files, Dependencies, and Acceptance Criteria. If a dependency milestone isn't actually done, stop and finish that first — don't skip ahead "because it's quick," you'll just end up debugging two half-finished things at once.
- Don't let a session drift into the next milestone. If you're mid-M14 (Setup view) and realize you also want to fix something in M9 (design tokens), that's a *second* session/branch, even if it's small. Finishing one thing cleanly beats two things half-done.
- A milestone is done when its acceptance criteria are all true — not when it "looks right." Several acceptance criteria explicitly say "manually verified" — actually run the app and do that step, don't assume the code is correct because it compiles.
- If a milestone turns out to be bigger than it looked once you're in it, stop and split it rather than pushing through — a 400-line commit is much harder to review than two 150-line ones.

**With Claude Code specifically:** open a session by pointing it at the milestone (e.g. "let's do M14 from ROADMAP.md"), not by describing the feature from memory — the roadmap entry already encodes the file list and acceptance criteria, so re-describing it invites drift from what was actually planned.

## 2. Avoiding technical debt

Debt on this project almost always means one thing: a shortcut that breaks the dependency rule in `CLAUDE.md` ("outer depends on inner, never the reverse"). It's easy to introduce by accident because it still compiles — Swift won't stop you from importing `AVFoundation` into `ACCore`, only your discipline will.

Concrete rules:
- **Don't stub something "to come back to later."** If a milestone needs a `Person` picker, build the real (if minimal) picker — don't hardcode a fake person and leave a comment. Half-built features are where debt hides, because they look done in a diff review.
- **No `// TODO` without a `ROADMAP.md` milestone number next to it.** A bare TODO is a promise nobody's tracking. `// TODO(M25): handle arranger authorization flag` is fine because it's traceable; `// TODO: fix this later` is not.
- **Don't skip a test to move faster.** This is more important with AI-assisted coding, not less — Claude can produce a lot of plausible-looking code quickly, and untested code you didn't personally verify is exactly where debt compounds silently.
- **Don't add a field, enum case, or dependency that isn't in `SPEC.md`/`CLAUDE.md` without updating those files in the same change.** An undocumented schema change is debt the moment it's committed, because the next session (yours or Claude's) will trust the doc over the code.

## 3. When to refactor instead of adding code

Default to adding code. Refactor when one of these is true, not on a hunch:

- **The rule of three.** You're about to write the third near-identical version of something (a third row-building function, a third "fetch and map" block). The first two times, duplication is fine and even preferable — you don't know the right abstraction yet. The third time, extract it.
- **You can't meet the milestone's acceptance criteria without touching unrelated code.** E.g., M24 needs `CueTableView` in `ACDesignSystem` to take no `ACCore` type — if the existing draft component was written with a `Cue` parameter baked in, that's not a new feature, it's a pre-existing violation you need to fix first.
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
- **A commit should leave the tree buildable and tests passing.** Don't commit "part 1 of 3" if part 1 doesn't compile — squash locally before committing if you were exploring.
- Match a commit to a milestone where possible. If a milestone naturally needs 2–3 commits (e.g., model + tests, then wiring), that's fine — just keep each one coherent on its own.

## 5. Writing tests

If you're new to Swift testing: this project uses `XCTest`/Swift Testing conventions — a test is a function that calls the code under test and asserts on the result, in a `Tests/<Target>Tests/` folder mirroring `Sources/<Target>/`.

What to test, by layer (this follows directly from `CLAUDE.md`'s architecture):
- **`ACCore` (Domain):** the easiest and most important tests in the project — pure functions/structs, no I/O, no mocking needed. Every use case and every validation rule (share sums, required fields) needs a direct unit test. If a `ACCore` test needs a mock, something's wrong — it should need nothing but plain values.
- **Data-layer packages (`ACAudioKit`, `ACExport`, `ACPersistence`):** test against *real* fixtures, not mocks of the file system — a real small WAV file, a real in-memory `ModelContainer`. Mocking the thing you're supposed to be testing (file I/O, SwiftData) just proves your mock works, not your code.
- **ViewModels:** test against the fakes in `ACTestSupport` (`InMemoryProjectRepository`, etc.), never against real `AVFoundation`/`SwiftData`. A ViewModel test should be fast and shouldn't touch disk.
- **Views:** not unit tested. Verified manually per the milestone's acceptance criteria, plus the accessibility/keyboard pass in Phase 12.

Practical habits:
- Write the test in the same sitting as the code, not after the whole milestone is "done" — if you write `ValidateCueRightHolderSharesUseCase` and its test back to back, you'll catch the boundary cases (0 right-holders, shares summing to 99.9%) while you still remember them.
- Name tests after the behavior, not the method: `sharesNotSummingTo100PercentFailsValidation`, not `testValidate2`.
- Test the public protocol/behavior, not private internals — if you find yourself needing `@testable import` to reach into internals to test something, that's usually a sign the public API is missing something, not that you need deeper access.

## 6. Rules for keeping the architecture clean

These are restated from `CLAUDE.md` because they're the ones most likely to get bent under time pressure — treat any violation as a bug, not a style nit:

- **`ACCore` never imports `AVFoundation`, `SwiftData`, `PDFKit`, or `libxlsxwriter`.** If domain code needs one of these, the fix is a new Repository protocol in `ACCore`, implemented in the relevant Data package — never an exception.
- **Views call ViewModels only.** Never a Repository, never a Use Case, never `AVFoundation`/`SwiftData` directly from a View.
- **ViewModels call Use Cases only**, never Data-layer packages directly, and hold no business logic — a ViewModel orchestrates and holds view state; a Use Case decides.
- **One source of truth per piece of state.** Persisted data lives in `SwiftData` behind `ProjectRepository`; the actively-edited `Setup`/`[Cue]` lives in the screen's ViewModel. If you ever find yourself keeping the "same" value in two places and syncing them by hand, that's the bug to fix, not a pattern to repeat.
- **`ACDesignSystem` components take no domain types.** If a component needs to know what a `Cue` is to make sense, it belongs in `Features/`, not the design system.

## 7. Common mistakes to avoid

**Swift-specific (if you're coming from another language):**
- Don't force-unwrap (`!`) to make the compiler happy. `let name = person.firstName!` will crash the app the first time it's `nil`. Use `guard let` / `if let` / a default value instead — the compiler is warning you about a real case, not being pedantic.
- Swift models are `struct`s (value types) by default in this project's domain layer — `Project`, `Cue`, `Setup`, etc. are all structs. Assigning one to a new variable copies it; mutating the copy doesn't touch the original. This is deliberate (it's what makes "single source of truth" tractable) — don't reach for `class` out of habit unless you specifically need reference semantics (ViewModels are the exception: they're reference types on purpose, since a View needs to observe one shared instance).
- Use `async`/`await`, not completion-handler closures or `DispatchQueue.main.async`. Long-running work (audio analysis, export) is written as an `async` function reporting progress via `AsyncStream`, not nested callbacks.
- Watch for retain cycles in closures that capture `self` (e.g., inside a `Task { }` or an `AsyncStream` continuation) — use `[weak self]` when the closure outlives the call, same idea as avoiding retain cycles anywhere else, just spelled differently.

**Working with Claude Code specifically:**
- Don't accept a diff without reading it. Claude Code can generate a full milestone's worth of code in one turn — that's the point — but "it compiled" isn't the same as "it's correct." Actually check the diff against the milestone's acceptance criteria before committing.
- Don't let one session silently do two milestones' worth of work. If Claude starts touching files outside the current milestone's file list, that's worth a pause, not an automatic yes.
- Ask for tests alongside the implementation, not as an afterthought — "add M18's silence detector with its tests" in one request, not "add the detector" now and "now add tests" three sessions later after you've forgotten the edge cases.
- If Claude's suggested approach conflicts with `CLAUDE.md`, say so and point at the specific rule — don't assume it's automatically right just because it's confidently written. Update `CLAUDE.md` explicitly if you two decide to change a rule; don't let the code and the doc quietly diverge.

**Architecture/domain-specific to this project:**
- Don't add cue-sheet fields from other countries' conventions (US-style usage categories like "Background Instrumental," in/out timecodes as required fields, etc.). `CLAUDE.md` rule 5 exists specifically because this is an easy mistake if you've seen a US cue-sheet template before — SUISA's form doesn't work that way; check `SPEC.md` §2.1 before adding any field.
- Don't reintroduce a persisted `CueSheet` type. It was deliberately dropped — the exported cue sheet is `Setup` + `[Cue]`, assembled on demand.
- Don't add a third-party dependency without checking App Sandbox compatibility and static-linkability first (`CLAUDE.md` rule 4) — a dependency that works great in a normal macOS app can still break App Store submission.
- Don't load a full WAV file into memory "just to get something working." At 3-hour file sizes this isn't a performance nitpick, it's the difference between the app running and the app crashing — always go through the streaming reader from the start, even in a rough first pass.
