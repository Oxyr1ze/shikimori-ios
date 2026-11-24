import SwiftUI

/// Первый запуск: вводим данные своего OAuth-приложения и входим по коду.
struct SetupView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.openURL) private var openURL
    @State private var clientID = Keychain.get("client_id")
    @State private var secret = Keychain.get("client_secret")
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Shikimori")
                    .font(.system(size: 40, weight: .heavy))
                Text("Войдите в свой аккаунт. Данные приложения хранятся только в защищённом хранилище вашего iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                field("Client ID", text: $clientID, secure: false)
                field("Client Secret", text: $secret, secure: true)

                Button {
                    auth.saveClient(id: clientID, secret: secret)
                    if let url = auth.authorizeURL() { openURL(url) }
                } label: {
                    Text("1. Открыть страницу входа").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(clientID.isEmpty || secret.isEmpty)

                field("2. Код со страницы Shikimori", text: $code, secure: false)

                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text("3. Войти").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(code.isEmpty || busy)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .background(AppBackground())
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Group {
                    if secure { SecureField("", text: text) } else { TextField("", text: text) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    if let s = UIPasteboard.general.string { text.wrappedValue = s }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Вставить из буфера")
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func signIn() async {
        busy = true
        error = nil
        auth.saveClient(id: clientID, secret: secret)
        do {
            try await auth.login(code: code)
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
