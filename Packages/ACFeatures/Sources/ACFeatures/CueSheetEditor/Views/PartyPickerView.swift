import ACCore
import ACDesignSystem
import SwiftUI

/// Lets the user pick an existing `Person`/`Label` from the project's
/// directory, or create a new one inline — used for `Setup.producer`/
/// `.directorOrPrincipal`/`.declarant` (`ROADMAP.md` D7/T7.3). One combined
/// list, not two separate Person/Label pickers — the SUISA form's own field
/// language ("name, first name **or publishing company**") treats them as
/// interchangeable answers to the same question.
///
/// Backed directly by `RightHolderDirectoryViewModel` (not plain closures,
/// unlike `PersonEditorSheet`/`LabelEditorSheet`) — this View's whole job
/// *is* presenting that ViewModel's directory and driving its create
/// methods, so there's no adapter-at-the-edge boundary to cross here.
struct PartyPickerView: View {
    let directoryViewModel: RightHolderDirectoryViewModel
    let onSelect: (Party) -> Void
    let onCancel: () -> Void

    @State private var isShowingNewPersonSheet = false
    @State private var isShowingNewLabelSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Select Person or Label")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            if directoryViewModel.people.isEmpty, directoryViewModel.labels.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Entries Yet",
                    message: "Create a new Person or Label to get started.",
                    surface: .primary
                )
            } else {
                List {
                    ForEach(directoryViewModel.people) { person in
                        rowButton(title: "\(person.firstName) \(person.lastName)") {
                            onSelect(.person(person.id))
                        }
                    }
                    ForEach(directoryViewModel.labels) { label in
                        rowButton(title: label.name) {
                            onSelect(.label(label.id))
                        }
                    }
                }
                .listStyle(.plain)
                // List paints its own native background material behind
                // rows on macOS, which a plain .background() on the List
                // does not override (the exact bug D6's ProjectLibraryView
                // already hit and fixed this same way) — without this, row
                // text renders on that native material instead of this
                // app's fixed white surface, unreadable under system Dark
                // Mode. Confirmed via a real rendered window, not assumed.
                .scrollContentBackground(.hidden)
                .background(Theme.Surface.primary.background)
                .frame(height: 220)
            }

            HStack {
                Button("+ New Person") { isShowingNewPersonSheet = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                Button("+ New Label") { isShowingNewLabelSheet = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 380)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
        // Deliberately does NOT call directoryViewModel.loadDirectory() on
        // appear. SetupView already loads it once, and every RightHolder-
        // DirectoryViewModel mutation (savePerson/saveLabel/deletePerson/
        // deleteLabel) updates people/labels in place — a second, redundant
        // subscription here raced against the "+ New Person" save flow: if
        // this task's own `for await ... break` happened to capture the
        // stream's pre-save snapshot (a real, confirmed ordering hazard,
        // not hypothetical — see docs/DECISIONS.md), it would silently
        // overwrite the optimistic post-save update, which is exactly what
        // produced "selecting closes the sheet but shows the old/blank
        // state until the picker is reopened."
        .sheet(isPresented: $isShowingNewPersonSheet) {
            PersonEditorSheet(
                existing: nil,
                onSave: { person in
                    isShowingNewPersonSheet = false
                    Task {
                        if await directoryViewModel.savePerson(person) {
                            onSelect(.person(person.id))
                        }
                    }
                },
                onCancel: { isShowingNewPersonSheet = false }
            )
        }
        .sheet(isPresented: $isShowingNewLabelSheet) {
            LabelEditorSheet(
                existing: nil,
                onSave: { label in
                    isShowingNewLabelSheet = false
                    Task {
                        if await directoryViewModel.saveLabel(label) {
                            onSelect(.label(label.id))
                        }
                    }
                },
                onCancel: { isShowingNewLabelSheet = false }
            )
        }
    }

    private func rowButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(Theme.Surface.primary.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHandCursor()
    }
}
