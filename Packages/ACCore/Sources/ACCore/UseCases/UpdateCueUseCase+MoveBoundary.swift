import Foundation

/// Split into its own file purely to keep `UpdateCueUseCase` under this
/// project's type-body-length lint limit — still the same type, just via an
/// extension, the same pattern `CueDetectionReviewViewModel
/// +ClearImportedAudio.swift` already establishes.
public extension UpdateCueUseCase {
    /// Repositions a cue's start or end marker (SPEC.md §4.19's "Boundary
    /// markers: contiguous vs. non-contiguous"). Whether this writes one cue
    /// or two is decided fresh, each call, from the actual gap between the
    /// dragged cue and its immediate neighbor as it stands in the repository
    /// *before* this call — never a stored flag, never inferred from a
    /// drag's path (nothing is written mid-drag; the caller only invokes
    /// this once, at gesture release).
    ///
    /// **Non-contiguous** (gap > `contiguityEpsilonSeconds`): the neighbor is
    /// never touched. Moving away from it is unconstrained (aside from the
    /// dragged cue's own minimum-length floor, `duration >= 0`); moving
    /// toward it clamps at exactly the neighbor's current position — it
    /// cannot be dragged past, and a further call requesting an even more
    /// extreme offset produces the identical clamped result.
    ///
    /// **Contiguous** (gap <= `contiguityEpsilonSeconds`): moving away from
    /// the touching position is still a single-cue write — the gap simply
    /// reopens, no confirmation needed. Moving further into the neighbor
    /// carries the neighbor's matching edge along by the same amount, in one
    /// atomic write, with the neighbor's own *opposite* edge held fixed —
    /// the same "keep the far end anchored" rule every other branch here
    /// already uses. Anchoring the neighbor's far edge is also what keeps a
    /// push from ever cascading past the immediate pair: by the
    /// no-overlap invariant, that anchored edge is already at or before any
    /// third cue, so clamping against it alone is sufficient — no separate
    /// third-cue lookup is needed.
    @discardableResult
    func moveBoundary(
        projectID: Project.ID,
        marker: BoundaryMarkerKind,
        toOffsetSeconds: Double
    ) async throws -> BoundaryMoveResult {
        switch marker {
        case let .end(cueID):
            try await moveEnd(projectID: projectID, cueID: cueID, toOffsetSeconds: toOffsetSeconds)
        case let .start(cueID):
            try await moveStart(projectID: projectID, cueID: cueID, toOffsetSeconds: toOffsetSeconds)
        }
    }
}

private extension UpdateCueUseCase {
    func moveEnd(projectID: Project.ID, cueID: Cue.ID, toOffsetSeconds: Double) async throws -> BoundaryMoveResult {
        let recorder = BoundaryWriteRecorder()
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            guard project.cues[index].startTimecode != nil else {
                throw UpdateCueUseCaseError.cueHasNoStartTimecode(cueID)
            }
            var cues = project.cues
            let plan = Self.planEndMove(
                cues: cues,
                index: index,
                toOffsetSeconds: toOffsetSeconds,
                fileEndSeconds: project.audioAsset?.duration.seconds
            )
            for entry in plan {
                cues[entry.index] = entry.cue
            }
            recorder.writtenCueIDs = Set(plan.map(\.cue.id))
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return BoundaryMoveResult(updatedCues: updated.cues.filter { recorder.writtenCueIDs.contains($0.id) })
    }

    func moveStart(projectID: Project.ID, cueID: Cue.ID, toOffsetSeconds: Double) async throws -> BoundaryMoveResult {
        let recorder = BoundaryWriteRecorder()
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            guard project.cues[index].startTimecode != nil else {
                throw UpdateCueUseCaseError.cueHasNoStartTimecode(cueID)
            }
            var cues = project.cues
            let plan = Self.planStartMove(cues: cues, index: index, toOffsetSeconds: toOffsetSeconds)
            for entry in plan {
                cues[entry.index] = entry.cue
            }
            recorder.writtenCueIDs = Set(plan.map(\.cue.id))
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return BoundaryMoveResult(updatedCues: updated.cues.filter { recorder.writtenCueIDs.contains($0.id) })
    }

    /// Pure planning step for `moveEnd` — no repository access, so it's
    /// trivially unit-testable on its own and keeps `moveEnd` itself just
    /// the I/O shell around it. Returns the `(index, updatedCue)` pairs to
    /// apply: one for an independent move, two for an atomic push-through.
    /// Assumes `cues[index]` has a `startTimecode` — `moveEnd` above already
    /// guards that before calling this.
    static func planEndMove(
        cues: [Cue],
        index: Int,
        toOffsetSeconds: Double,
        fileEndSeconds: Double?
    ) -> [(index: Int, cue: Cue)] {
        let cue = cues[index]
        guard let start = cue.startTimecode else { return [] }

        let successorIndex = index + 1
        let successor: Cue? = cues.indices.contains(successorIndex) ? cues[successorIndex] : nil
        guard let successor, let successorTimecode = successor.startTimecode else {
            // No neighbor (last cue) — bounded only by this cue's own start
            // and, if known, the file's own duration.
            var newEnd = max(toOffsetSeconds, start.offsetSeconds)
            if let fileEndSeconds {
                newEnd = min(newEnd, fileEndSeconds)
            }
            let updated = cue.withDuration(MediaDuration(seconds: max(0, newEnd - start.offsetSeconds)))
                .reclassifiedAsManual()
            return [(index, updated)]
        }

        let successorStart = successorTimecode.offsetSeconds
        let gapBefore = successorStart - (start.offsetSeconds + cue.duration.seconds)

        if toOffsetSeconds <= successorStart {
            // Away from, or approaching, the neighbor — always a single-cue
            // write, whether the boundary starts contiguous or not.
            let newEnd = max(toOffsetSeconds, start.offsetSeconds)
            let updated = cue.withDuration(MediaDuration(seconds: max(0, newEnd - start.offsetSeconds)))
                .reclassifiedAsManual()
            return [(index, updated)]
        }
        if gapBefore <= UpdateCueUseCase.contiguityEpsilonSeconds {
            // Already touching — push through, carrying the neighbor's
            // matching edge along, clamped at its own far (anchored) end.
            let successorOwnEnd = successorStart + successor.duration.seconds
            let newEnd = min(toOffsetSeconds, successorOwnEnd)
            let updatedCue = cue.withDuration(MediaDuration(seconds: max(0, newEnd - start.offsetSeconds)))
                .reclassifiedAsManual()
            let updatedSuccessor = successor.withStart(
                Timecode(offsetSeconds: newEnd),
                duration: MediaDuration(seconds: max(0, successorOwnEnd - newEnd))
            ).reclassifiedAsManual()
            return [(index, updatedCue), (successorIndex, updatedSuccessor)]
        }
        // Non-contiguous, and the request tries to cross — clamp at the
        // neighbor's current position, never cross it.
        let updated = cue.withDuration(MediaDuration(seconds: max(0, successorStart - start.offsetSeconds)))
            .reclassifiedAsManual()
        return [(index, updated)]
    }

    /// The mirror image of `planEndMove` — see its doc comment for the
    /// shared shape. Assumes `cues[index]` has a `startTimecode` — `moveStart`
    /// above already guards that before calling this.
    static func planStartMove(
        cues: [Cue],
        index: Int,
        toOffsetSeconds: Double
    ) -> [(index: Int, cue: Cue)] {
        let cue = cues[index]
        guard let start = cue.startTimecode else { return [] }
        let ownEnd = start.offsetSeconds + cue.duration.seconds

        let predecessorIndex = index - 1
        let predecessor: Cue? = cues.indices.contains(predecessorIndex) ? cues[predecessorIndex] : nil
        guard let predecessor, let predecessorTimecode = predecessor.startTimecode else {
            // No neighbor (first cue) — bounded only by this cue's own end
            // and the file's own start (0).
            let newStart = min(max(toOffsetSeconds, 0), ownEnd)
            let updated = cue.withStart(
                Timecode(offsetSeconds: newStart),
                duration: MediaDuration(seconds: max(0, ownEnd - newStart))
            ).reclassifiedAsManual()
            return [(index, updated)]
        }

        let predecessorEnd = predecessorTimecode.offsetSeconds + predecessor.duration.seconds
        let gapBefore = start.offsetSeconds - predecessorEnd

        if toOffsetSeconds >= predecessorEnd {
            // Away from, or approaching, the neighbor — always a
            // single-cue write.
            let newStart = min(toOffsetSeconds, ownEnd)
            let updated = cue.withStart(
                Timecode(offsetSeconds: newStart),
                duration: MediaDuration(seconds: max(0, ownEnd - newStart))
            ).reclassifiedAsManual()
            return [(index, updated)]
        }
        if gapBefore <= UpdateCueUseCase.contiguityEpsilonSeconds {
            // Already touching — push through, carrying the predecessor's
            // matching edge along, clamped at its own far (anchored) start.
            let newStart = max(toOffsetSeconds, predecessorTimecode.offsetSeconds)
            let updatedCue = cue.withStart(
                Timecode(offsetSeconds: newStart),
                duration: MediaDuration(seconds: max(0, ownEnd - newStart))
            ).reclassifiedAsManual()
            let updatedPredecessor = predecessor.withDuration(
                MediaDuration(seconds: max(0, newStart - predecessorTimecode.offsetSeconds))
            ).reclassifiedAsManual()
            return [(index, updatedCue), (predecessorIndex, updatedPredecessor)]
        }
        // Non-contiguous, and the request tries to cross — clamp at the
        // neighbor's current position, never cross it.
        let updated = cue.withStart(
            Timecode(offsetSeconds: predecessorEnd),
            duration: MediaDuration(seconds: max(0, ownEnd - predecessorEnd))
        ).reclassifiedAsManual()
        return [(index, updated)]
    }
}

/// Identifies which cue's marker is being dragged, for `moveBoundary`.
/// `ACCore`-only — never crosses into `ACDesignSystem`, which identifies
/// markers by plain `Int` cue-index instead (`CLAUDE.md`'s Design System
/// rule); `ACFeatures` translates between the two at the point it calls this
/// Use Case (SPEC.md §4.19).
public enum BoundaryMarkerKind: Equatable, Sendable {
    case start(Cue.ID)
    case end(Cue.ID)
}

/// The cue(s) `moveBoundary` actually wrote — one for an independent
/// (non-contiguous) move, two for an atomic contiguous push-through.
public struct BoundaryMoveResult: Equatable, Sendable {
    public let updatedCues: [Cue]
}

/// A single-use side channel for reporting which cue(s) a `moveBoundary`
/// branch actually wrote, out of `ProjectRepository.update(id:transform:)`'s
/// `@Sendable` transform closure. `@unchecked Sendable` is deliberate here,
/// not a shortcut: the closure runs exactly once, synchronously, within that
/// one `await` call — never concurrently, never more than once — so a plain
/// mutable class property is safe in practice even though the compiler
/// cannot prove it from the closure's `@Sendable` signature alone (that
/// signature exists for the closure to safely cross into the repository's
/// actor isolation, not because it's ever actually invoked concurrently).
private final class BoundaryWriteRecorder: @unchecked Sendable {
    var writtenCueIDs: Set<Cue.ID> = []
}

private extension Cue {
    /// `moveBoundary`'s "keep the other end anchored" pattern, repeated
    /// across `planEndMove`/`planStartMove` — extracted here purely to avoid
    /// spelling out `Cue`'s full memberwise init at each call site, the same
    /// "small, file-local helper" tier `reclassifiedAsManual()` already
    /// establishes, not a public API addition.
    func withDuration(_ duration: MediaDuration) -> Cue {
        Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: duration,
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: startTimecode,
            notes: notes
        )
    }

    func withStart(_ startTimecode: Timecode, duration: MediaDuration) -> Cue {
        Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: duration,
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: startTimecode,
            notes: notes
        )
    }
}
