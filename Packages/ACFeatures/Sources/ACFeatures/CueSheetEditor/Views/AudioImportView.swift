import ACDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The Cue Sheet section's audio-import screen (`ROADMAP.md` D8/T8.6) —
/// reached from `ProjectWindowView`'s `.cueSheet` tab until D9/D10 replace
/// it with the real cue-detection/editing screens. Uses SwiftUI's
/// `.fileImporter`, gated by `AutoCue.entitlements`'
/// `com.apple.security.files.user-selected.read-only` entitlement (D8).
///
/// **Two ways to obtain the file, one entry point once a `URL` exists.**
/// Both the "Choose File…" button (`.fileImporter`) and drag-and-drop
/// (`.onDrop`) funnel into the same `viewModel.importFile(from:)` — neither
/// path reimplements or bypasses `AudioAnalysisRepositoryImpl`'s
/// security-scoped-bookmark/plain-fallback handling (SPEC.md §4.10);
/// drag-and-drop is purely a second way to obtain the `URL` that mechanism
/// already accepts. A file dropped from Finder into a sandboxed app is
/// Powerbox-mediated the same way `.fileImporter`'s selection is — the
/// `NSItemProvider`-vended `URL` is just as security-scopable, extracted via
/// `loadItem(forTypeIdentifier: UTType.fileURL.identifier)` rather than
/// `loadFileRepresentation`/`loadInPlaceFileRepresentation` (both of which
/// hand back a URL scoped to the completion handler's lifetime, or a
/// throwaway copy — the wrong shape for a URL this screen needs to still be
/// valid a `Task` hop later).
///
/// **`.onDrop`'s accepted-type list must include `.fileURL`, not just
/// `.wav` — confirmed via real drag testing, not assumed.** Declaring only
/// `[.wav]` seemed like the obvious, tighter filter (reject non-WAV drags
/// at the cursor), but `.onDrop`'s content-type list doesn't just gate the
/// drop-target highlight — it determines which representations SwiftUI
/// actually negotiates from the drag source at all. `.fileURL` and `.wav`
/// are unrelated types in the UTI hierarchy (a file-URL representation
/// isn't "a kind of" WAV), so a `[.wav]`-only filter meant the file-URL
/// representation was never negotiated in the first place — confirmed by
/// logging the real, live-dragged `NSItemProvider.registeredTypeIdentifiers`
/// during investigation: only `com.microsoft.waveform-audio`, no
/// `public.file-url` at all, which is exactly why both
/// `loadItem(forTypeIdentifier: .fileURL)` and the higher-level
/// `loadObject(ofClass: URL.self)` failed identically
/// (`NSItemProviderErrorDomain` -1000/-1200) regardless of which API was
/// used. The fix is accepting `.fileURL` here and validating WAV-ness
/// explicitly once a URL is obtained, not relying on the type filter to
/// pre-reject non-WAV drops.
public struct AudioImportView: View {
    @Bindable private var viewModel: AudioImportViewModel
    @State private var isPresentingFileImporter = false
    @State private var isDropTargeted = false

    public init(viewModel: AudioImportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            switch viewModel.phase {
            case .idle, .failed:
                importPrompt
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

    /// Replicates `EmptyStateView`'s visual language (icon/title/message,
    /// same tokens) rather than reusing it directly — the action row needs
    /// a second element (the drag-and-drop text) beside the button, which
    /// `EmptyStateView`'s single `actionTitle`/`action` pair can't express.
    /// Stays local to this Feature-layer View rather than promoting
    /// `EmptyStateView` itself to support a trailing-content slot for a
    /// need only this one screen currently has, per `CLAUDE.md` rule 7 and
    /// the Reusable Component Philosophy ("promote... the moment a second
    /// feature needs the same thing" — not before).
    private var importPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.5))

            Text("Import Audio")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            Text(failureMessage ?? "Select a WAV file to import into this project.")
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.sm) {
                Button("Choose File…") { isPresentingFileImporter = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))

                Text("or drag & drop a file here")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.primary.background)
        .overlay(
            Rectangle()
                .strokeBorder(isDropTargeted ? Theme.Colors.accent : .clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
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

    /// `.onDrop`'s type filter is `.fileURL`, not `.wav` — see the type-level
    /// doc comment above for why. That means WAV-ness has to be checked
    /// explicitly here, once a URL is actually in hand, rather than relying
    /// on the drop target to have pre-rejected anything non-WAV. Returning
    /// `true` tells SwiftUI the drop was accepted (matching the live
    /// highlight `isDropTargeted` already showed); the actual
    /// import/rejection is resolved asynchronously once the provider
    /// responds, exactly like `.fileImporter`'s own async completion.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let droppedURL: URL? = if let data = item as? Data {
                URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsURL = item as? NSURL {
                nsURL as URL
            } else {
                nil
            }
            Task { @MainActor in
                guard let droppedURL else {
                    viewModel.failWithoutImporting(
                        message: error?.localizedDescription
                            ?? "Couldn't read the dropped file. Try again or use Choose File…."
                    )
                    return
                }
                let isWAV = UTType(filenameExtension: droppedURL.pathExtension)?.conforms(to: .wav) ?? false
                guard isWAV else {
                    let fileName = droppedURL.lastPathComponent
                    viewModel.failWithoutImporting(
                        message: "\"\(fileName)\" isn't a WAV file. Drop a .wav file, or use Choose File…."
                    )
                    return
                }
                viewModel.importFile(from: droppedURL)
            }
        }
        return true
    }
}
