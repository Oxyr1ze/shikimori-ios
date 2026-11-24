import SwiftUI

@MainActor
final class CalendarModel: ObservableObject {
    struct Day: Identifiable {
        let id: Date
        let items: [CalendarItem]
    }

    @Published var days: [Day] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        do {
            let items = try await AuthManager.shared.calendar()
            let cal = Calendar.current
            let sorted = items.filter { $0.date != nil }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            let grouped = Dictionary(grouping: sorted) { cal.startOfDay(for: $0.date!) }
            days = grouped.keys.sorted().map { Day(id: $0, items: grouped[$0] ?? []) }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CalendarView: View {
    @StateObject private var model = CalendarModel()

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInTomorrow(date) { return "Завтра" }
        return Self.dayFormat.string(from: date).capitalized
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayTitle(day.id)).font(.title3.weight(.bold))
                        ForEach(day.items) { item in
                            NavigationLink(value: MediaRef(id: item.anime.id, kind: .anime)) {
                                row(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if model.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.load() } }
                }
                if !model.loading && model.days.isEmpty && model.error == nil {
                    Text("Расписание пусто").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Календарь")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.days.isEmpty { await model.load() } }
        .refreshable { await model.load() }
    }

    private func row(_ item: CalendarItem) -> some View {
        HStack(spacing: 14) {
            PosterView(urls: item.anime.thumbCandidates, radius: 12)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.anime.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let n = item.nextEpisode {
                    Text("\(n)-й эпизод").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let d = item.date {
                Text(Self.timeFormat.string(from: d))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
