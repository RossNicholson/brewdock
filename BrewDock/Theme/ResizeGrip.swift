import AppKit
import SwiftUI

/// The diagonal-lines grip in a panel's bottom-right corner, so it's obvious
/// the panel can be made bigger. Dragging it resizes the panel, keeping its top
/// edge under the menu bar and respecting the window's minimum size.
/// Shared by BrewDock, ClawdBar and Mop Up.
struct ResizeGrip: NSViewRepresentable {
    /// Called with the new size when the drag ends, to remember it
    var onResized: ((NSSize) -> Void)? = nil

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.onResized = onResized
        view.toolTip = "Drag to resize"
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.handle)
        view.setAccessibilityLabel("Resize")
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.onResized = onResized
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GripView, context: Context) -> CGSize? {
        CGSize(width: 16, height: 16)
    }

    final class GripView: NSView {
        var onResized: ((NSSize) -> Void)?
        private var startMouse: NSPoint = .zero
        private var startFrame: NSRect = .zero

        override var mouseDownCanMoveWindow: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            // Three diagonal lines, longest in the corner
            NSColor.secondaryLabelColor.withAlphaComponent(0.7).setStroke()
            for length in [4.0, 8.0, 12.0] {
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: bounds.maxX - 2 - length, y: bounds.minY + 2))
                path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + 2 + length))
                path.stroke()
            }
        }

        override func resetCursorRects() {
            if #available(macOS 15, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startFrame = window?.frame ?? .zero
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let minSize = window.minSize
            let maxSize = window.maxSize
            let width = min(max(startFrame.width + now.x - startMouse.x, minSize.width), maxSize.width)
            // Dragging down makes it taller
            let height = min(max(startFrame.height + startMouse.y - now.y, minSize.height), maxSize.height)
            // Keep the top edge where it is, hanging from the menu bar
            window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height),
                            display: true)
        }

        override func mouseUp(with event: NSEvent) {
            if let size = window?.frame.size, size != startFrame.size { onResized?(size) }
        }
    }
}
