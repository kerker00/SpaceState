import AppKit
import SwiftUI

/// Fit ordinary windows to their content until the user chooses a size.
/// The background view never handles input or presents another window.
struct MacWindowSizing: NSViewRepresentable {
    var preferredHeight: CGFloat?
    var minimum: NSSize

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.preferredHeight = preferredHeight
        view.minimum = minimum
        view.scheduleResize()
    }

    final class SizingView: NSView {
        var preferredHeight: CGFloat?
        var minimum = NSSize(width: 440, height: 280)
        private var userSized = false
        private var resizePending = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            userSized = false
            scheduleResize()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            userSized = true
        }

        func scheduleResize() {
            guard !resizePending else { return }
            resizePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizePending = false
                self.resizeWindow()
            }
        }

        private func resizeWindow() {
            guard let window, !window.inLiveResize else { return }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let maximumHeight = max(160, min(680, (visible?.height ?? 800) - chrome - 24))
            let minimumHeight = min(minimum.height, maximumHeight)
            window.contentMinSize = NSSize(width: minimum.width, height: minimumHeight)
            let current = window.contentRect(forFrameRect: window.frame).size
            let proposed = !userSized ? preferredHeight ?? current.height : current.height
            guard proposed.isFinite, proposed > 0 else { return }
            let height = min(maximumHeight, max(minimumHeight, ceil(proposed)))
            let width = min(max(minimum.width, current.width), visible?.width ?? 1440)
            guard abs(current.height - height) > 1 || abs(current.width - width) > 1 else { return }
            var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            if let visible {
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            }
            window.setFrame(frame, display: true)
        }
    }
}
