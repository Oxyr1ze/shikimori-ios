import SwiftUI

/// Карточка человека или персонажа: круглое фото, имя и необязательная подпись.
struct PersonCellView: View {
    let person: CastPerson
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: 54, height: 54)
                .overlay { RemoteImage(urls: person.imageURLs, placeholder: "person.fill") }
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(person.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension Array where Element == Role {
    /// Персонажи: сначала главные, потом второстепенные (порядок внутри как на сайте).
    var mainCharacters: [Role] { filter { $0.character != nil && $0.isMain } }
    var otherCharacters: [Role] { filter { $0.character != nil && !$0.isMain } }
    var allCharactersSorted: [Role] { mainCharacters + otherCharacters }
    /// Создатели по важности роли.
    var staffSorted: [Role] {
        filter { $0.person != nil }
            .enumerated()
            .sorted { ($0.element.staffRank, $0.offset) < ($1.element.staffRank, $1.offset) }
            .map(\.element)
    }
}

private let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

/// Экран «Персонажи»: главные и второстепенные герои.
struct TitleCharactersScreen: View {
    let roles: [Role]

    private func grid(_ list: [Role]) -> some View {
        LazyVGrid(columns: twoColumns, spacing: 10) {
            ForEach(list) { role in
                if let c = role.character {
                    NavigationLink { CharacterView(id: c.id) } label: { PersonCellView(person: c) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        let main = roles.mainCharacters
        let other = roles.otherCharacters
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !main.isEmpty {
                    Text(other.isEmpty ? "Персонажи" : "Главные герои").font(.title3.weight(.bold))
                    grid(main)
                }
                if !other.isEmpty {
                    Text(main.isEmpty ? "Персонажи" : "Второстепенные герои").font(.title3.weight(.bold))
                    grid(other)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Персонажи")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Экран «Создатели».
struct TitleStaffScreen: View {
    let roles: [Role]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: twoColumns, spacing: 10) {
                ForEach(roles.staffSorted) { role in
                    if let p = role.person {
                        NavigationLink { PersonView(id: p.id) } label: {
                            PersonCellView(person: p, subtitle: role.staffRolesText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Создатели")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Экран «Похожее»: сетка как в каталоге, оценка справа сверху.
struct SimilarScreen: View {
    let items: [Media]
    let kind: MediaKind

    var body: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        ScrollView {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink { TitleView(ref: MediaRef(id: item.id, kind: kind)) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterView(urls: item.thumbCandidates, radius: 18, rateKey: RateStore.key(kind, item.id))
                                .overlay(alignment: .topTrailing) {
                                    if let s = item.scoreText { ScoreBadge(text: s).padding(8) }
                                }
                            Text(item.title).font(.subheadline.weight(.semibold))
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text([item.kind.map(kindTitle), item.yearText].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Похожее")
        .navigationBarTitleDisplayMode(.inline)
    }
}
