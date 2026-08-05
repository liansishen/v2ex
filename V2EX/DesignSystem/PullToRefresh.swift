import SwiftUI

/// Shared native pull-to-refresh behavior for scrollable screens.
struct PullToRefreshModifier: ViewModifier {
    let isEnabled: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            // Keep refresh available when a loading or empty state is shorter
            // than the viewport.
            .scrollBounceBehavior(.always)
            // The system refresh control owns its content inset and settling
            // animation. A custom inset driven by contentOffset creates a
            // feedback loop that makes the list shake while pulling.
            .refreshable {
                guard isEnabled else { return }
                await action()
            }
    }
}

extension View {
    /// Attach to the screen's scrollable content.
    func pullToRefresh(
        isEnabled: Bool = true,
        action: @escaping () async -> Void
    ) -> some View {
        modifier(
            PullToRefreshModifier(
                isEnabled: isEnabled,
                action: action
            )
        )
    }
}
