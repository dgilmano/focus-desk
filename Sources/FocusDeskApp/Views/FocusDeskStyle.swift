import SwiftUI

enum FocusDeskStyle {
    static var appBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.aqua, .darkAqua])

            if matchedAppearance == .darkAqua {
                return NSColor(calibratedWhite: 0.13, alpha: 1)
            }

            return NSColor(calibratedWhite: 0.965, alpha: 1)
        })
    }

    static var groupedBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var selectedBackground: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
    }

    static var hairline: Color {
        Color(nsColor: .separatorColor).opacity(0.55)
    }

    static var sectionHeadingForeground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.aqua, .darkAqua])

            if matchedAppearance == .darkAqua {
                return NSColor(calibratedWhite: 0.68, alpha: 1)
            }

            return NSColor(calibratedWhite: 0.42, alpha: 1)
        })
    }
}

struct FocusDeskIcon: View {
    var systemName: String
    var filled: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: filled ? 17 : 13, weight: filled ? .medium : .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .frame(width: filled ? 24 : 18, height: filled ? 24 : 18)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.secondary.opacity(0.22))
                }
            }
    }
}

struct FocusDeskSidebarSection<Content: View>: View {
    var title: String
    var isExpanded: Binding<Bool>?
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader

            if isSectionExpanded {
                VStack(spacing: 1) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FocusDeskStyle.sectionHeadingForeground)

            Spacer(minLength: 0)

            if let isExpanded {
                Button {
                    withAnimation(.smooth(duration: 0.16)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "Collapse \(title)" : "Expand \(title)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let isExpanded else {
                return
            }

            withAnimation(.smooth(duration: 0.16)) {
                isExpanded.wrappedValue.toggle()
            }
        }
    }

    private var isSectionExpanded: Bool {
        isExpanded?.wrappedValue ?? true
    }
}

struct FocusDeskSidebarButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool = false
    var count: Int?
    var iconColor: Color = .secondary
    var swatchColor: Color?
    var swatchBorderColor: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                sidebarIcon

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FocusDeskStyle.selectedBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sidebarIcon: some View {
        if let swatchColor {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(swatchColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke((swatchBorderColor ?? iconColor).opacity(0.34), lineWidth: 0.8)
                }
                .frame(width: 12, height: 12)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)
        }
    }
}

struct FocusDeskSidebarTagButton: View {
    var title: String
    var isSelected: Bool = false
    var count: Int?
    var dotColor: Color
    var dotBorderColor: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .overlay {
                        Circle()
                            .stroke((dotBorderColor ?? dotColor).opacity(0.28), lineWidth: 0.7)
                    }
                    .frame(width: 12, height: 12)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FocusDeskStyle.selectedBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FocusDeskSidebarAllTagsButton: View {
    var title: String = "All Tags..."
    var isSelected: Bool = false
    var count: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.9), lineWidth: 1.4)
                        .frame(width: 12, height: 12)
                        .offset(x: -3)

                    Circle()
                        .stroke(Color.primary.opacity(0.9), lineWidth: 1.4)
                        .frame(width: 12, height: 12)
                        .offset(x: 3)
                }
                .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FocusDeskStyle.selectedBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarEmptyLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24, alignment: .leading)
    }
}

struct FocusDeskGroupedPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusDeskStyle.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FocusDeskActionRow: View {
    var title: String
    var systemImage: String
    var showsChevron: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                FocusDeskIcon(systemName: systemImage, filled: true)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FocusDeskPillSegment<Selection: Hashable>: View {
    var title: String
    var systemImage: String
    var value: Selection
    @Binding var selection: Selection

    private var isSelected: Bool {
        selection == value
    }

    var body: some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(FocusDeskStyle.selectedBackground)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
