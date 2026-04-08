//
//  TodoStore.swift
//  NostalPos
//

import Foundation
import UserNotifications

// MARK: - 週期單位

enum TodoRepeatUnit: String, Codable, CaseIterable {
    case minutes = "分鐘"
    case hours   = "小時"
    case days    = "天"
    case weeks   = "週"
    case months  = "月"
    case years   = "年"

    var seconds: Double {
        switch self {
        case .minutes: return 60
        case .hours:   return 3600
        case .days:    return 86400
        case .weeks:   return 7 * 86400
        case .months:  return 30 * 86400
        case .years:   return 365 * 86400
        }
    }
}

// MARK: - 分類標籤

struct TodoCategory: Identifiable, Codable {
    var id: UUID
    var name: String
    var colorIndex: Int   // index into TodoCategory.paletteCount（循環使用）

    init(id: UUID = UUID(), name: String, colorIndex: Int = 0) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }

    // 共 8 組淡色配色（bg hex + text hex），UI 層轉成 Color
    static let paletteCount = 8
}

// MARK: - 待辦項目

struct TodoItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var categoryId: UUID?
    var isRecurring: Bool
    var repeatValue: Int
    var repeatUnit: TodoRepeatUnit
    var nextShowAt: Date?
    var reminderDate: Date?    // 截止日期，前一天 9:00 跳出本地通知
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        categoryId: UUID? = nil,
        isRecurring: Bool = false,
        repeatValue: Int = 1,
        repeatUnit: TodoRepeatUnit = .hours,
        nextShowAt: Date? = nil,
        reminderDate: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.categoryId = categoryId
        self.isRecurring = isRecurring
        self.repeatValue = repeatValue
        self.repeatUnit = repeatUnit
        self.nextShowAt = nextShowAt
        self.reminderDate = reminderDate
        self.isCompleted = isCompleted
    }

    var intervalSeconds: TimeInterval {
        repeatUnit.seconds * Double(repeatValue)
    }
}

// MARK: - Store

final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published var items:      [TodoItem]     = []
    @Published var categories: [TodoCategory] = []

    private let itemsKey      = "pos.todoItems"
    private let categoriesKey = "pos.todoCategories"

    private init() {
        loadItems()
        loadCategories()
        if categories.isEmpty {
            categories = [
                TodoCategory(name: "清潔", colorIndex: 0),
                TodoCategory(name: "備料", colorIndex: 1),
                TodoCategory(name: "設備", colorIndex: 2),
                TodoCategory(name: "其他", colorIndex: 3),
            ]
            saveCategories()
        }
    }

    // 目前應顯示的項目（未完成，或週期時間到了）
    var activeItems: [TodoItem] {
        let now = Date()
        return items.filter { item in
            if item.isCompleted {
                if item.isRecurring, let t = item.nextShowAt { return t <= now }
                return false
            }
            return true
        }
    }

    // MARK: 勾選完成

    func complete(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        cancelReminder(for: item.id)
        if item.isRecurring {
            items[idx].isCompleted = true
            items[idx].nextShowAt  = Date().addingTimeInterval(item.intervalSeconds)
        } else {
            items.remove(at: idx)
        }
        saveItems()
    }

    // MARK: 新增 / 刪除

    func add(_ item: TodoItem) {
        items.append(item)
        saveItems()
        scheduleReminder(for: item)
    }

    func update(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        cancelReminder(for: item.id)
        items[idx] = item
        saveItems()
        scheduleReminder(for: item)
    }

    func delete(id: UUID) {
        cancelReminder(for: id)
        items.removeAll { $0.id == id }
        saveItems()
    }

    // MARK: 分類管理

    func addCategory(name: String) {
        let idx = categories.count % TodoCategory.paletteCount
        categories.append(TodoCategory(name: name, colorIndex: idx))
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        for i in items.indices where items[i].categoryId == id {
            items[i].categoryId = nil
        }
        saveItems()
        saveCategories()
    }

    // MARK: 週期檢查（每分鐘呼叫一次）

    func checkRecurring() {
        let now = Date()
        var changed = false
        for i in items.indices {
            guard items[i].isCompleted, items[i].isRecurring,
                  let t = items[i].nextShowAt, t <= now else { continue }
            items[i].isCompleted = false
            items[i].nextShowAt  = nil
            changed = true
        }
        if changed { saveItems() }
    }

    // MARK: 查詢分類

    func category(for id: UUID?) -> TodoCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func categoryName(for id: UUID?) -> String? {
        category(for: id)?.name
    }

    // MARK: 本地通知（截止日期前一天 9:00）

    private func scheduleReminder(for item: TodoItem) {
        guard let reminderDate = item.reminderDate else { return }

        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: reminderDate) else { return }

        // 前一天 9:00
        var components = cal.dateComponents([.year, .month, .day], from: dayBefore)
        components.hour   = 9
        components.minute = 0

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d（EEE）"

        let content = UNMutableNotificationContent()
        content.title = "待辦提醒"
        content.body  = "「\(item.title)」明天（\(f.string(from: reminderDate))）是待辦日期"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId(item.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelReminder(for id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(id)])
    }

    private func notificationId(_ id: UUID) -> String { "todo-reminder-\(id.uuidString)" }

    // MARK: Persistence

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: itemsKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return }
        items = decoded
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: itemsKey)
    }

    private func loadCategories() {
        guard let data = UserDefaults.standard.data(forKey: categoriesKey),
              let decoded = try? JSONDecoder().decode([TodoCategory].self, from: data)
        else { return }
        categories = decoded
    }

    private func saveCategories() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: categoriesKey)
    }
}
