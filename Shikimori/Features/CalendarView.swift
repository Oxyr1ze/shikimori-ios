import SwiftUI

/// Что показывать в календаре: всё расписание или только тайтлы из моих списков.
enum CalendarFilter: String, CaseIterable, Identifiable {
    case all, mine, watching, planned
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все тайтлы"
        case .mine: return "В моём списке"
        case .watching: return "Смотрю"
        case .planned: return "Запланировано"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .mine: return "bookmark"
        case .watching: return "play.circle"
        case .planned: return "calendar.badge.clock"
        }
    }

    func allows(_ status: String?) -> Bool {
        switch self {
        case .all: return true
        case .mine: return status != nil
        case .watching: return status == "watching" || status == "rewatching"
        case .planned: return status == "planned"
        }
    }
}

@MainActor
final class CalendarModel: ObservableObject {
    struct Day: Identifiable {
        let id: Date
        let items: [CalendarItem]
    }

    @Published var days: [Day] = []
    @Published var loading = false
    @Published var error: String?
    private let cacheKey = "calendar-items-v1"

    private func build(_ items: [CalendarItem]) {
        let cal = Calendar.current
        let sorted = items.filter { $0.date != nil }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let grouped = Dictionary(grouping: sorted) { cal.startOfDay(for: $0.date!) }
        days = grouped.keys.sorted().map { Day(id: $0, items: grouped[$0] ?? []) }
    }

    func restore() {
        if days.isEmpty, let saved = DiskCache.load([CalendarItem].self, key: cacheKey) { build(saved) }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let items = try await AuthManager.shared.calendar()
            build(items)
            DiskCache.save(items, key: cacheKey)
        } catch is CancellationError {
        } catch {
            self.error = days.isEmpty ? error.localizedDescription : offlineMessage
        }
        loading = false
    }
}

struct CalendarView: View {
    @StateObject private var model = CalendarModel()
    @ObservedObject private var rates = RateStore.shared
    @AppStorage("calendar.filter") private var filterRaw = CalendarFilter.all.rawValue
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private var filter: CalendarFilter { CalendarFilter(rawValue: filterRaw) ?? .all }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EE"
        return f
    }()
    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d"
        return f
    }()
    private static let dayLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        let base = Self.dayLong.string(from: date).capitalized
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInTomorrow(date) { return "Завтра" }
        return base
    }

    private func visible(_ day: CalendarModel.Day) -> [CalendarItem] {
        guard filter != .all else { return day.items }
        return day.items.filter { filter.allows(rates.status(RateStore.key(.anime, $0.anime.id))) }
    }

    private func titlesText(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        let word = (m10 == 1 && m100 != 11) ? "тайтл" : ((2...4).contains(m10) && !(12...14).contains(m100)) ? "тайтла" : "тайтлов"
        return "\(n) \(word)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.days.isEmpty { dayStrip }
            if model.days.isEmpty {
                placeholder
            } else {
                TabView(selection: $selected) {
                    ForEach(model.days) { day in
                        page(day).tag(day.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(AppBackground())
        .navigationTitle("Календарь")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Показывать", selection: $filterRaw) {
                        ForEach(CalendarFilter.allCases) { f in
                            Label(f.title, systemImage: f.icon).tag(f.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task {
            model.restore()
            pickInitialDay()
            await model.load()
            pickInitialDay()
        }
        .task { if rates.statuses.isEmpty { await rates.refresh() } }
    }

    /// Сегодняшний день, если он есть в расписании, иначе ближайший.
    private func pickInitialDay() {
        guard !model.days.contains(where: { $0.id == selected }) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        selected = model.days.first(where: { $0.id >= today })?.id ?? model.days.first?.id ?? today
    }

    // MARK: Полоса дней

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.days) { day in
                        let on = day.id == selected
                        let isToday = Calendar.current.isDateInToday(day.id)
                        Button {
                            withAnimation(.snappy) { selected = day.id }
                        } label: {
                            VStack(spacing: 3) {
                                Text(Self.weekdayShort.string(from: day.id).capitalized)
                                    .font(.caption.weight(.semibold))
                                    .opacity(on ? 1 : 0.7)
                                Text(Self.dayNumber.string(from: day.id))
                                    .font(.title3.weight(.bold))
                                Circle()
                                    .fill(isToday ? (on ? Color.white : Theme.accent) : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 50, height: 66)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(day.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: selected) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }

    // MARK: Страница дня

    private let cols = [GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top)]

    private func page(_ day: CalendarModel.Day) -> some View {
        let items = visible(day)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle(day.id)).font(.title3.weight(.bold))
                    Spacer()
                    Text(titlesText(items.count)).font(.subheadline).foregroundStyle(.secondary)
                }
                if filter != .all {
                    Label(filter.title, systemImage: filter.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                if items.isEmpty {
                    ContentUnavailableView(
                        filter == .all ? "В этот день ничего не выходит" : "Из ваших списков ничего не выходит",
                        systemImage: filter == .all ? "calendar" : "bookmark.slash",
                        description: filter == .all ? nil : Text("Выберите «Все тайтлы» в меню справа сверху, чтобы увидеть всё расписание.")
                    )
                    .padding(.top, 30)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(items) { item in
                            NavigationLink {
                                TitleView(ref: MediaRef(id: item.anime.id, kind: .anime))
                            } label: {
                                cell(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.load() } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
        .refreshable { await model.load() }
    }

    private func cell(_ item: CalendarItem) -> some View {
        let aired = (item.date ?? .distantFuture) < Date()
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PosterView(urls: item.anime.thumbCandidates, radius: 14, rateKey: RateStore.key(.anime, item.anime.id))
                if let score = item.anime.score, let v = Double(score), v > 0 {
                    ScoreBadge(text: score).padding(6)
                }
            }
            Text(item.anime.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                if let n = item.nextEpisode { Text("Эп \(n)").foregroundStyle(.secondary) }
                if let d = item.date {
                    if aired {
                        Label("вышла", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.green)
                    } else {
                        Text(Self.timeFormat.string(from: d)).foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
            }
            .font(.caption2)
        }
        .opacity(aired ? 0.8 : 1)
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            Spacer()
        } else if let message = model.error {
            ErrorBanner(message: message) { Task { await model.load() } }.padding(20)
            Spacer()
        } else {
            ContentUnavailableView("Расписание пусто", systemImage: "calendar").padding(.top, 60)
            Spacer()
        }
    }
}
