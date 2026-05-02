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

    /// 正在等待伺服器回應的訂位 ID（refresh 時不蓋掉這些）
    private var pendingUpdateIds: Set<UUID> = []

    private let legacyKey = "pos.reservations"

    private init() {
        loadLegacy()
        Task { await refresh() }
    }

    // 從伺服器重新抓取（不蓋掉尚未同步完成的本機變更）
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIClient.shared.fetchReservations()
            // 若某筆訂位正在等待 PATCH 回應，保留本機版本，避免蓋掉樂觀更新
            let merged = fetched.map { serverR -> Reservation in
                if pendingUpdateIds.contains(serverR.id),
                   let localR = reservations.first(where: { $0.id == serverR.id }) {
                    return localR
                }
                return serverR
            }
            reservations = merged.sorted { ($0.date + $0.time) < ($1.date + $1.time) }
            lastError = nil
        } catch {
            guard !(error is CancellationError) else { return }
            lastError = error.localizedDescription
            print("⚠️ ReservationStore.refresh failed: \(error.localizedDescription)")
        }
    }

    // 新增：樂觀更新 + 背景同步（失敗時移除本機紀錄並顯示錯誤）
    func add(_ r: Reservation) {
        reservations.append(r)
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        Task {
            do {
                try await APIClient.shared.createReservation(r)
            } catch {
                // POST 失敗 → 移除本機的樂觀新增，否則這筆訂位永遠只存在本機
                reservations.removeAll { $0.id == r.id }
                lastError = "訂位新增失敗：\(error.localizedDescription)"
                print("⚠️ createReservation failed: \(error)")
            }
        }
    }

    // 更新：樂觀更新 + 背景同步（失敗時復原並顯示錯誤）
    func update(_ r: Reservation) {
        guard let idx = reservations.firstIndex(where: { $0.id == r.id }) else { return }
        let old = reservations[idx]
        reservations[idx] = r
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        pendingUpdateIds.insert(r.id)
        Task {
            defer { pendingUpdateIds.remove(r.id) }
            do {
                try await APIClient.shared.updateReservation(r)
            } catch {
                // API 失敗 → 復原本機狀態
                if let revertIdx = reservations.firstIndex(where: { $0.id == r.id }) {
                    reservations[revertIdx] = old
                    reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
                }
                lastError = "訂位更新失敗：\(error.localizedDescription)"
                print("⚠️ updateReservation failed: \(error)")
            }
        }
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
