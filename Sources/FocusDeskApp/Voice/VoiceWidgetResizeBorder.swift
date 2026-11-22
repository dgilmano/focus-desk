#if DEBUG && !FOCUS_DESK_UPDATES
import AppKit
import SwiftUI

struct VoiceWidgetResizeBorder: View {
    let frame: CGRect
    let limits: CGRect
    let resize: (CGRect) -> Void
    static let minimumSize = CGSize(width: 320, height: 260)

    var body: some View {
        ZStack {
            grip(.leading)
            grip(.trailing)
            grip(.top)
            grip(.bottom)
            grip(.topLeading)
            grip(.topTrailing)
            grip(.bottomLeading)
            grip(.bottomTrailing)
        }
        .accessibilityHidden(true)
    }

    private func grip(_ edge: Alignment) -> some View {
        let changesWidth = edge.horizontal != .center
        let changesHeight = edge.vertical != .center
        let thickness: CGFloat = changesWidth && changesHeight ? 12 : 7
        return VoiceResizeGrip(edge: edge) { delta in
            var left = frame.minX, right = frame.maxX
            var top = frame.minY, bottom = frame.maxY
            let minimum = Self.minimumSize
            if edge.horizontal == .leading {
                left = max(limits.minX, min(right - minimum.width, left + delta.width))
            } else if edge.horizontal == .trailing {
                right = min(limits.maxX, max(left + minimum.width, right + delta.width))
            }
            if edge.vertical == .top {
                top = max(limits.minY, min(bottom - minimum.height, top + delta.height))
            } else if edge.vertical == .bottom {
                bottom = min(limits.maxY, max(top + minimum.height, bottom + delta.height))
            }
            resize(CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
        .frame(width: changesWidth ? thickness : nil, height: changesHeight ? thickness : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
    }
}

private struct VoiceResizeGrip: NSViewRepresentable {
    let edge: Alignment
    let resize: (CGSize) -> Void

    func makeNSView(context: Context) -> GripView { GripView() }

    func updateNSView(_ view: GripView, context: Context) {
        view.resize = resize
        view.cursor = cursor
    }

    private var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch edge {
            case .leading: position = .left
            case .trailing: position = .right
            case .top: position = .top
            case .bottom: position = .bottom
            case .topLeading: position = .topLeft
            case .topTrailing: position = .topRight
            case .bottomLeading: position = .bottomLeft
            default: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        if edge.vertical == .center { return .resizeLeftRight }
        if edge.horizontal == .center { return .resizeUpDown }
        return .crosshair
    }

    final class GripView: NSView {
        var cursor = NSCursor.arrow
        var resize: ((CGSize) -> Void)?
        private var dragFromStart: ((CGSize) -> Void)?
        private var start = CGPoint.zero

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }

        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow
            // Keep the original geometry as the SwiftUI card moves under the pointer.
            dragFromStart = resize
        }

        override func mouseDragged(with event: NSEvent) {
            let point = event.locationInWindow
            dragFromStart?(CGSize(width: point.x - start.x, height: start.y - point.y))
        }

        override func mouseUp(with event: NSEvent) {
            dragFromStart = nil
        }
    }
}
#endif
