import SwiftUI

struct ActivityDateControls: View {
    @Binding var selectedDate: Date?
    @State private var showingCalendar = false
    var now: Date

    private var day: Date { selectedDate ?? now }
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: now) }
    private var dateBinding: Binding<Date> {
        Binding(get: { day }, set: {
            selectedDate = Calendar.current.isDate($0, inSameDayAs: now) ? nil : $0
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            ActivityIconButton(symbol: "chevron.left", title: "Previous day") { moveDay(-1) }
            Button { showingCalendar = true } label: {
                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose day")
            .accessibilityLabel("Choose day")
            .accessibilityValue(day.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Day", selection: dateBinding, in: ...now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    HStack {
                        Button("Today") { selectedDate = nil; showingCalendar = false }
                        Spacer()
                        Button("Done") { showingCalendar = false }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
            }
            ActivityIconButton(symbol: "chevron.right", title: "Next day") { moveDay(1) }
                .disabled(isToday)
        }
        .padding(.horizontal, 3)
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(FocusDeskStyle.hairline) }
        .fixedSize()
    }

    private func moveDay(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: day) else { return }
        selectedDate = Calendar.current.isDate(date, inSameDayAs: now) ? nil : date
    }
}
