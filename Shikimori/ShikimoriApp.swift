import SwiftUI

@main
struct ShikimoriApp: App {
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if !auth.isReady {
                ZStack {
                    AppBackground()
                    ProgressView()
                }
            } else if !auth.isAuthorized {
                SetupView()
            } else {
                MainTabs()
            }
        }
        .task { await auth.restore() }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Главная", systemImage: "house.fill") { HomeView() }
            Tab("Каталог", systemImage: "square.grid.2x2.fill") { CatalogView() }
            Tab("Списки", systemImage: "bookmark.fill") { ListsView() }
            Tab("Профиль", systemImage: "person.fill") { ProfileView() }
            Tab(role: .search) { SearchView() }
        }
    }
}
