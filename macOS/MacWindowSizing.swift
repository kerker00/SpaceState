import AppKit
import SwiftUI

/// Fit ordinary windows to their content until the user chooses a size.
/// The background view never handles input or presents another window.
struct MacWindowSizing: NSViewRepresentable {
    struct ContentFit: Equatable {
        var contentHeight: CGFloat
        var viewportHeight: CGFloat
    }

    var preferredHeight: CGFloat?
    var minimum: NSSize
    var contentFit: ContentFit? = nil
    var maximumHeight: CGFloat? = 680

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.preferredHeight = preferredHeight
        view.minimum = minimum
        view.contentFit = contentFit
        view.maximumHeight = maximumHeight
        view.scheduleResize()
    }

    final class SizingView: NSView {
        var preferredHeight: CGFloat?
        var minimum = NSSize(width: 440, height: 280)
        var contentFit: ContentFit?
        var maximumHeight: CGFloat? = 680
        private var lastContentFit: ContentFit?
        private var userSized = false
        private var resizePending = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            userSized = false
            lastContentFit = nil
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
            let screenMaximum = (visible?.height ?? 800) - chrome - 24
            let maximumHeight = max(160, min(self.maximumHeight ?? screenMaximum, screenMaximum))
            let minimumHeight = min(minimum.height, maximumHeight)
            window.contentMinSize = NSSize(width: minimum.width, height: minimumHeight)
            let current = window.contentRect(forFrameRect: window.frame).size
            let proposed: CGFloat
            if userSized {
                proposed = current.height
            } else if let contentFit, contentFit.contentHeight.isFinite,
                      contentFit.viewportHeight.isFinite, contentFit.contentHeight > 0,
                      contentFit.viewportHeight > 0 {
                // Add only the space missing from the actual viewport. This
                // includes the real tab/toolbar overhead without guessing it.
                // Never apply the same measurement twice while SwiftUI catches up.
                if contentFit == lastContentFit {
                    proposed = current.height
                } else {
                    lastContentFit = contentFit
                    proposed = current.height + ceil(contentFit.contentHeight) + 1 - contentFit.viewportHeight
                }
            } else {
                lastContentFit = nil
                proposed = preferredHeight ?? current.height
            }
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
