import ACCore
import Foundation

/// Backs `AudioImportView` (`ROADMAP.md` D8/T8.6). Calls Use Cases only,
/// never a Repository directly, per `CONTRIBUTING.md` §6.
///
/// **Chains import then waveform-peak generation itself, as one coherent
/// on-screen progress experience** — SPEC.md §4.15 says waveform generation
/// "runs immediately after import," and this ViewModel is where that
/// chaining actually happens (`ImportAudioUseCase`/`GenerateWaveformPeaksUseCase`
/// are each independently complete Use Cases; sequencing two Use Case calls
/// for one screen's UX is exactly what a ViewModel orchestrates, per
/// `CLAUDE.md`'s MVVM rules — it does not belong hidden inside either Use
/// Case).
@Observable
@MainActor
public final class AudioImportViewModel {
    public enum ImportPhase: Equatable {
        case idle
        case importingFile(fractionCompleted: Double)
        case generatingWaveformOverview(fractionCompleted: Double)
        /// `bookmarkAccessWarning` is non-`nil` only when the imported
        /// `AudioAsset.bookmarkAccessMode == .plainFallback` (SPEC.md
        /// §4.10) — the import itself still succeeded, but persistent
        /// access to this file isn't guaranteed to survive an app
        /// relaunch. Surfaced honestly rather than as a silent success or a
        /// hard failure, since the underlying cause is outside this app's
        /// control.
        case completed(bookmarkAccessWarning: String?)
        case failed(message: String)
    }

    public let projectID: Project.ID
    public private(set) var phase: ImportPhase = .idle

    private let importAudioUseCase: ImportAudioUseCase
    private let generateWaveformPeaksUseCase: GenerateWaveformPeaksUseCase

    public init(
        projectID: Project.ID,
        importAudioUseCase: ImportAudioUseCase,
        generateWaveformPeaksUseCase: GenerateWaveformPeaksUseCase
    ) {
        self.projectID = projectID
        self.importAudioUseCase = importAudioUseCase
        self.generateWaveformPeaksUseCase = generateWaveformPeaksUseCase
    }

    public func importFile(from url: URL) {
        phase = .importingFile(fractionCompleted: 0)
        Task { [weak self] in
            guard let self else { return }
            do {
                let asset = try await runImport(from: url)
                try await runWaveformGeneration(for: asset)
                phase = .completed(bookmarkAccessWarning: Self.bookmarkAccessWarning(for: asset))
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Resumes waveform-peak generation alone, against an already-persisted
    /// `AudioAsset` — the partial-import resume case `CueSheetSectionViewModel`
    /// (`ROADMAP.md` D9/T9.5) routes to `.needsWaveformGeneration` for: a
    /// real, reachable state where `Project.audioAsset` exists but
    /// `.waveformPeaks` never completed (a quit/crash between
    /// `ImportAudioUseCase` and `GenerateWaveformPeaksUseCase`'s two
    /// sequential calls in `importFile(from:)`, above). No re-import step,
    /// no new Use Case — reuses the same private `runWaveformGeneration(for:)`
    /// and `ImportPhase` cases the fresh-import path already uses, per
    /// `SPEC.md` §4.21.
    public func resumeWaveformGeneration(for asset: AudioAsset) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await runWaveformGeneration(for: asset)
                phase = .completed(bookmarkAccessWarning: Self.bookmarkAccessWarning(for: asset))
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Surfaces a failure that occurred before any `URL` was even available
    /// to hand to `importFile(from:)` — the drag-and-drop entry point's only
    /// failure mode that isn't already covered by `importFile`'s own
    /// `do`/`catch` (`AudioImportView`'s `.onDrop` handler calls this when
    /// its `NSItemProvider` can't produce a usable file URL at all). Routes
    /// through the same `.failed` phase every other import failure uses —
    /// one source of truth for import status regardless of entry point,
    /// per `CLAUDE.md`'s "Single Source of Truth."
    public func failWithoutImporting(message: String) {
        phase = .failed(message: message)
    }

    /// Resets back to `.idle` — called by `ProjectWindowView` whenever
    /// `CueSheetSectionViewModel.resumeState` routes back to `.needsImport`
    /// (including after `ClearImportedAudioUseCase` clears a previously-
    /// imported asset). Without this, this long-lived, per-window ViewModel
    /// (constructed once, never recreated — `CLAUDE.md`, "Document & Window
    /// Model") kept showing this screen's *previous* cycle's terminal phase
    /// (`.completed`/`.failed`) instead of a genuine fresh import prompt the
    /// second time a project cycled through import → clear → import →
    /// clear — `.completed` renders no "Choose File…" button at all, so the
    /// screen looked stuck. A no-op whenever `phase` is already `.idle`
    /// (the common, first-ever-import case).
    public func resetIfNeeded() {
        guard phase != .idle else { return }
        phase = .idle
    }

    private func runImport(from url: URL) async throws -> AudioAsset {
        var importedAsset: AudioAsset?
        for try await event in importAudioUseCase.importAudio(projectID: projectID, from: url) {
            switch event {
            case let .progress(update):
                phase = .importingFile(fractionCompleted: update.fractionCompleted)
            case let .completed(asset):
                importedAsset = asset
            }
        }
        guard let importedAsset else {
            throw AudioImportViewModelError.streamEndedWithoutCompleting
        }
        return importedAsset
    }

    private func runWaveformGeneration(for asset: AudioAsset) async throws {
        phase = .generatingWaveformOverview(fractionCompleted: 0)
        for try await event in generateWaveformPeaksUseCase.generate(projectID: projectID, asset: asset) {
            if case let .progress(update) = event {
                phase = .generatingWaveformOverview(fractionCompleted: update.fractionCompleted)
            }
        }
    }

    /// SPEC.md §4.10, "Security-scoped bookmark creation can fail entirely":
    /// user-legible, honest framing — not a hard failure, and not silently
    /// treated as equivalent to the normal case.
    private static func bookmarkAccessWarning(for asset: AudioAsset) -> String? {
        guard asset.bookmarkAccessMode == .plainFallback else { return nil }
        return "This file's access may need to be re-selected after restarting the app."
    }
}

enum AudioImportViewModelError: Error, Equatable {
    case streamEndedWithoutCompleting
}
