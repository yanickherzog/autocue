# AutoCue — Definition of Done

The checklist a `ROADMAP.md` Deliverable (or, mid-Deliverable, an individual Task) must satisfy before it's considered complete — not "looks right," not "compiles," this list. `CONTRIBUTING.md` §1 points back here for what "done" actually means; this file is the authoritative checklist, not restated prose scattered across other docs.

Every item below must be true. None are optional, and none are satisfied by a subset of the others — "tests pass" doesn't imply "zero warnings," and "builds successfully" doesn't imply "documentation updated." Check all six explicitly.

## 1. Builds successfully

- `swift build` (or, once `ROADMAP.md` Deliverable D1 creates the workspace, `xcodebuild build -scheme AutoCue`) completes with zero errors.
- Every package touched by the change builds on its own, not just as part of the whole workspace — a package with a broken internal build that happens to still link is not "building successfully."

## 2. Tests pass

- Every existing test still passes — a Deliverable that breaks an unrelated test is not done until that's fixed, even if fixing it feels out of scope.
- Every new behavior introduced by the Deliverable has a new test covering it, per the testing rules in `CONTRIBUTING.md` §5 (unit tests, by layer) and §7 (the small UI/integration layer, only for the flows named there).
- CI (`.github/workflows/ci.yml`) is green — a local "tests pass on my machine" is necessary but not sufficient; the pushed commit's CI run must also be green before the Deliverable is considered done.

## 3. Zero warnings

- Zero compiler warnings — an unused variable, an unreachable case, a deprecated API call left in place is not "a warning to clean up later," it's unfinished work.
- Zero `SwiftLint` violations at the `--strict` threshold CI runs (`.swiftlint.yml`) — this includes the force-unwrap/force-cast/force-try rules, which are configured as errors specifically because `CONTRIBUTING.md` §9 already treats them as non-negotiable, not just a style preference.
- `swiftformat --lint .` reports no files requiring formatting — run `swiftformat .` before committing, don't let CI be the first place that notices.

## 4. Documentation updated

- `SPEC.md` updated in the same change if the Deliverable added, removed, or changed a domain model field, case, or type — per `CLAUDE.md` rules 5 and 9. A schema change without a `SPEC.md` update is not done, regardless of how correct the code is.
- `CLAUDE.md` updated in the same change if the Deliverable changed an architectural rule, module boundary, or established pattern — per `CLAUDE.md` rule 8.
- `docs/DECISIONS.md` gets a new entry if the Deliverable made a real, debatable architectural call (a library choice, a reversed earlier decision, a considered-and-rejected alternative) — not every commit needs one, but a real trade-off does. See that file's own header for the bar.
- Doc changes are reviewed for internal consistency, not just written and forgotten — a claim in `SPEC.md` that contradicts `CLAUDE.md`, or a `ROADMAP.md` acceptance criterion that references a renamed type, is exactly the kind of drift this whole checklist exists to prevent.

## 5. `ROADMAP.md` updated

- The Deliverable (and each of its Tasks) is marked complete in `ROADMAP.md` itself — the roadmap is a live tracking document, not a static plan written once and never touched again.
- If the Deliverable's actual scope diverged from what `ROADMAP.md` described going in (a Task turned out to need splitting, a dependency was discovered that wasn't listed), `ROADMAP.md` is corrected to reflect what actually happened — not left describing a plan that's now wrong.

## 6. Architecture preserved

- No violation of any rule in `CLAUDE.md`'s "Rules for Future Development" section — this is checked mechanically wherever CI's two architecture scripts cover it (`Scripts/check-import-boundaries.sh`, `Scripts/check-color-literals.sh` — see `CLAUDE.md`, "Package Dependency Graph," for what those do and don't catch), and by hand everywhere else.
- Every dependency-direction rule from `CLAUDE.md`'s MVVM + Clean Architecture section still holds: Views → ViewModels → Use Cases/Repository Protocols ← Repository Implementations, never the reverse.
- A `docs/REVIEW.md` entry is appended for the completed Deliverable (see that file's template) — this is where architecture/code-quality observations, technical debt, and refactoring suggestions get recorded for the next session to actually see, rather than living only in the author's memory.

---

**A Deliverable that satisfies 1–3 but not 4–6 is not done — it's working code with unfinished paperwork, and the paperwork is what keeps this project navigable for whoever (human or Claude) picks it up next, on a project explicitly designed to be built across dozens of independent sessions over years.**
