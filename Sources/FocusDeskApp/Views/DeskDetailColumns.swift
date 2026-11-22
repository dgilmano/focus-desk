#if DEBUG
import AppKit
import SwiftUI

struct DeskDetailColumns<Inspector: View, Journal: View>: View {
    let width: CGFloat
    @ViewBuilder var inspector: () -> Inspector
    @ViewBuilder var journal: () -> Journal

    @AppStorage(ActivityPreview.isActive ? "previewDeskInspectorFraction" : "deskInspectorFraction")
    private var savedFraction = 0.5
    @GestureState private var dragOffset: CGFloat?
    @State private var hovering = false

    private let gap = FocusDeskStyle.deskPanelSpacing
    private var isWide: Bool { width >= FocusDeskStyle.workspaceCompactBreakpoint }
    private var tileSpace: CGFloat { max(0, width - gap) }
    private var restingWidth: CGFloat {
        clampedWidth(tileSpace * (savedFraction.isFinite ? savedFraction : 0.5))
    }
    private var inspectorWidth: CGFloat { clampedWidth(restingWidth + (dragOffset ?? 0)) }

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(alignment: .top, spacing: gap))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: gap))
        layout {
            inspector()
                .frame(width: isWide ? inspectorWidth : width, alignment: .topLeading)
            journal()
                .frame(width: isWide ? tileSpace - inspectorWidth : width, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: isWide)
        .overlay(alignment: .leading) {
            if isWide {
                let hitWidth = gap + 8
                divider.frame(width: hitWidth)
                    .offset(x: inspectorWidth + (gap - hitWidth) / 2)
            }
        }
    }

    private func clampedWidth(_ value: CGFloat) -> CGFloat {
        let minimum = min(260, tileSpace / 2)
        return min(max(value, minimum), tileSpace - minimum)
    }

    private func storeWidth(_ value: CGFloat) {
        guard isWide else { return }
        savedFraction = clampedWidth(value) / tileSpace
    }

    private var divider: some View {
        let resize = DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragOffset) { value, offset, transaction in
                transaction.animation = nil
                offset = value.translation.width
            }
            .onEnded { value in storeWidth(restingWidth + value.translation.width) }
        let reset = TapGesture(count: 2).onEnded { savedFraction = 0.5 }

        return Color.clear
            .overlay {
                Capsule()
                    .fill(hovering || dragOffset != nil ? FocusDeskStyle.deskAccent : Color.secondary.opacity(0.34))
                    .frame(width: 2, height: 26)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(resize.exclusively(before: reset))
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovering { NSCursor.pop(); hovering = false }
            }
            .help("Drag to resize. Double-click to restore equal widths.")
            .accessibilityElement()
            .accessibilityLabel("Resize Current task and Journal")
            .accessibilityValue("\(Int((inspectorWidth / tileSpace * 100).rounded())) percent Current task")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: storeWidth(inspectorWidth + 24)
                case .decrement: storeWidth(inspectorWidth - 24)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Restore equal widths") { savedFraction = 0.5 }
    }
}
#endif
