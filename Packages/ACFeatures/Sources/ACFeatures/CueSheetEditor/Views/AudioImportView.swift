import ACDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The Cue Sheet section's audio-import screen (`ROADMAP.md` D8/T8.6) —
/// reached from `ProjectWindowView`'s `.cueSheet` tab until D9/D10 replace
/// it with the real cue-detection/editing screens. Uses SwiftUI's
/// `.fileImporter`, gated by `AutoCue.entitlements`'
/// `com.apple.security.files.user-selected.read-only` entitlement (D8).
public struct AudioImportView: View {
    @Bindable private var viewModel: AudioImportViewModel
    @State private var isPresentingFileImporter = false

    public init(viewModel: AudioImportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            switch viewModel.phase {
            case .idle, .failed:
                EmptyStateView(
                    systemImage: "waveform",
                    title: "Import Audio",
                    message: failureMessage ?? "Select a WAV file to import into this project.",
                    actionTitle: "Choose File…",
                    surface: .primary,
                    action: { isPresentingFileImporter = true }
                )
            case let .importingFile(fractionCompleted):
                ProgressBanner(message: "Importing audio…", fractionCompleted: fractionCompleted)
                    .padding(Theme.Spacing.lg)
            case let .generatingWaveformOverview(fractionCompleted):
                ProgressBanner(message: "Generating waveform overview…", fractionCompleted: fractionCompleted)
                    .padding(Theme.Spacing.lg)
            case let .completed(bookmarkAccessWarning):
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "Audio Imported",
                    message: [bookmarkAccessWarning, "Cue detection and editing are coming in ROADMAP.md D9–D10."]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    surface: .primary
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.primary.background)
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [.wav],
            onCompletion: handleFileImporterResult
        )
    }

    private var failureMessage: String? {
        if case let .failed(message) = viewModel.phase {
            return message
        }
        return nil
    }

    private func handleFileImporterResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            viewModel.importFile(from: url)
        case let .failure(error):
            // `.fileImporter` failing (e.g. the user cancelled) isn't a real
            // import failure — no state change needed, the empty state's
            // own action remains available to try again.
            _ = error
        }
    }
}
