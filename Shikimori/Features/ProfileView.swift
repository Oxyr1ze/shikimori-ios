import SwiftUI

/// Свой профиль выглядит так же, как чужие, плюс кнопки выхода и диагностики.
struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.user {
                    OwnProfileBody(user: user)
                } else {
                    ProgressView()
                }
            }
            .background(AppBackground())
            .navigationTitle("Профиль")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
        }
    }
}

private struct OwnProfileBody: View {
    @StateObject private var model: UserModel
    @EnvironmentObject var auth: AuthManager
    @State private var confirmLogout = false
    @State private var showDiagnostics = false

    init(user: ShikiUser) {
        _model = StateObject(wrappedValue: UserModel(user: user))
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Версия \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                UserContent(model: model)

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
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { auth.logout() }
        }
        .sheet(isPresented: $showDiagnostics) { ApiCheckView() }
    }
}
