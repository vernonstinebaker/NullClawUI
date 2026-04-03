import SwiftUI

// MARK: - Error Presentation Modifier

/// A view modifier that presents a root-level error alert bound to an
/// `AppModel.presentedErrorMessage`. Dismisses the error when the user taps OK.
///
/// Usage:
/// ```swift
/// ContentView()
///     .rootErrorAlert(appModel: appModel)
/// ```
struct RootErrorAlertModifier: ViewModifier {
    @Bindable var appModel: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: Binding(
                get: { appModel.presentedErrorMessage != nil },
                set: { if !$0 { appModel.dismissError() } }
            )) {
                Button("OK", role: .cancel) {
                    appModel.dismissError()
                }
            } message: {
                if let message = appModel.presentedErrorMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    /// Presents errors from the given AppModel as a root-level alert.
    func rootErrorAlert(appModel: AppModel) -> some View {
        modifier(RootErrorAlertModifier(appModel: appModel))
    }
}
