import SwiftUI

/// Временный экран: «Проверка API». Не финальный дизайн.
struct ApiCheckView: View {
    @StateObject private var checker = ApiChecker()
    @State private var clientID = Keychain.get("client_id")
    @State private var secret = Keychain.get("client_secret")
    @State private var code = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Шаг 1. Публичные запросы")
                        .font(.headline)
                    Button("Проверить API без входа") {
                        Task { await checker.runPublicChecks() }
                    }
                    .buttonStyle(.glassProminent)

                    Divider()

                    Text("Шаг 2. Вход в аккаунт")
                        .font(.headline)
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(.thinMaterial, in: .rect(cornerRadius: 12))
                    SecureField("Client Secret", text: $secret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(.thinMaterial, in: .rect(cornerRadius: 12))

                    Button("Открыть страницу входа в Safari") {
                        Keychain.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), for: "client_id")
                        Keychain.set(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: "client_secret")
                        if let url = checker.authorizeURL(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.glass)

                    TextField("Код со страницы Shikimori", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(.thinMaterial, in: .rect(cornerRadius: 12))

                    Button("Войти по коду и проверить аккаунт") {
                        Task {
                            await checker.exchange(
                                code: code,
                                clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                                secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    .buttonStyle(.glassProminent)

                    HStack {
                        Button("Запросы аккаунта ещё раз") {
                            Task { await checker.runAccountChecks() }
                        }
                        Button("Обновить токен") {
                            Task {
                                await checker.refresh(
                                    clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                                    secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                    }
                    .buttonStyle(.glass)

                    Divider()

                    HStack {
                        Text("Результат").font(.headline)
                        if checker.busy { ProgressView() }
                        Spacer()
                        Button("Копировать") { UIPasteboard.general.string = checker.log }
                            .buttonStyle(.glass)
                    }
                    Text(checker.log.isEmpty ? "Пока пусто" : checker.log)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("Проверка API")
        }
    }
}
