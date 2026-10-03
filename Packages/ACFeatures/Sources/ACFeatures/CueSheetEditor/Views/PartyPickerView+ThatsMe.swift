import ACCore

/// "That's Me" — split into its own file once `PartyPickerView.swift`
/// exceeded `CONTRIBUTING.md` §8's `SwiftLint` file-length threshold, the
/// same reason `PartyPickerView+Sheets.swift` already exists. An `extension
/// PartyPickerView`, not a free function — same "`$state`-style access needs
/// the declaring type, not the declaring file" reasoning that file's own
/// doc comment already establishes.
extension PartyPickerView {
    /// Shown whenever a `ComposerProfile` is on file and this picker ever
    /// lists `Person` entries (`showsThatsMeButton`), regardless of
    /// `allowsCreatingNewEntries`: selecting the app owner's own,
    /// already-confirmed identity (`ComposerProfile`'s own doc comment) is
    /// a fundamentally different action from creating an arbitrary new,
    /// unconnected entry — the concern `allowsCreatingNewEntries == false`
    /// (Declarant) exists to guard against — so it isn't gated by that flag.
    ///
    /// Matches by IPI number first (normalized to bare digits, so a
    /// formatting difference doesn't produce a false negative): if an
    /// existing `Person` in this project's directory already has the same
    /// IPI, selects that `Person` directly rather than creating a second,
    /// duplicate entry for the same real person. Only when no match exists
    /// does this open the "+ New Artist" sheet, pre-filled — visibly and
    /// editably, never locked — from the stored profile. Not `private` —
    /// called directly from `mainContent`'s button action in
    /// `PartyPickerView.swift`.
    func useComposerProfile() {
        guard let profile = directoryViewModel.composerProfile else { return }
        let normalizedProfileIPI = profile.ipiNumber.filter(\.isNumber)
        if let existingMatch = directoryViewModel.people.first(where: { person in
            guard let personIPI = person.ipiNumber, !personIPI.isEmpty else { return false }
            return personIPI.filter(\.isNumber) == normalizedProfileIPI
        }) {
            select(existingMatch)
        } else {
            newPersonPrefillProfile = profile
            isShowingNewPersonSheet = true
        }
    }

    var showsThatsMeButton: Bool {
        scope != .labelOnly && directoryViewModel.composerProfile != nil
    }
}
