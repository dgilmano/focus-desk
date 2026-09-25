import Charts
import FocusDeskCore
import SwiftUI

struct ActivityDayBalanceView: View {
    var categories: [ActivityCategory]
    var segments: [ActivityDaySegment]
    var totals: [UUID: TimeInterval]
    var dayEnd: Date
    var onSelectInterval: (ActivityDaySegment) -> Void

    private var recordedCategories: [ActivityCategory] { categories.filter { totals[$0.id, default: 0] > 0 } }
    private var recorded: TimeInterval { totals.values.reduce(0, +) }
    private var untracked: TimeInterval {
        segments.filter { $0.intervalID == nil }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Daily balance")
                .font(.system(size: 17, weight: .semibold))
                .frame(height: 28)
            donut
                .frame(maxWidth: .infinity)
            VStack(spacing: 14) {
                ForEach(recordedCategories) { category in
                    HStack(spacing: 10) {
                        Circle().fill(ActivityAppearance.accent(category.colorName)).frame(width: 10, height: 10)
                        Text(category.name).lineLimit(1).help(category.name)
                        Spacer(minLength: 8)
                        Text(ActivityTimeText.duration(totals[category.id, default: 0]))
                            .monospacedDigit().fixedSize()
                    }
                    .font(.system(size: 12))
                    .accessibilityElement(children: .combine)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Circle().fill(.secondary.opacity(0.3)).frame(width: 10, height: 10)
                Text("Untracked")
                Spacer(minLength: 8)
                Text(ActivityTimeText.duration(untracked)).monospacedDigit().fixedSize()
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .combine)
            dayStrip
        }
    }

    private var donut: some View {
        ZStack {
            if recorded > 0 {
                Chart(recordedCategories) { category in
                    SectorMark(angle: .value("Time", totals[category.id, default: 0]),
                               innerRadius: .ratio(0.72), angularInset: 1)
                        .foregroundStyle(ActivityAppearance.accent(category.colorName).opacity(0.8))
                        .accessibilityLabel(category.name)
                        .accessibilityValue(ActivityTimeText.duration(totals[category.id, default: 0]))
                }
            } else {
                Circle().strokeBorder(FocusDeskStyle.focusSurface, lineWidth: 27)
            }
            VStack(spacing: 5) {
                Text(ActivityTimeText.duration(recorded))
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text("Recorded").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 140)
            .allowsHitTesting(false)
        }
        .frame(width: 200, height: 200)
    }

    @ViewBuilder private var dayStrip: some View {
        if let start = segments.first?.start, let end = segments.last?.end, end > start {
            let duration = end.timeIntervalSince(start)
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        ForEach(segments) { segment in
                            let category = categories.first { $0.id == segment.categoryID }
                            Button { onSelectInterval(segment) } label: {
                                Rectangle()
                                    .fill(segment.intervalID == nil ? Color.secondary.opacity(0.15) :
                                            ActivityAppearance.accent(category?.colorName ?? "gray").opacity(0.8))
                                    .overlay(alignment: .trailing) {
                                        Rectangle().fill(ActivityAppearance.canvas).frame(width: 1)
                                    }
                                    .frame(width: geometry.size.width * segment.duration / duration, height: 18)
                            }
                            .buttonStyle(.plain)
                            .offset(x: geometry.size.width * segment.start.timeIntervalSince(start) / duration)
                            .help("\(category?.name ?? "Untracked"): \(ActivityTimeText.clock(segment.start, dayEnd: dayEnd)) - \(ActivityTimeText.clock(segment.end, dayEnd: dayEnd))")
                            .accessibilityLabel("\(category?.name ?? "Untracked"), \(ActivityTimeText.duration(segment.duration))")
                        }
                    }
                    .frame(width: geometry.size.width, height: 18, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 18)
                HStack {
                    Text(ActivityTimeText.clock(start, dayEnd: dayEnd))
                    Spacer()
                    Text(ActivityTimeText.clock(end, dayEnd: dayEnd))
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
}
