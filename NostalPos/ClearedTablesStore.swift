//
//  ClearedTablesStore.swift
//  NostalPos
//

import Foundation

struct UndoBackups {
    var sheetBackups: [String: TableOrderSnapshot]                       = [:]
    var timerBackups: [String: (elapsed: TimeInterval, isActive: Bool)]  = [:]
    var roundStartBackups: [String: TimeInterval]                         = [:]
}

final class ClearedTablesStore {
    static let shared = ClearedTablesStore()
    private init() {}

    private let clearedKey = "pos.clearedTables"
    private var _undoBackups = UndoBackups()

    // MARK: - 清桌狀態（UserDefaults）

    func save(_ tables: Set<String>) {
        UserDefaults.standard.set(Array(tables), forKey: clearedKey)
    }

    func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: clearedKey) ?? [])
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: clearedKey)
    }

    // MARK: - 復原備份（in-memory，CartLine 非 Codable 故無法持久化）

    func saveUndoBackups(
        sheetBackups: [String: TableOrderSnapshot],
        timerBackups: [String: (elapsed: TimeInterval, isActive: Bool)],
        roundStartBackups: [String: TimeInterval]
    ) {
        _undoBackups = UndoBackups(
            sheetBackups: sheetBackups,
            timerBackups: timerBackups,
            roundStartBackups: roundStartBackups
        )
    }

    func loadUndoBackups() -> UndoBackups {
        _undoBackups
    }

    func clearUndoBackups() {
        _undoBackups = UndoBackups()
    }
}
