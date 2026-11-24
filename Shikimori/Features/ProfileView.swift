import SwiftUI

@MainActor
final class ProfileModel: ObservableObject {
    @Published var favourites: Favourites?
    @Published var friends: [ShikiUser] = []
    @Published var history: [HistoryItem] = []

    func load() async {
        let api = AuthManager.shared
        favourites = await api.favourites()
        friends = await api.friends()
        history = await api.history()
    }
}

struct ProfileView: View {
    @StateObject private var model = ProfileModel()
    @EnvironmentObject var auth: AuthManager
    @State private var confirmLogout = false
    @State private var showDiagnostics = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Версия \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        AsyncImage(url: auth.user?.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable().foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        Text(auth.user?.nickname ?? "")
                            .font(.title2.weight(.heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    if let fav = model.favourites {
                        MediaRow(title: "Избранное: аниме", items: fav.animes ?? [], kind: .anime)
                        MediaRow(title: "Избранное: манга", items: fav.mangas ?? [], kind: .manga)
                        MediaRow(title: "Избранное: ранобэ", items: fav.ranobe ?? [], kind: .ranobe)
                        favouriteCharacters(fav.characters ?? [])
                    }
                    friendsRow
                    historyList

                    Button { showDiagnostics = true } label: {
                        Label("Диагностика API", systemImage: "stethoscope").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button(role: .destructive) { confirmLogout = true } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Text(version).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Профиль")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task { await model.load() }
            .refreshable { await model.load() }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { auth.logout() }
            }
            .sheet(isPresented: $showDiagnostics) { ApiCheckView() }
        }
    }

    @ViewBuilder
    private func favouriteCharacters(_ list: [CastPerson]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Избранные персонажи").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(list, id: \.id) { c in
                            VStack(spacing: 6) {
                                Color(UIColor.tertiarySystemFill)
                                    .frame(width: 76, height: 76)
                                    .overlay { RemoteImage(urls: c.imageURLs) }
                                    .clipShape(Circle())
                                Text(c.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 84)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var friendsRow: some View {
        if !model.friends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Друзья").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(model.friends, id: \.id) { f in
                            VStack(spacing: 6) {
                                Color(UIColor.tertiarySystemFill)
                                    .frame(width: 60, height: 60)
                                    .overlay { if let u = f.avatarURL { RemoteImage(urls: [u]) } }
                                    .clipShape(Circle())
                                Text(f.nickname)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        let items = model.history.filter { !$0.plainDescription.isEmpty }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Недавняя активность").font(.title3.weight(.bold))
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.plainDescription).font(.subheadline)
                        Text(item.dateText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
