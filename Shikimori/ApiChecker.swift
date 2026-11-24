import Foundation
import SwiftUI

/// Временный инструмент этапа 3: делает реальные запросы к Shikimori
/// и показывает ответ, чтобы мы проверили API, а не гадали.
@MainActor
final class ApiChecker: ObservableObject {
    @Published var log: String = ""
    @Published var busy = false

    private let host = "https://shikimori.io"
    private let redirect = "urn:ietf:wg:oauth:2.0:oob"
    private let scopes = "user_rates comments topics"

    func append(_ text: String) { log += text + "\n" }

    private func request(_ method: String, _ path: String, body: Data? = nil,
                         contentType: String? = nil, token: String? = nil) async -> (Int, String) {
        guard let url = URL(string: host + path) else { return (-1, "bad url") }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue("ShikiApp", forHTTPHeaderField: "User-Agent")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return (code, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "Ошибка сети: \(error.localizedDescription)")
        }
    }

    private func short(_ s: String, _ n: Int = 350) -> String {
        s.count > n ? String(s.prefix(n)) + "…" : s
    }

    func runPublicChecks() async {
        busy = true; defer { busy = false }
        log = "— Публичные запросы —\n"

        let gql = #"{"query":"{ animes(search: \"Frieren\", limit: 1) { id name russian score status episodes } }"}"#
        var r = await request("POST", "/api/graphql", body: Data(gql.utf8), contentType: "application/json")
        append("GraphQL animes: HTTP \(r.0)\n\(short(r.1))\n")

        r = await request("GET", "/api/animes?limit=1&order=popularity")
        append("REST /api/animes: HTTP \(r.0)\n\(short(r.1))\n")

        r = await request("GET", "/api/calendar")
        append("REST /api/calendar: HTTP \(r.0)\n\(short(r.1, 200))\n")

        r = await request("GET", "/api/animes/52991")
        append("REST /api/animes/52991: HTTP \(r.0)\n\(short(r.1, 200))\n")

        r = await request("GET", "/api/animes/52991/similar")
        append("REST similar: HTTP \(r.0)\n\(short(r.1, 150))\n")

        r = await request("GET", "/api/topics?limit=1&forum=news")
        append("REST /api/topics (news): HTTP \(r.0)\n\(short(r.1, 200))\n")
    }

    func authorizeURL(clientID: String) -> URL? {
        var c = URLComponents(string: host + "/oauth/authorize")
        c?.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes)
        ]
        return c?.url
    }

    private func form(_ items: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").utf8)
    }

    func exchange(code: String, clientID: String, secret: String) async {
        busy = true; defer { busy = false }
        log = "— Вход —\n"
        let body = form([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": secret,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "redirect_uri": redirect
        ])
        let r = await request("POST", "/oauth/token", body: body,
                              contentType: "application/x-www-form-urlencoded")
        guard r.0 == 200,
              let json = try? JSONSerialization.jsonObject(with: Data(r.1.utf8)) as? [String: Any],
              let access = json["access_token"] as? String else {
            append("Обмен кода: HTTP \(r.0)\n\(short(r.1))")
            return
        }
        Keychain.set(access, for: "access_token")
        Keychain.set((json["refresh_token"] as? String) ?? "", for: "refresh_token")
        append("Обмен кода: HTTP 200, токены получены и сохранены в Keychain.")
        append("Срок жизни access token, сек: \(json["expires_in"] ?? "?")")
        append("Доступы (scope): \(json["scope"] ?? "?")\n")
        await runAccountChecks()
    }

    func refresh(clientID: String, secret: String) async {
        busy = true; defer { busy = false }
        log = "— Обновление токена —\n"
        let body = form([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": secret,
            "refresh_token": Keychain.get("refresh_token")
        ])
        let r = await request("POST", "/oauth/token", body: body,
                              contentType: "application/x-www-form-urlencoded")
        if r.0 == 200,
           let json = try? JSONSerialization.jsonObject(with: Data(r.1.utf8)) as? [String: Any],
           let access = json["access_token"] as? String {
            Keychain.set(access, for: "access_token")
            Keychain.set((json["refresh_token"] as? String) ?? "", for: "refresh_token")
            append("Обновление: HTTP 200, новая пара токенов сохранена.")
        } else {
            append("Обновление: HTTP \(r.0)\n\(short(r.1))")
        }
    }

    func runAccountChecks() async {
        let token = Keychain.get("access_token")
        guard !token.isEmpty else { append("Токена нет: сначала войдите."); return }
        busy = true; defer { busy = false }
        append("— Запросы от имени аккаунта —")

        var r = await request("GET", "/api/users/whoami", token: token)
        append("whoami: HTTP \(r.0)\n\(short(r.1, 250))\n")

        var userID = ""
        if let j = try? JSONSerialization.jsonObject(with: Data(r.1.utf8)) as? [String: Any],
           let id = j["id"] { userID = "\(id)" }

        if !userID.isEmpty {
            r = await request("GET", "/api/v2/user_rates?user_id=\(userID)&target_type=Anime&limit=2", token: token)
            append("v2 user_rates: HTTP \(r.0)\n\(short(r.1, 250))\n")

            r = await request("GET", "/api/users/\(userID)/friends?limit=2", token: token)
            append("friends (чтение): HTTP \(r.0)\n\(short(r.1, 150))\n")

            r = await request("GET", "/api/users/\(userID)/favourites", token: token)
            append("favourites: HTTP \(r.0)\n\(short(r.1, 150))\n")

            r = await request("GET", "/api/users/\(userID)/history?limit=2", token: token)
            append("history: HTTP \(r.0)\n\(short(r.1, 150))\n")

            r = await request("GET", "/api/users/\(userID)/anime_rates?limit=2&status=watching", token: token)
            append("anime_rates (v1): HTTP \(r.0)\n\(short(r.1, 150))\n")
        }

        r = await request("GET", "/api/dialogs", token: token)
        append("dialogs (нужен messages): HTTP \(r.0)\n\(short(r.1, 120))\n")
    }
}
