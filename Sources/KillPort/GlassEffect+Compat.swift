import SwiftUI

// MARK: - Liquid Glass Compatibility

extension View {

    /// Applies a Liquid Glass effect on macOS 26+, falling back to a translucent
    /// `.ultraThinMaterial` background on older systems.
    ///
    /// On macOS 26 (Tahoe) and later, this calls the native `glassEffect(in:)`
    /// modifier, which renders the Liquid Glass material in the given shape
    /// behind the view and applies subtle foreground optical effects over the
    /// view's content.
    ///
    /// On macOS 12–15, the fallback uses `.ultraThinMaterial` in the same shape
    /// to provide a visually similar translucent background without the full
    /// Liquid Glass lensing and specular highlights.
    ///
    /// - Parameter shape: The shape in which the glass/material is rendered.
    ///   Defaults to a `RoundedRectangle(cornerRadius: 12)`.
    /// - Returns: A view with a glass-like translucent background.
    @ViewBuilder
    func glassBackground(
        in shape: some Shape = RoundedRectangle(cornerRadius: 12)
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(
                .ultraThinMaterial,
                in: shape
            )
        }
    }
}
