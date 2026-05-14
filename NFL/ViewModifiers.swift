import SwiftUI

/// Cross-platform shims so the same SwiftUI code compiles on iOS + macOS.
extension View {
    /// `.navigationBarTitleDisplayMode(.inline)` on iOS; no-op on macOS.
    @ViewBuilder
    func navBarInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Disables autocapitalization on iOS where the modifier exists.
    /// macOS text fields don't autocapitalize by default, so it's a no-op there.
    @ViewBuilder
    func iOSNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
