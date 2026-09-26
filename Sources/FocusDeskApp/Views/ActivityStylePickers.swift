import SwiftUI

struct ActivitySymbolGroup: Identifiable {
    var title: String
    var keywords: String
    var symbols: [String]
    var id: String { title }

    static let all: [ActivitySymbolGroup] = [
        .init(title: "Work & study", keywords: "работа учеба учёба офис программирование learning coding", symbols: [
            "briefcase", "laptopcomputer", "desktopcomputer", "keyboard", "terminal", "curlybraces", "hammer",
            "wrench.and.screwdriver", "gearshape", "folder", "doc.text", "doc.richtext", "tray", "archivebox",
            "calendar", "checklist", "checkmark.circle", "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis",
            "book", "books.vertical", "graduationcap", "pencil", "pencil.and.outline", "lightbulb", "brain", "magnifyingglass"
        ]),
        .init(title: "Health & rest", keywords: "здоровье отдых сон спорт усталость медитация energy sleep tired exhausted exercise", symbols: [
            "heart", "heart.text.square", "cross.case", "pills", "bandage", "stethoscope", "bed.double", "moon",
            "moon.zzz", "zzz", "battery.0", "battery.25", "battery.100", "bolt", "flame", "leaf", "lungs",
            "figure.walk", "figure.run", "bicycle", "dumbbell", "sportscourt", "sun.max", "cloud", "cloud.rain", "drop"
        ]),
        .init(title: "Home & food", keywords: "дом быт еда кофе обед уборка покупки food coffee cooking shopping", symbols: [
            "house", "building.2", "key", "lock", "lightbulb.fill", "sofa", "house.fill", "shower", "bathtub",
            "washer", "tshirt", "hanger", "basket", "cart", "bag", "gift", "cup.and.saucer", "mug",
            "fork.knife", "carrot", "birthday.cake", "wineglass", "takeoutbag.and.cup.and.straw"
        ]),
        .init(title: "Creative & leisure", keywords: "творчество досуг музыка игры фильмы фото рисование music games art hobby", symbols: [
            "music.note", "music.note.list", "headphones", "guitars", "pianokeys", "mic", "radio", "play.circle",
            "film", "tv", "camera", "photo", "paintbrush", "paintpalette", "scissors", "theatermasks",
            "gamecontroller", "puzzlepiece", "dice", "suit.spade", "sparkles", "star", "wand.and.stars"
        ]),
        .init(title: "People & travel", keywords: "люди общение семья друзья звонок поездка дорога транспорт people family friends call travel", symbols: [
            "person", "person.2", "person.3", "person.crop.circle", "hand.wave", "hands.clap", "bubble.left",
            "bubble.left.and.bubble.right", "phone", "video", "envelope", "paperplane", "at", "globe", "map",
            "mappin.and.ellipse", "location", "compass.drawing", "airplane", "car", "bus", "tram", "ferry", "suitcase", "tent"
        ]),
        .init(title: "Other", keywords: "другое время цель финансы деньги other time goal money", symbols: [
            "ellipsis", "circle", "square", "triangle", "diamond", "hexagon", "plus", "minus", "checkmark",
            "xmark", "questionmark.circle", "exclamationmark.circle", "flag", "target", "scope", "clock", "timer",
            "stopwatch", "hourglass", "bell", "bookmark", "tag", "link", "paperclip", "creditcard", "banknote", "dollarsign.circle"
        ])
    ]

    func matching(_ query: String) -> [String] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return symbols.filter { symbol in
            let text = "\(title) \(keywords) \(symbol.replacingOccurrences(of: ".", with: " "))"
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }
    }
}

struct ActivitySymbolPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("activityRecentSymbols") private var recentSymbols = ""
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 10)

    private var recent: [String] {
        let known = Set(ActivitySymbolGroup.all.flatMap(\.symbols))
        return recentSymbols.split(separator: "|").map(String.init).filter { known.contains($0) }
    }
    private var groups: [(group: ActivitySymbolGroup, symbols: [String])] {
        ActivitySymbolGroup.all.map { ($0, $0.matching(query)) }.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Icons").font(.headline)
                Spacer()
                ActivityIconButton(symbol: "xmark", title: "Close icons") { dismiss() }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search icons…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    ActivityIconButton(symbol: "xmark.circle.fill", title: "Clear search") { query = "" }
                }
            }
            .padding(8)
            .background(FocusDeskStyle.focusSurface, in: RoundedRectangle(cornerRadius: 6))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.isEmpty, !recent.isEmpty { section("Recent", symbols: recent) }
                    ForEach(groups, id: \.group.id) { item in
                        section(item.group.title, symbols: item.symbols)
                    }
                    if groups.isEmpty {
                        Text("No icons found. Try another search.")
                            .foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 374)
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }

    private func section(_ title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        recentSymbols = ([symbol] + recent.filter { $0 != symbol }).prefix(16).joined(separator: "|")
                        dismiss()
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(TaskTagPalette.gray.foreground)
                            .frame(width: 26, height: 26)
                            .background(selection == symbol ? FocusDeskStyle.selectedBackground : FocusDeskStyle.focusSurface,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityValue(selection == symbol ? "Selected" : "")
                }
            }
        }
    }
}
