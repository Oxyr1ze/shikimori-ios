import SwiftUI

struct ProfileView: View {
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
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))

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
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { auth.logout() }
            }
            .sheet(isPresented: $showDiagnostics) { ApiCheckView() }
        }
    }
}
