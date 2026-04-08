//
//  CakeOrderService.swift
//  NostalPos
//

import Foundation

struct CakeOrder: Identifiable, Codable {
    let id: Int
    let orderNo: String
    let customer: String
    let phone: String
    let pickupDate: String   // "2026-04-07"
    let pickupTime: String
    let note: String
    let totalAmount: Int
    let items: [CakeOrderItem]
}

struct CakeOrderItem: Codable {
    let name: String
    let price: Int
    let quantity: Int
}

private struct POSOrdersResponse: Codable {
    let ok: Bool
    let orders: [CakeOrder]?
    let error: String?
}

final class CakeOrderService {
    static let shared = CakeOrderService()
    private init() {}

    private let baseURL = "https://www.nostalgiacoffeeroastery.com/api/pos/orders"
    private let apiKey  = "nospos2026"

    func fetchOrders(from: Date, to: Date) async throws -> [CakeOrder] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let fromStr = fmt.string(from: from)
        let toStr   = fmt.string(from: to)

        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "from", value: fromStr),
            URLQueryItem(name: "to",   value: toStr),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(POSOrdersResponse.self, from: data)

        guard resp.ok, let orders = resp.orders else {
            throw NSError(
                domain: "CakeOrderService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: resp.error ?? "unknown error"]
            )
        }
        return orders
    }
}
