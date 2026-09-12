import Foundation

/// Turns raw signal detection (`AudioAnalysisRepository.detectCues`,
/// `SilenceDetector`) plus `AudioAsset.embeddedMarkers` into the final,
/// reconciled `[Cue]` list — the real merge layer SPEC.md §4.11's
/// "Combining with embedded markers" assigns this Use Case, not the
/// Repository (`ROADMAP.md` D9/T9.1).
public struct DetectCuesUseCase: Sendable {
    private let audioAnalysisRepository: AudioAnalysisRepository
    private let projectRepository: ProjectRepository

    public init(audioAnalysisRepository: AudioAnalysisRepository, projectRepository: ProjectRepository) {
        self.audioAnalysisRepository = audioAnalysisRepository
        self.projectRepository = projectRepository
    }

    /// Runs detection against `asset`, merges the result against
    /// `asset.embeddedMarkers`, preserves every existing `.manual`/
    /// `.embeddedMarker` cue already on `Project.cues` untouched (SPEC.md
    /// §4.11's re-run rule — only `.detectedFromAudio` cues are replaced),
    /// persists the combined result, and yields it.
    public func detectCues(
        projectID: Project.ID,
        asset: AudioAsset,
        settings: AnalysisSettings
    ) -> AsyncThrowingStream<OperationProgress<[Cue]>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let asset = try await BookmarkRefresher.refreshingIfNeeded(
                        asset,
                        projectID: projectID,
                        audioAnalysisRepository: audioAnalysisRepository,
                        projectRepository: projectRepository
                    )
                    var rawCues: [Cue] = []
                    for try await event in audioAnalysisRepository.detectCues(in: asset, settings: settings) {
                        switch event {
                        case let .progress(update):
                            continuation.yield(.progress(update))
                        case let .completed(cues):
                            rawCues = cues
                        }
                    }

                    let merged = EmbeddedMarkerMerge.merge(
                        rawCues: rawCues,
                        embeddedMarkers: asset.embeddedMarkers,
                        toleranceSeconds: settings.embeddedMarkerMergeToleranceSeconds,
                        fileDurationSeconds: asset.duration.seconds
                    )

                    let finalCues = try await persist(merged, projectID: projectID)
                    continuation.yield(.completed(finalCues))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Preserves every existing `.manual`/`.embeddedMarker` cue untouched;
    /// replaces only `.detectedFromAudio` ones with `merged` — SPEC.md
    /// §4.11's exact re-run rule. **The "warn before discarding" UX is the
    /// calling ViewModel's job, not this Use Case's** — it checks whether
    /// `Project.cues` has any non-`.detectedFromAudio` entries *before* ever
    /// invoking this method at all; Use Cases don't own UI.
    private func persist(_ merged: [Cue], projectID: Project.ID) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            let ffoaFiltered = FirstFrameOfActionExclusion.apply(
                to: merged,
                timecodeStart: project.setup.timecodeStart
            )
            let preserved = project.cues.filter { $0.source != .detectedFromAudio }
            let combined = (preserved + ffoaFiltered).sorted { lhs, rhs in
                (lhs.startTimecode?.offsetSeconds ?? .infinity) < (rhs.startTimecode?.offsetSeconds ?? .infinity)
            }
            return Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: project.audioAsset,
                waveformPeaks: project.waveformPeaks,
                setup: project.setup.updating(
                    totalMusicRuntime: RecalculateTotalMusicRuntimeUseCase.recalculate(cues: combined)
                ),
                cues: combined,
                people: project.people,
                labels: project.labels
            )
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }
}

/// The embedded-marker merge algorithm, SPEC.md §4.11 — "an embedded marker
/// is always authoritative," extended to the marker-with-no-nearby-detected-
/// boundary case per the 2026-09-05 resolution in `docs/DECISIONS.md`. Kept
/// as a plain, private, stateless algorithm — no Repository dependency, pure
/// function of its inputs — so it's independently unit-testable without any
/// I/O (`DetectCuesUseCaseTests` exercises it through the Use Case's public
/// `detectCues` method, per `CONTRIBUTING.md` §5's "test the public
/// protocol/behavior, not private internals").
enum EmbeddedMarkerMerge {
    /// `rawCues` are expected `.detectedFromAudio`, each with a non-nil
    /// `startTimecode` (guaranteed by `AudioAnalysisRepository.detectCues`'s
    /// contract) — sorted defensively regardless of input order.
    static func merge(
        rawCues: [Cue],
        embeddedMarkers: [EmbeddedMarker],
        toleranceSeconds: Double,
        fileDurationSeconds: Double
    ) -> [Cue] {
        var regions = rawCues.sorted { ($0.startTimecode?.offsetSeconds ?? 0) < ($1.startTimecode?.offsetSeconds ?? 0) }
        let sortedMarkers = embeddedMarkers.sorted { $0.position.offsetSeconds < $1.position.offsetSeconds }

        let confirmedMarkerIDs = confirmNearbyMarkers(
            in: &regions,
            markers: sortedMarkers,
            toleranceSeconds: toleranceSeconds
        )
        // An unconfirmed marker is still authoritative — it produces its own
        // cue-start regardless, splitting whatever region currently contains
        // it, or (if it falls in silence) running to the next known
        // boundary or file-end. Processed in ascending position order so
        // each marker's containment check sees every previously-inserted
        // marker's own cue too — resolving a chain of adjacent unconfirmed
        // markers correctly via repeated splitting.
        for marker in sortedMarkers where !confirmedMarkerIDs.contains(marker.id) {
            insert(marker, into: &regions, fileDurationSeconds: fileDurationSeconds)
        }

        return regions.sorted { ($0.startTimecode?.offsetSeconds ?? 0) < ($1.startTimecode?.offsetSeconds ?? 0) }
    }

    /// A marker within tolerance of a region's start confirms it — the
    /// region is reclassified `.embeddedMarker` and its start snaps to the
    /// marker's own (authoritative) position, keeping the region's original
    /// *end* fixed. Returns the IDs of every marker that confirmed a region,
    /// so the caller knows which markers remain unconfirmed.
    private static func confirmNearbyMarkers(
        in regions: inout [Cue],
        markers: [EmbeddedMarker],
        toleranceSeconds: Double
    ) -> Set<UUID> {
        var confirmedMarkerIDs = Set<UUID>()
        for index in regions.indices {
            guard let start = regions[index].startTimecode else { continue }
            let candidate = markers
                .filter { !confirmedMarkerIDs.contains($0.id) }
                .min {
                    abs($0.position.offsetSeconds - start.offsetSeconds) <
                        abs($1.position.offsetSeconds - start.offsetSeconds)
                }
            guard let marker = candidate,
                  abs(marker.position.offsetSeconds - start.offsetSeconds) <= toleranceSeconds
            else { continue }

            confirmedMarkerIDs.insert(marker.id)
            let end = start.offsetSeconds + regions[index].duration.seconds
            regions[index] = regions[index].reclassifiedAsEmbeddedMarker(at: marker.position, endSeconds: end)
        }
        return confirmedMarkerIDs
    }

    /// Inserts an unconfirmed `marker` into `regions` — splitting the region
    /// it falls inside, if any, or else creating a freestanding cue running
    /// to the next known boundary (or file-end, if none follows).
    private static func insert(_ marker: EmbeddedMarker, into regions: inout [Cue], fileDurationSeconds: Double) {
        let position = marker.position.offsetSeconds

        guard let containing = containingRegion(at: position, in: regions) else {
            let nextBoundary = regions
                .compactMap { $0.startTimecode?.offsetSeconds }
                .filter { $0 > position }
                .min() ?? fileDurationSeconds
            let newCue = Cue(
                title: "",
                duration: MediaDuration(seconds: max(0, nextBoundary - position)),
                rightHolders: [],
                source: .embeddedMarker,
                startTimecode: marker.position
            )
            let insertIndex = regions.firstIndex { ($0.startTimecode?.offsetSeconds ?? 0) > position } ?? regions.count
            regions.insert(newCue, at: insertIndex)
            return
        }

        let original = regions[containing.index]
        regions[containing.index] = Cue(
            id: original.id,
            title: original.title,
            workNumber: original.workNumber,
            duration: MediaDuration(seconds: position - containing.start),
            rightHolders: original.rightHolders,
            isArrangementOfProtectedOriginal: original.isArrangementOfProtectedOriginal,
            source: original.source,
            startTimecode: original.startTimecode,
            notes: original.notes
        )
        let newCue = Cue(
            title: "",
            duration: MediaDuration(seconds: containing.end - position),
            rightHolders: [],
            source: .embeddedMarker,
            startTimecode: marker.position
        )
        regions.insert(newCue, at: containing.index + 1)
    }

    private static func containingRegion(at position: Double, in regions: [Cue]) -> ContainingRegion? {
        for (index, region) in regions.enumerated() {
            guard let start = region.startTimecode?.offsetSeconds else { continue }
            let end = start + region.duration.seconds
            if position > start, position < end {
                return ContainingRegion(index: index, start: start, end: end)
            }
        }
        return nil
    }

    private struct ContainingRegion {
        let index: Int
        let start: Double
        let end: Double
    }
}

private extension Cue {
    func reclassifiedAsEmbeddedMarker(at position: Timecode, endSeconds: Double) -> Cue {
        Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: MediaDuration(seconds: endSeconds - position.offsetSeconds),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: .embeddedMarker,
            startTimecode: position,
            notes: notes
        )
    }

    /// Keeps every field except `startTimecode`/`duration`, which move to
    /// start exactly at `newStartSeconds` while the cue's original *end*
    /// stays fixed — the same "snap start, keep end" shape
    /// `reclassifiedAsEmbeddedMarker` above already uses, applied here for
    /// `FirstFrameOfActionExclusion`'s straddling-FFOA case instead.
    func truncatingStart(toOffsetSeconds newStartSeconds: Double) -> Cue {
        guard let start = startTimecode?.offsetSeconds else { return self }
        let end = start + duration.seconds
        return Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: MediaDuration(seconds: end - newStartSeconds),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: Timecode(offsetSeconds: newStartSeconds),
            notes: notes
        )
    }
}

/// SPEC.md §4.11, "First Frame of Action exclusion" — no detected or
/// embedded-marker-derived cue is ever constructed (or left standing) with
/// real content entirely before First Frame of Action (`10:00:00:00`, the
/// industry-standard FFOA convention). This is applied **after**
/// `EmbeddedMarkerMerge`, to its combined output, deliberately — that's
/// what makes it apply uniformly regardless of a cue's source
/// (`.detectedFromAudio` or `.embeddedMarker`): "an embedded marker is
/// always authoritative" (SPEC.md §4.11) resolves which *real* candidate
/// wins between competing detections, it was never meant to admit material
/// that's categorically not music (a 2-pop's own embedded marker included).
/// Kept as its own pure, stateless algorithm rather than folded into
/// `EmbeddedMarkerMerge` — that type's own doc comment scopes it
/// specifically to marker-vs-detection reconciliation, a different concern
/// than gating on absolute film position.
enum FirstFrameOfActionExclusion {
    /// Absolute (film-timeline) FFOA position, in seconds — `10:00:00:00`.
    /// Hardcoded, never `Setup`-configurable: only `Setup.timecodeStart`
    /// varies per project (SPEC.md §4.11). Exactly frame-rate-independent —
    /// `10:00:00:00` has `0` frames, the same property `Setup.timecodeStart`'s
    /// own default (`09:59:52:00`) already relies on, so no
    /// `TimecodeFrameRate` conversion or rounding is involved anywhere in
    /// this comparison.
    static let absoluteSeconds: Double = 36000.0

    /// No-op when `timecodeStart` is `nil` — with no absolute reference
    /// point, there's nothing to compare a cue's audio-file-relative
    /// position against, so nothing is excluded or truncated.
    static func apply(to cues: [Cue], timecodeStart: Timecode?) -> [Cue] {
        guard let timecodeStart else { return cues }
        let ffoaOffsetSeconds = absoluteSeconds - timecodeStart.offsetSeconds

        return cues.compactMap { cue -> Cue? in
            guard let start = cue.startTimecode?.offsetSeconds else { return cue }
            let end = start + cue.duration.seconds

            if end <= ffoaOffsetSeconds {
                // Entirely before FFOA -- leader/2-pop/sync-tone material,
                // never real music. Never construct a Cue for it at all.
                return nil
            }
            if start < ffoaOffsetSeconds {
                // Straddles FFOA -- truncate to start exactly at it rather
                // than dropping real content that happens to share one
                // detected region with a sliver of pre-FFOA material (a
                // real case on real production audio, not hypothetical --
                // see docs/DECISIONS.md, this date, for the SEA_STEM cue1
                // finding that motivated this branch).
                return cue.truncatingStart(toOffsetSeconds: ffoaOffsetSeconds)
            }
            return cue
        }
    }
}
