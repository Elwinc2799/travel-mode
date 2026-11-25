import AppKit
import SwiftUI

/// Resizes the menu bar panel's window to its SwiftUI content whenever the content's height changes,
/// keeping the top edge pinned under the menu bar.
struct WindowFitter: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = contentHeight
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            let chrome = window.frame.height - window.contentLayoutRect.height
            let target = (height + chrome).rounded()
            guard abs(window.frame.height - target) > 0.5 else { return }
            var frame = window.frame
            let top = frame.maxY
            frame.size.height = target
            frame.origin.y = top - target
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
