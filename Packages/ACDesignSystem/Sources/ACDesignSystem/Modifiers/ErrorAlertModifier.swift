import SwiftUI

public struct ErrorAlertModifier: ViewModifier {
    @Binding private var errorMessage: String?

    public init(errorMessage: Binding<String?>) {
        _errorMessage = errorMessage
    }

    public func body(content: Content) -> some View {
        content.alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK") {
                    errorMessage = nil
                }
            },
            message: {
                Text(errorMessage ?? "")
            }
        )
    }
}

public extension View {
    /// Presents `message`'s value as a standard alert, then clears it on dismiss.
    func errorAlert(message: Binding<String?>) -> some View {
        modifier(ErrorAlertModifier(errorMessage: message))
    }
}

private struct ErrorAlertPreviewHost: View {
    @State private var errorMessage: String? = "Something went wrong."

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Content behind the alert")
            Button("Show Error") {
                errorMessage = "Something went wrong."
            }
            .buttonStyle(SharpButtonStyle())
        }
        .padding(Theme.Spacing.lg)
        .errorAlert(message: $errorMessage)
    }
}

#Preview("ErrorAlertModifier") {
    ErrorAlertPreviewHost()
}
