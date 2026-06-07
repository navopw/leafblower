import SwiftUI
import AppKit

/// A transparent AppKit layer that reports clicks immediately, with their click
/// count and modifier flags. Using this instead of SwiftUI's
/// `SpatialTapGesture(count:)` avoids the ~250 ms delay SwiftUI imposes while it
/// waits to tell single and double taps apart — so selecting and drilling feel
/// instant. Coordinates are reported top-left origin to match SwiftUI.
struct ClickCatcher: NSViewRepresentable {
    /// `(location, clickCount, shiftHeld)`.
    var onClick: (CGPoint, Int, Bool) -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.onClick = onClick
    }

    final class ClickView: NSView {
        var onClick: ((CGPoint, Int, Bool) -> Void)?

        override var isFlipped: Bool { true }

        override func mouseUp(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            guard bounds.contains(p) else { return }
            onClick?(p, event.clickCount, event.modifierFlags.contains(.shift))
        }
    }
}
