import SwiftUI

enum OrbStyle {
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

struct OrbIcon: View {
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

struct OrbSidebarSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OrbStyle.sectionHeadingForeground)
                .padding(.horizontal, 10)

            VStack(spacing: 1) {
                content()
            }
        }
    }
}

struct OrbSidebarButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool = false
    var count: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                OrbIcon(systemName: systemImage)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(OrbStyle.selectedBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct OrbGroupedPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbStyle.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct OrbActionRow: View {
    var title: String
    var systemImage: String
    var showsChevron: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                OrbIcon(systemName: systemImage, filled: true)

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

struct OrbPillSegment<Selection: Hashable>: View {
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
                        .fill(OrbStyle.selectedBackground)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
