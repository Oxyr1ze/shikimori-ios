import SwiftUI

@main
struct ShikimoriApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        // Больше места под картинки: постеры остаются на телефоне и открываются без интернета.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 600 * 1024 * 1024)
    }

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
        .task {
            RateStore.shared.restore()
            await RateStore.shared.refresh()
        }
    }
}
