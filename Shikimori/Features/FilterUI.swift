import SwiftUI

// MARK: Общий стиль отдельных экранов

private let pageBackground = Color(UIColor.systemGroupedBackground)
private let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

/// Кнопки «Очистить» и «Готово» вверху отдельных экранов.
private struct PageToolbar: ToolbarContent {
    let canClear: Bool
    let clear: () -> Void
    let done: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Очистить", action: clear)
                .tint(Theme.accent)
                .disabled(!canClear)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: done) { Image(systemName: "checkmark") }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .accessibilityLabel("Готово")
        }
    }
}

struct ChoiceGroup: Identifiable {
    let title: String
    let items: [ExtraNamed]
    var id: String { title }
}

/// Отдельный экран выбора: список с круглыми отметками, вкладки сверху (если групп несколько), поиск.
struct FilterChoicePage: View {
    let title: String
    let groups: [ChoiceGroup]
    @Binding var selection: Set<Int>
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var search = ""

    private var current: ChoiceGroup { groups[min(tab, groups.count - 1)] }

    private func chosen(_ g: ChoiceGroup) -> Int {
        selection.intersection(Set(g.items.compactMap(\.intID))).count
    }

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = current.items.filter { query.isEmpty || ($0.name ?? "").lowercased().contains(query) }
        ScrollView {
            VStack(spacing: 16) {
                if groups.count > 1 {
                    Picker("", selection: $tab) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                            let n = chosen(g)
                            Text(verbatim: n > 0 ? "\(g.title) \(n)" : g.title).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if current.items.isEmpty {
                    ProgressView().padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            if let id = item.intID {
                                Button {
                                    if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                                } label: {
                                    HStack(spacing: 14) {
                                        checkbox(selection.contains(id))
                                        Text(verbatim: item.name ?? "")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < list.count - 1 { Divider().padding(.leading, 56) }
                            }
                        }
                    }
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $search, prompt: "Поиск")
        .toolbar {
            PageToolbar(canClear: !selection.isEmpty, clear: {
                let ids = Set(groups.flatMap(\.items).compactMap(\.intID))
                selection.subtract(ids)
            }, done: { dismiss() })
        }
    }

    private func checkbox(_ on: Bool) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.7), lineWidth: 2).opacity(on ? 0 : 1)
            Circle().fill(Theme.accent).opacity(on ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).opacity(on ? 1 : 0)
        }
        .frame(width: 28, height: 28)
        .animation(.snappy(duration: 0.15), value: on)
    }
}

// MARK: Годы

struct YearRangePage: View {
    @Binding var from: Int
    @Binding var to: Int
    @Environment(\.dismiss) private var dismiss

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var years: [Int] { Array((1960...(currentYear + 1)).reversed()) }

    private struct Preset: Identifiable {
        let title: String
        let from: Int
        let to: Int
        var id: String { title }
    }

    private var presets: [Preset] {
        let y = currentYear
        return [
            Preset(title: "Этот год", from: y, to: y),
            Preset(title: "Последние 5 лет", from: y - 4, to: y + 1),
            Preset(title: "2020-е", from: 2020, to: 2029),
            Preset(title: "2010-е", from: 2010, to: 2019),
            Preset(title: "2000-е", from: 2000, to: 2009),
            Preset(title: "1990-е", from: 1990, to: 1999),
            Preset(title: "До 1990", from: 1960, to: 1989)
        ]
    }

    private var summary: String {
        if from == 0 && to == 0 { return "Любые годы" }
        if from > 0 && to > 0 { return from == to ? String(from) : "\(from) – \(to)" }
        return from > 0 ? "с \(from) года" : "по \(to) год"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: summary)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(from == 0 && to == 0 ? Color.secondary : Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: summary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { p in
                            let on = from == p.from && to == p.to
                            Button { withAnimation(.snappy) { from = p.from; to = p.to } } label: {
                                Text(verbatim: p.title)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .glassEffect(on ? .regular.tint(Theme.accent) : .regular, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)

                HStack(alignment: .top, spacing: 12) {
                    wheelCard("С", value: $from)
                    wheelCard("По", value: $to)
                }
            }
            .padding(16)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("Годы")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            PageToolbar(canClear: from != 0 || to != 0, clear: { from = 0; to = 0 }, done: { dismiss() })
        }
        .onChange(of: from) { _, new in if new > 0 && to > 0 && new > to { to = new } }
        .onChange(of: to) { _, new in if new > 0 && from > 0 && new < from { from = new } }
    }

    private func wheelCard(_ title: String, value: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            Picker("", selection: value) {
                Text(verbatim: "Не важно").tag(0)
                ForEach(years, id: \.self) { Text(verbatim: String($0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
