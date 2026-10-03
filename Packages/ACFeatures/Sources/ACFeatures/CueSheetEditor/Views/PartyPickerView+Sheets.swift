import ACCore
import SwiftUI

/// `PartyPickerView`'s four create/edit sheets (`+ New Artist`, `+ New
/// Label`/`Company`, and both pencil-icon edit sheets) — split out once
/// `PartyPickerView.swift` exceeded `CONTRIBUTING.md` §8's `SwiftLint`
/// file-length threshold, the same reason `SetupView` itself is already
/// split across several `+`-suffixed files. An `extension PartyPickerView`,
/// not a free function — `$isShowingNewPersonSheet`-style `@State`
/// projected-value access only works for an extension on the type that
/// actually declares the property (file doesn't matter, only the type and
/// non-`private` access do), never for a plain struct value handed to a
/// free function.
extension PartyPickerView {
    func partyPickerSheets(_ content: some View) -> some View {
        editSheets(creationSheets(content))
            .errorAlert(message: blockedDeleteMessage)
    }

    /// Deliberately does NOT call directoryViewModel.loadDirectory() on
    /// appear. SetupView already loads it once, and every RightHolder-
    /// DirectoryViewModel mutation (savePerson/saveLabel/deletePerson/
    /// deleteLabel) updates people/labels in place — a second, redundant
    /// subscription here raced against the "+ New Person" save flow: if
    /// this task's own `for await ... break` happened to capture the
    /// stream's pre-save snapshot (a real, confirmed ordering hazard, not
    /// hypothetical — see docs/DECISIONS.md), it would silently overwrite
    /// the optimistic post-save update, which is exactly what produced
    /// "selecting closes the sheet but shows the old/blank state until the
    /// picker is reopened."
    private func creationSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isShowingNewPersonSheet) {
                PersonEditorSheet(
                    existing: nil,
                    initialIntendedRole: initialIntendedRole,
                    showsIPINumberField: showsIPINumberFieldOnCreate,
                    onSave: { person in
                        let result = await directoryViewModel.savePerson(person)
                        if case .saved = result {
                            isShowingNewPersonSheet = false
                            select(person)
                        }
                        return result
                    },
                    onCancel: { isShowingNewPersonSheet = false }
                )
            }
            .sheet(isPresented: $isShowingNewLabelSheet) {
                LabelEditorSheet(
                    existing: nil,
                    displayName: labelDisplayName,
                    showsKindField: showsLabelKindField,
                    newEntryDefaultKind: newLabelDefaultKind,
                    initialIntendedForLabelRoster: initialIntendedForLabelRoster,
                    onSave: { label in
                        let result = await directoryViewModel.saveLabel(label)
                        if case .saved = result {
                            isShowingNewLabelSheet = false
                            onSelect(.label(label.id))
                        }
                        return result
                    },
                    onCancel: { isShowingNewLabelSheet = false }
                )
            }
    }

    private func editSheets(_ content: some View) -> some View {
        content
            .sheet(item: $personBeingEdited) { person in
                PersonEditorSheet(
                    existing: person,
                    onSave: { edited in
                        let result = await directoryViewModel.savePerson(edited)
                        if case .saved = result {
                            personBeingEdited = nil
                        }
                        return result
                    },
                    onCancel: { personBeingEdited = nil }
                )
            }
            .sheet(item: $labelBeingEdited) { label in
                LabelEditorSheet(
                    existing: label,
                    displayName: labelDisplayName,
                    showsKindField: showsLabelKindField,
                    newEntryDefaultKind: newLabelDefaultKind,
                    onSave: { edited in
                        let result = await directoryViewModel.saveLabel(edited)
                        if case .saved = result {
                            labelBeingEdited = nil
                        }
                        return result
                    },
                    onCancel: { labelBeingEdited = nil }
                )
            }
    }
}
