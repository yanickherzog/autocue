import ACCore
import ACDesignSystem
import SwiftUI

/// The real content for the `Settings` scene (`AutoCueApp.swift`), replacing
/// its `ROADMAP.md` D6/T6.1 placeholder. Edits only the independent
/// `ComposerProfile` store — not `Settings` itself — built narrowly ahead of
/// D15's own full scope; see `docs/DECISIONS.md`.
public struct ComposerProfileSettingsView: View {
    @Bindable var viewModel: ComposerProfileSettingsViewModel

    public init(viewModel: ComposerProfileSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("My Composer Profile")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            Text(
                "Stored once, on this Mac, and never sent anywhere — used only to auto-fill \"That's Me\" " +
                "when you add yourself as a right-holder on a Project."
            )
            .font(Theme.Typography.font(.regular, size: 12))
            .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))

            HStack(spacing: Theme.Spacing.sm) {
                GhostTextField(placeholder: "First Name", text: $viewModel.firstName)
                GhostTextField(placeholder: "Last Name", text: $viewModel.lastName)
            }
            GhostTextField(placeholder: "IPI Number (11 digits)", text: $viewModel.ipiNumber)
            GhostTextField(placeholder: "Email (optional)", text: $viewModel.email)
            PostalAddressFields(
                street: $viewModel.street,
                postalCode: $viewModel.postalCode,
                city: $viewModel.city,
                country: $viewModel.country
            )

            if !viewModel.isFirstSave {
                // "Future only" wording (the feature's own explicit
                // requirement #7) — makes clear this never reaches back
                // into right-holder entries "That's Me" already created.
                Text("Changes here only affect future \"That's Me\" entries — existing ones are untouched.")
                    .font(Theme.Typography.font(.regular, size: 11))
                    .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            }

            HStack {
                Spacer()
                Button(viewModel.isFirstSave ? "Save" : "Save Changes", action: viewModel.requestSave)
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                    .disabled(!viewModel.canSave)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
        .errorAlert(message: $viewModel.errorMessage)
        .alert("Confirm Your IPI Number", isPresented: $viewModel.isShowingConfirmation) {
            Button("Cancel", role: .cancel, action: viewModel.cancelConfirmation)
            Button("Save", action: viewModel.confirmSave)
        } message: {
            Text(
                "\(viewModel.firstName) \(viewModel.lastName) — IPI-Nr. \(viewModel.groupedIPIForConfirmation)\n\n" +
                "This will be saved and used to auto-fill future right-holder entries. Double-check the number " +
                "above is correct before saving — an error here would silently repeat everywhere it's used."
            )
        }
    }
}
