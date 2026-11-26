import Foundation

/// Простой кэш на диске: последние полученные данные сохраняются и показываются сразу, в том числе без интернета.
enum DiskCache {
    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DataCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return folder.appendingPathComponent(safe + ".json")
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Сколько секунд назад сохранены данные (nil, если их нет).
    static func age(key: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file(key).path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(date)
    }

    /// Удаляет все сохранённые данные (при выходе из аккаунта).
    static func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Ключ с номером пользователя: у каждого аккаунта свои списки.
    @MainActor
    static func userKey(_ name: String) -> String {
        "u\(AuthManager.shared.user?.id ?? 0)-\(name)"
    }
}

let offlineMessage = "Нет соединения. Показаны сохранённые данные."
