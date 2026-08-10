import ACCore
import ACDesignSystem
import SwiftUI

/// `Setup.attachmentTypes`'s checkbox group (SPEC.md §4.2.2). Not named in
/// `ROADMAP.md` D7/T7.2's original file list — added because
/// `attachmentTypes`/`otherAttachmentDescription` need UI same as any other
/// §4.2 field; see `docs/DECISIONS.md`. Same shape as `ProductionTypePicker`
/// (both thin wrappers around `CheckboxGridView`) — kept as two small,
/// separate files rather than one shared component, since two instances
/// doesn't clear `CONTRIBUTING.md` §3's rule-of-three bar for *this*
/// specific wrapping (the underlying grid itself already was extracted, at
/// the third instance — see `CheckboxGridView`'s own doc comment).
struct AttachmentTypePicker: View {
    @Binding var selection: Set<AttachmentType>
    @Binding var otherDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CheckboxGridView(items: AttachmentType.allCases, label: Self.displayName, selection: $selection)
            if selection.contains(.other) {
                GhostTextField(placeholder: "Please specify", text: $otherDescription)
            }
        }
    }

    private static func displayName(_ type: AttachmentType) -> String {
        switch type {
        case .score: "Score"
        case .agreement: "Agreement"
        case .soundOrVideoCarrier: "Sound / Video Carrier"
        case .other: "Other"
        }
    }
}
