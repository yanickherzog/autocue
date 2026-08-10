import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Collaborators" section — the project-scoped right-holder
/// directory (`ROADMAP.md` D7/T7.3), organized into four buckets matching
/// the original product brief: Komponist*in, Arrangeur*in, Interpret*in,
/// Label. See `SetupView`'s own doc comment for why this screen is split
/// across files.
///
/// **Distinct from `Setup.producer`/`.directorOrPrincipal`/`.declarant`.**
/// Those three remain single-value `Setup` fields, each with their own
/// "Select" picker over the *whole* directory (`PartyPickerView`) — SPEC.md
/// has no role restriction on who can be Producer/Director/Declarant, so
/// sharing one directory across all three is correct, not a bug. This
/// section is a different concept: building up `Project.people`/`.labels`
/// itself, organized by `Person.intendedRole` — a UI-only organizing hint
/// (SPEC.md §4.5), not a stored `CueRightHolder.role` (that's D10, assigned
/// per-Cue). See `docs/DECISIONS.md`.
extension SetupView {
    var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Collaborators")
            CollaboratorPersonBucket(title: "Komponist*in", role: .composer, directoryViewModel: directoryViewModel)
            CollaboratorPersonBucket(title: "Arrangeur*in", role: .arranger, directoryViewModel: directoryViewModel)
            CollaboratorPersonBucket(title: "Interpret*in", role: .performer, directoryViewModel: directoryViewModel)
            CollaboratorLabelBucket(directoryViewModel: directoryViewModel)
        }
        .errorAlert(message: blockedDeleteMessage)
    }

    /// Surfaces `RightHolderDirectoryViewModel.blockedDeleteLocations`
    /// (SPEC.md §4.12) as a readable message — one place for all four
    /// buckets' delete attempts, since they share one `directoryViewModel`.
    private var blockedDeleteMessage: Binding<String?> {
        Binding(
            get: {
                guard let locations = directoryViewModel.blockedDeleteLocations, !locations.isEmpty else {
                    return nil
                }
                let described = locations.map(Self.describe).joined(separator: ", ")
                return "Can't delete — still referenced by: \(described)."
            },
            set: { newValue in
                if newValue == nil {
                    directoryViewModel.clearBlockedDeleteLocations()
                }
            }
        )
    }

    private static func describe(_ location: PartyReferenceLocation) -> String {
        switch location {
        case .setupProducer: "Producer"
        case .setupDirectorOrPrincipal: "Director / Principal"
        case .setupDeclarant: "Declarant"
        case .settingsDefaultDeclarant: "Default Declarant (Settings)"
        case .cueRightHolder: "a Cue's right-holder list"
        }
    }
}

/// One Komponist*in/Arrangeur*in/Interpret*in bucket — lists
/// `directoryViewModel.people` filtered to this bucket's `PersonIntendedRole`
/// and lets the user add a brand-new `Person` under it. "+ Add" always
/// creates new (never picks from elsewhere in the directory) — the whole
/// reason this section exists is so a director's name, added under a
/// different context entirely, can't show up here.
private struct CollaboratorPersonBucket: View {
    let title: String
    let role: PersonIntendedRole
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingAddSheet = false

    private var people: [Person] {
        directoryViewModel.people.filter { $0.intendedRole == role }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.font(.medium, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Spacer()
                Button("+ Add") { isShowingAddSheet = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
            ForEach(people) { person in
                HStack {
                    Text("\(person.firstName) \(person.lastName)")
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                    Spacer()
                    Button {
                        Task { await directoryViewModel.deletePerson(person.id) }
                    } label: {
                        Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            PersonEditorSheet(
                existing: nil,
                initialIntendedRole: role,
                onSave: { person in
                    isShowingAddSheet = false
                    Task { await directoryViewModel.savePerson(person) }
                },
                onCancel: { isShowingAddSheet = false }
            )
        }
    }
}

/// The Label bucket — no `intendedRole` concept (there's only one kind of
/// `Label` entry), so this simply lists `directoryViewModel.labels` in full.
private struct CollaboratorLabelBucket: View {
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Label")
                    .font(Theme.Typography.font(.medium, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Spacer()
                Button("+ Add") { isShowingAddSheet = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
            ForEach(directoryViewModel.labels) { label in
                HStack {
                    Text(label.name)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                    Spacer()
                    Button {
                        Task { await directoryViewModel.deleteLabel(label.id) }
                    } label: {
                        Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            LabelEditorSheet(
                existing: nil,
                onSave: { label in
                    isShowingAddSheet = false
                    Task { await directoryViewModel.saveLabel(label) }
                },
                onCancel: { isShowingAddSheet = false }
            )
        }
    }
}
