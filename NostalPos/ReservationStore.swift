//
//  ReservationStore.swift
//  NostalPos
//

import Foundation

struct PreorderItem: Codable, Identifiable, Equatable {
    var name: String
    var price: Int
    var quantity: Int
    var id: String { name }
}

enum ReservationTitle: String, Codable, CaseIterable {
    case mr   = "先生"
    case ms   = "小姐"
    case none = ""
}

enum ReservationStatus: String, Codable {
    case pending  // 尚未到
    case arrived  // 已到
    case noShow   // No Show
}

struct Reservation: Identifiable, Codable {
    let id: UUID
    var date: String
    var time: String
    var name: String
    var title: ReservationTitle
    var phone: String
    var adults: Int
    var children: Int
    var note: String
    var status: ReservationStatus
    var preorderItems: [PreorderItem]

    init(id: UUID, date: String, time: String, name: String, title: ReservationTitle,
         phone: String, adults: Int, children: Int, note: String,
         status: ReservationStatus = .pending, preorderItems: [PreorderItem] = []) {
        self.id = id; self.date = date; self.time = time; self.name = name
        self.title = title; self.phone = phone; self.adults = adults
        self.children = children; self.note = note; self.status = status
        self.preorderItems = preorderItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,              forKey: .id)
        date         = try c.decode(String.self,            forKey: .date)
        time         = try c.decode(String.self,            forKey: .time)
        name         = try c.decode(String.self,            forKey: .name)
        title        = try c.decode(ReservationTitle.self,  forKey: .title)
        phone        = try c.decode(String.self,            forKey: .phone)
        adults       = try c.decode(Int.self,               forKey: .adults)
        children     = try c.decode(Int.self,               forKey: .children)
        note         = try c.decode(String.self,            forKey: .note)
        status       = try c.decodeIfPresent(ReservationStatus.self,  forKey: .status)       ?? .pending
        preorderItems = try c.decodeIfPresent([PreorderItem].self,    forKey: .preorderItems) ?? []
    }
}

@MainActor
final class ReservationStore: ObservableObject {
    static let shared = ReservationStore()
    @Published var reservations: [Reservation] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let legacyKey = "pos.reservations"

    private init() {
        loadLegacy()
        Task { await refresh() }
    }

    // 從 GAS 重新抓取
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIClient.shared.fetchReservations()
            reservations = fetched.sorted { ($0.date + $0.time) < ($1.date + $1.time) }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ ReservationStore.refresh failed: \(error.localizedDescription)")
        }
    }

    // 新增：樂觀更新 + 背景同步
    func add(_ r: Reservation) {
        reservations.append(r)
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        Task { try? await APIClient.shared.createReservation(r) }
    }

    // 更新：樂觀更新 + 背景同步
    func update(_ r: Reservation) {
        guard let idx = reservations.firstIndex(where: { $0.id == r.id }) else { return }
        reservations[idx] = r
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        Task { try? await APIClient.shared.updateReservation(r) }
    }

    // 刪除：樂觀更新 + 背景同步
    func delete(id: UUID) {
        reservations.removeAll { $0.id == id }
        Task { try? await APIClient.shared.deleteReservation(id: id) }
    }

    // 首次啟動：把 UserDefaults 舊資料上傳到 GAS 後清除
    private func loadLegacy() {
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode([Reservation].self, from: data),
              !decoded.isEmpty
        else { return }

        reservations = decoded.sorted { ($0.date + $0.time) < ($1.date + $1.time) }

        // 上傳到 GAS，完成後清除 UserDefaults
        Task {
            for r in decoded {
                try? await APIClient.shared.createReservation(r)
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("✅ Legacy reservations migrated to GAS (\(decoded.count) items)")
        }
    }
}

// MARK: - 訂位黑名單（GAS 後台）

@MainActor
final class BlacklistStore: ObservableObject {
    static let shared = BlacklistStore()
    @Published var phones: Set<String> = []

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let fetched = try await APIClient.shared.fetchBlacklist()
            phones = Set(fetched)
        } catch {
            print("⚠️ BlacklistStore.refresh failed: \(error.localizedDescription)")
        }
    }

    func add(phone: String) {
        let p = phone.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        phones.insert(p)
        Task { try? await APIClient.shared.addToBlacklist(phone: p) }
    }

    func isBlacklisted(_ phone: String) -> Bool {
        let p = phone.trimmingCharacters(in: .whitespaces)
        return !p.isEmpty && phones.contains(p)
    }
}

// MARK: - 蛋糕取貨確認（本機）

final class CakePickupStore: ObservableObject {
    static let shared = CakePickupStore()
    @Published var confirmedIds: Set<String> = []

    private let key = "pos.cakePickups"

    private init() {
        confirmedIds = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func toggle(orderId: String) {
        if confirmedIds.contains(orderId) {
            confirmedIds.remove(orderId)
        } else {
            confirmedIds.insert(orderId)
        }
        UserDefaults.standard.set(Array(confirmedIds), forKey: key)
    }

    func isConfirmed(_ orderId: String) -> Bool {
        confirmedIds.contains(orderId)
    }
}
