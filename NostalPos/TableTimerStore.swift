import Foundation

/// 持久化每桌計時器的 startTime / isActive
/// - 只存 timestamp，不存 elapsed
/// - 內部會做 table key 正規化，避免「台/臺」等字形差異導致詐屍
final class TableTimerStore {
    static let shared = TableTimerStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let prefix = "nostalpos.tableTimer."

    // ✅ 統一 table key：trim + 將常見的「台」統一成「臺」
    private func normalizeTableKey(_ table: String) -> String {
        let trimmed = table.trimmingCharacters(in: .whitespacesAndNewlines)
        // 你桌名裡會用到「臺」字，且 log 出現「台/臺」混用，這裡統一成「臺」
        // 若未來你真的有桌名包含「台」且就是要「台」，再來調整映射表即可。
        return trimmed.replacingOccurrences(of: "台", with: "臺")
    }

    private func key(_ table: String, _ field: String) -> String {
        "\(prefix)\(normalizeTableKey(table)).\(field)"
    }

    func save(table: String, startTime: Date?, isActive: Bool) {
        if let startTime {
            defaults.set(startTime.timeIntervalSince1970, forKey: key(table, "start"))
        } else {
            defaults.removeObject(forKey: key(table, "start"))
        }
        defaults.set(isActive, forKey: key(table, "active"))
    }

    func load(table: String) -> (startTime: Date?, isActive: Bool) {
        let active = defaults.bool(forKey: key(table, "active"))

        guard defaults.object(forKey: key(table, "start")) != nil else {
            return (nil, active)
        }

        let t = defaults.double(forKey: key(table, "start"))
        return (Date(timeIntervalSince1970: t), active)
    }

    func clear(table: String) {
        defaults.removeObject(forKey: key(table, "start"))
        defaults.removeObject(forKey: key(table, "active"))

        // ✅ 額外保險：把「另一個字形」也清掉，避免你之前已經寫入的舊 key 留著
        // 若 table 傳進來已經是「臺」，那 alt 就是「台」；反之亦然
        let normalized = normalizeTableKey(table)
        let alt = normalized.replacingOccurrences(of: "臺", with: "台")
        defaults.removeObject(forKey: "\(prefix)\(alt).start")
        defaults.removeObject(forKey: "\(prefix)\(alt).active")
    }
}

