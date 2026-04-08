//
//  ReservationStore.swift
//  NostalPos
//

import Foundation

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

    init(id: UUID, date: String, time: String, name: String, title: ReservationTitle,
         phone: String, adults: Int, children: Int, note: String, status: ReservationStatus = .pending) {
        self.id = id; self.date = date; self.time = time; self.name = name
        self.title = title; self.phone = phone; self.adults = adults
        self.children = children; self.note = note; self.status = status
    }

    // 舊資料沒有 status 欄位時，預設 .pending
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,              forKey: .id)
        date     = try c.decode(String.self,            forKey: .date)
        time     = try c.decode(String.self,            forKey: .time)
        name     = try c.decode(String.self,            forKey: .name)
        title    = try c.decode(ReservationTitle.self,  forKey: .title)
        phone    = try c.decode(String.self,            forKey: .phone)
        adults   = try c.decode(Int.self,               forKey: .adults)
        children = try c.decode(Int.self,               forKey: .children)
        note     = try c.decode(String.self,            forKey: .note)
        status   = try c.decodeIfPresent(ReservationStatus.self, forKey: .status) ?? .pending
    }
}

final class ReservationStore: ObservableObject {
    static let shared = ReservationStore()
    @Published var reservations: [Reservation] = []

    private let key = "pos.reservations"

    private init() { load() }

    func add(_ r: Reservation) {
        reservations.append(r)
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        save()
    }

    func update(_ r: Reservation) {
        guard let idx = reservations.firstIndex(where: { $0.id == r.id }) else { return }
        reservations[idx] = r
        reservations.sort { ($0.date + $0.time) < ($1.date + $1.time) }
        save()
    }

    func delete(id: UUID) {
        reservations.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Reservation].self, from: data)
        else { return }
        reservations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reservations) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
