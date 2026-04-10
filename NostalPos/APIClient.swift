//
//  APIClient.swift
//  SimplePOS / NostalPos
//

import Foundation

// MARK: - Line Pay Offline 回傳資料結構

struct LinePayOfflinePayInfo: Codable {
    let transactionId: Int64?
    let orderId: String?
    let transactionDate: String?
    let payInfo: [LinePayPayInfo]?
}

struct LinePayPayInfo: Codable {
    let method: String?
    let amount: Int?
}

struct LinePayCreateOrderResultLite: Codable {
    let ok: Bool?
    let orderId: String?
    let createdAt: String?
    let error: String?
}

struct LinePayOfflinePayResponse: Codable {
    let ok: Bool?
    let httpStatus: Int?
    let returnCode: String?
    let returnMessage: String?
    let info: LinePayOfflinePayInfo?
    let orderResult: LinePayCreateOrderResultLite?
    let error: String?
}

// MARK: - 共用回應（寬鬆）

struct GenericOKResponse: Decodable {
    let ok: Bool?
    let error: String?
    let message: String?
}

// MARK: - Shift / 關帳 DTO

struct LiveBusinessSummaryResponse: Decodable {
    let ok: Bool?
    let date: String
    let liveTotalAmount: Int
    let paidTotalAmount: Int
    let pendingTotalAmount: Int
    let totalCash: Int
    let totalCard: Int
    let totalLinePay: Int
    let totalTapPay: Int
    let paidOrderCount: Int
    let pendingOrderCount: Int
    let error: String?
    let message: String?
}

struct CloseShiftSummaryResponse: Decodable {
    let ok: Bool?
    let date: String
    let closeableTotalAmount: Int
    let totalCash: Int
    let totalCard: Int
    let totalLinePay: Int
    let totalTapPay: Int
    let orderCount: Int
    let error: String?
    let message: String?
}

struct CloseShiftResultResponse: Decodable {
    let ok: Bool?
    let date: String
    let closeableTotalAmount: Int
    let totalCash: Int
    let totalCard: Int
    let totalLinePay: Int
    let totalTapPay: Int
    let orderCount: Int
    let closedRows: Int?
    let error: String?
    let message: String?
}

struct ArchiveMonthResponse: Decodable {
    let ok: Bool?
    let month: String?
    let archivedRows: Int?
    let deletedRows: Int?
    let archiveSheetName: String?
    let error: String?
    let message: String?
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private var cachedMenu: MenuResponse?

    // ⚠️ 這裡填你的 GAS Web App URL（不要帶 ?action）
    private let baseURLString =
    "https://script.google.com/macros/s/AKfycbxKvvyOh3V31Gf_-EsyE1rWcPNwmLXl1MZ3YnihCYpBcON4gVD4aQGgkl3c4Kouow3PNw/exec"

    fileprivate var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("請先在 APIClient 裡設定正確的 Web App URL")
        }
        return url
    }

    // 共用 Encoder / Decoder
    fileprivate let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    fileprivate let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - 共用：POST JSON 到 GAS（body 自己含 action）(async/await)

    fileprivate func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        _ body: RequestBody,
        as type: ResponseBody.Type,
        timeout: TimeInterval = 40
    ) async throws -> ResponseBody {

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "APIClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP Status \(http.statusCode)"]
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw NSError(
                domain: "APIClient",
                code: -999,
                userInfo: [NSLocalizedDescriptionKey: "Decode 失敗：\(error.localizedDescription)\nRaw：\(raw)"]
            )
        }
    }

    // MARK: - 共用：POST JSON 到 GAS（寬鬆 JSONSerialization）

    fileprivate func postJSONLoose(_ payload: Data, timeout: TimeInterval = 25) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "APIClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP Status \(http.statusCode)"]
            )
        }

        if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
           let json = obj as? [String: Any] {
            return json
        }

        let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        throw NSError(
            domain: "APIClient",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "後端回傳非 JSON：\(raw)"]
        )
    }

    // MARK: - 共用：GET JSON（Decodable）

    fileprivate func getJSON<ResponseBody: Decodable>(
        action: String,
        timeout: TimeInterval = 15,
        as type: ResponseBody.Type
    ) async throws -> ResponseBody {

        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "action", value: action)
        ]

        guard let url = comps?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "APIClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP Status \(http.statusCode)"]
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw NSError(
                domain: "APIClient",
                code: -998,
                userInfo: [NSLocalizedDescriptionKey: "Decode 失敗：\(error.localizedDescription)\nRaw：\(raw)"]
            )
        }
    }

    // MARK: - 取得菜單（GET getMenu，有快取）

    func fetchMenu(forceRefresh: Bool = false) async throws -> MenuResponse {
        if !forceRefresh, let cached = cachedMenu { return cached }
        let result = try await getJSON(action: "getMenu", timeout: 15, as: MenuResponse.self)
        cachedMenu = result
        return result
    }

    // MARK: - Line Pay Offline：掃碼付款

    struct LinePayOfflinePayRequestBody: Encodable {
        let action = "linePayOfflinePay"
        let order: OrderRequest
        let oneTimeKey: String
    }

    func linePayOfflinePay(order: OrderRequest, oneTimeKey: String) async throws -> LinePayOfflinePayResponse {
        let body = LinePayOfflinePayRequestBody(order: order, oneTimeKey: oneTimeKey)
        return try await postJSON(body, as: LinePayOfflinePayResponse.self, timeout: 40)
    }
}

// MARK: - 建立訂單（寫入 Google Sheet）(callback 版保留)

extension APIClient {

    func createOrder(_ order: OrderRequest,
                     completion: @escaping (Result<String, Error>) -> Void) {

        struct Payload: Encodable {
            let action = "createOrder"
            let order: OrderRequest
        }

        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        do {
            let body = try encoder.encode(Payload(order: order))
            req.httpBody = body
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                completion(.failure(err))
                return
            }

            guard let data = data else {
                let e = NSError(
                    domain: "APIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "空回應"]
                )
                completion(.failure(e))
                return
            }

            if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
               let json = obj as? [String: Any] {

                let ok = (json["ok"] as? Bool) ?? true
                if !ok {
                    let msg = (json["error"] as? String)
                    ?? (json["message"] as? String)
                    ?? "後端回傳錯誤"
                    let e = NSError(
                        domain: "APIClient",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )
                    completion(.failure(e))
                    return
                }

                let oid = (json["orderId"] as? String)
                ?? (json["id"] as? String)
                ?? (json["order_id"] as? String)
                ?? order.orderId

                completion(.success(oid))
                return
            }

            let text = String(data: data, encoding: .utf8) ?? "非 UTF8 回應"
            let e = NSError(
                domain: "APIClient",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "createOrder 回傳非 JSON：\(text)"]
            )
            completion(.failure(e))
        }.resume()
    }

    func createOrderAsync(_ order: OrderRequest) async throws -> String {
        struct Payload: Encodable {
            let action = "createOrder"
            let order: OrderRequest
        }

        let payload = try encoder.encode(Payload(order: order))
        let json = try await postJSONLoose(payload, timeout: 25)

        let ok = (json["ok"] as? Bool) ?? true
        if !ok {
            let msg = (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? "後端回傳錯誤"
            throw NSError(domain: "APIClient", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let oid = (json["orderId"] as? String)
        ?? (json["id"] as? String)
        ?? (json["order_id"] as? String)
        ?? order.orderId

        return oid
    }
}

// MARK: - 刪單 / Void

extension APIClient {

    func voidOrder(orderId: String) async throws -> GenericOKResponse {
        try await deleteOrderAsync(orderId: orderId)
        return GenericOKResponse(ok: true, error: nil, message: nil)
    }
}

// MARK: - PENDING 保命線：刪單 / 更新狀態 / 改內容 / 落帳 / 重印

extension APIClient {

    struct DeleteOrderRequestBody: Encodable {
        let action = "deleteOrder"
        let orderId: String
    }

    struct ReprintOrderRequestBody: Encodable {
        let action = "reprintOrder"
        let orderId: String
    }

    struct UpdateOrderStatusRequestBody: Encodable {
        let action = "updateOrderStatus"
        let orderId: String
        let status: String
        let payMethod: String
        let linePayTransactionId: String?

        init(orderId: String, status: String, payMethod: String, linePayTransactionId: String? = nil) {
            self.orderId = orderId
            self.status = status
            self.payMethod = payMethod
            self.linePayTransactionId = linePayTransactionId
        }
    }

    struct UpdateOrderLinePayload: Encodable {
        let name: String
        let price: Int
        let qty: Int
    }

    struct UpdateOrderRequestBody: Encodable {
        let action = "updateOrder"
        let orderId: String
        let items: [UpdateOrderLinePayload]
        let amount: Int
        let note: String
    }

    struct UpdateOrderPaymentStatusRequestBody: Encodable {
        let action = "updateOrderPaymentStatus"
        let orderId: String
        let status: String
        let payMethod: String
        let linePayTransactionId: String?
    }

    func deleteOrderAsync(orderId: String) async throws {
        let body = DeleteOrderRequestBody(orderId: orderId)
        let payload = try encoder.encode(body)
        let json = try await postJSONLoose(payload, timeout: 20)

        let ok = (json["ok"] as? Bool) ?? false
        if !ok {
          let msg = (json["error"] as? String)
          ?? (json["message"] as? String)
          ?? "deleteOrder 失敗"
          throw NSError(domain: "APIClient", code: -30, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func reprintOrderAsync(orderId: String) async throws {
        let body = ReprintOrderRequestBody(orderId: orderId)
        let payload = try encoder.encode(body)
        let json = try await postJSONLoose(payload, timeout: 20)

        let ok = (json["ok"] as? Bool) ?? true
        if !ok {
            let msg = (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? "reprintOrder 失敗"
            throw NSError(domain: "APIClient", code: -33, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// 一般狀態更新。
    /// 注意：真正付款請優先走 updateOrderPaymentStatusAsync，避免 PAID / payMethod 語意分散。
    func updateOrderStatusAsync(
        orderId: String,
        status: String,
        payMethod: String,
        linePayTransactionId: String? = nil
    ) async throws {
        let body = UpdateOrderStatusRequestBody(
            orderId: orderId,
            status: status,
            payMethod: payMethod,
            linePayTransactionId: linePayTransactionId
        )

        let payload = try encoder.encode(body)
        let json = try await postJSONLoose(payload, timeout: 20)

        let ok = (json["ok"] as? Bool) ?? false
        if !ok {
            let msg = (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? "updateOrderStatus 失敗"
            throw NSError(domain: "APIClient", code: -31, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// 改單內容：只更新同一張單，不重建。
    /// 用於先點後結的 pending 單改品項 / 改數量 / 改備註。
    func updateOrderAsync(
        orderId: String,
        items: [CartLine],
        amount: Int,
        note: String
    ) async throws {
        let itemPayloads = items.map { line in
            let qty = max(line.quantity, 1)
            let unitPrice = qty > 0 ? (line.lineTotal / qty) : line.lineTotal

            return UpdateOrderLinePayload(
                name: line.displayName,
                price: unitPrice,
                qty: qty
            )
        }

        let body = UpdateOrderRequestBody(
            orderId: orderId,
            items: itemPayloads,
            amount: amount,
            note: note
        )

        let payload = try encoder.encode(body)
        let json = try await postJSONLoose(payload, timeout: 20)

        let ok = (json["ok"] as? Bool) ?? false
        if !ok {
            let msg = (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? "updateOrder 失敗"
            throw NSError(domain: "APIClient", code: -32, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// 真正付款用：把同一張 pending 單轉成 paid。
    func updateOrderPaymentStatusAsync(
        orderId: String,
        payMethod: String,
        linePayTransactionId: String? = nil
    ) async throws {
        let body = UpdateOrderPaymentStatusRequestBody(
            orderId: orderId,
            status: "PAID",
            payMethod: payMethod,
            linePayTransactionId: linePayTransactionId
        )

        let payload = try encoder.encode(body)
        let json = try await postJSONLoose(payload, timeout: 20)

        let ok = (json["ok"] as? Bool) ?? false
        if !ok {
            let msg =
              (json["error"] as? String)
           ?? (json["message"] as? String)
           ?? "updateOrderPaymentStatus 失敗"
            throw NSError(
                domain: "APIClient",
                code: -41,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    /// 保留舊方法以免其他檔案還在呼叫。
    /// 新流程不建議再用「刪掉 pending、重建 paid」。
    func finalizePendingByRecreatePaidAsync(
        pendingOrderId: String,
        paidOrder: OrderRequest
    ) async throws -> String {
        let newPaidId = try await createOrderAsync(paidOrder)
        try await deleteOrderAsync(orderId: pendingOrderId)
        return newPaidId
    }
}

extension APIClient {
    struct PayOrderResponse: Codable {
        var ok: Bool
        var message: String?
    }

    func payOrder(orderId: String, payMethod: String, completion: @escaping (Result<PayOrderResponse, Error>) -> Void) {
        // 保留空殼；目前正式流程請改走 updateOrderPaymentStatusAsync
    }
}

// MARK: - Move Table（搬桌）

extension APIClient {

    struct MoveTableRequestBody: Encodable {
        let action = "moveTable"
        let sourceTableName: String
        let targetTableName: String
    }

    struct MoveTableResponse: Codable {
        let ok: Bool?
        let sourceTableName: String?
        let targetTableName: String?
        let updated: Int?
        let movedOrderIds: [String]?
        let error: String?
        let rawText: String?

        init(ok: Bool?, source: String?, target: String?, updated: Int?, ids: [String]?, error: String?, rawText: String?) {
            self.ok = ok
            self.sourceTableName = source
            self.targetTableName = target
            self.updated = updated
            self.movedOrderIds = ids
            self.error = error
            self.rawText = rawText
        }
    }

    func moveTable(source: String, target: String) async throws -> MoveTableResponse {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        let body = MoveTableRequestBody(sourceTableName: source, targetTableName: target)
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "APIClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP Status \(http.statusCode)"]
            )
        }

        let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"

        if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
           let json = obj as? [String: Any] {

            let ok = json["ok"] as? Bool
            let source = json["sourceTableName"] as? String
            let target = json["targetTableName"] as? String
            let updated = json["updated"] as? Int
            let ids = json["movedOrderIds"] as? [String]
            let error = json["error"] as? String

            return MoveTableResponse(
                ok: ok,
                source: source,
                target: target,
                updated: updated,
                ids: ids,
                error: error,
                rawText: raw
            )
        }

        return MoveTableResponse(
            ok: false,
            source: nil,
            target: nil,
            updated: nil,
            ids: nil,
            error: "moveTable 回傳非 JSON",
            rawText: raw
        )
    }
}

// MARK: - 今日訂單（給 TodayOrdersView / POSViewModel 用）

extension APIClient {

    func fetchTodayOrders() async throws -> [TodayOrderDTO] {
        struct TodayOrdersResponse: Decodable {
            let ok: Bool?
            let orders: [TodayOrderDTO]
        }

        let wrapper = try await getJSON(
            action: "getTodayOrders",
            timeout: 15,
            as: TodayOrdersResponse.self
        )
        return wrapper.orders
    }
}

// MARK: - Shift / 關帳

extension APIClient {

    struct CloseShiftRequestBody: Encodable {
        let action = "closeShift"
        let date: String?

        init(date: String? = nil) {
            self.date = date
        }
    }

    /// 營業中即時總覽：應包含 PAID + PENDING
    func fetchLiveBusinessSummary() async throws -> LiveBusinessSummaryResponse {
        try await getJSON(
            action: "getLiveBusinessSummary",
            timeout: 15,
            as: LiveBusinessSummaryResponse.self
        )
    }

    /// 正式關帳預覽：只算可關帳的 PAID
    func fetchCloseShiftSummary() async throws -> CloseShiftSummaryResponse {
        try await getJSON(
            action: "getCloseShiftSummary",
            timeout: 15,
            as: CloseShiftSummaryResponse.self
        )
    }

    /// 真正執行關帳
    func closeShift(date: String? = nil) async throws -> CloseShiftResultResponse {
        let body = CloseShiftRequestBody(date: date)
        return try await postJSON(body, as: CloseShiftResultResponse.self, timeout: 40)
    }

    struct ArchiveMonthRequestBody: Encodable {
        let action = "archiveCurrentMonth"
        let month: String?

        init(month: String? = nil) {
            self.month = month
        }
    }

    /// 手動封存指定月份已關帳訂單（預設當月）
    func archiveCurrentMonth(month: String? = nil) async throws -> ArchiveMonthResponse {
        let body = ArchiveMonthRequestBody(month: month)
        return try await postJSON(body, as: ArchiveMonthResponse.self, timeout: 180)
    }
}

// MARK: - 訂位 API

extension APIClient {

    struct ReservationPayload: Encodable {
        let id: String
        let date: String
        let time: String
        let name: String
        let title: String
        let phone: String
        let adults: Int
        let children: Int
        let note: String
        let status: String
        let preorderJSON: String

        init(from r: Reservation) {
            id       = r.id.uuidString
            date     = r.date
            time     = r.time
            name     = r.name
            title    = r.title.rawValue
            phone    = r.phone
            adults   = r.adults
            children = r.children
            note     = r.note
            status   = r.status.rawValue
            preorderJSON = (try? String(data: JSONEncoder().encode(r.preorderItems), encoding: .utf8)) ?? "[]"
        }
    }

    struct ReservationStatusPayload: Encodable {
        let id: String
        let status: String
    }

    private struct CreateReservationBody: Encodable {
        let action = "createReservation"
        let reservation: ReservationPayload
    }

    private struct UpdateReservationBody: Encodable {
        let action = "updateReservation"
        let reservation: ReservationPayload
    }

    private struct UpdateReservationStatusBody: Encodable {
        let action = "updateReservation"
        let reservation: ReservationStatusPayload
    }

    private struct DeleteReservationBody: Encodable {
        let action = "deleteReservation"
        let id: String
    }

    private struct ReservationsResponse: Decodable {
        let ok: Bool?
        let reservations: [ReservationItem]?

        struct ReservationItem: Decodable {
            let id: String
            let date: String
            let time: String
            let name: String
            let title: String
            let phone: String
            let adults: Int
            let children: Int
            let note: String
            let status: String
            let preorderJSON: String?

            func toReservation() -> Reservation? {
                guard let uuid = UUID(uuidString: id) else { return nil }
                let t: ReservationTitle
                switch title {
                case "先生": t = .mr
                case "小姐": t = .ms
                default:    t = .none
                }
                let s: ReservationStatus
                switch status {
                case "arrived": s = .arrived
                case "noShow":  s = .noShow
                default:        s = .pending
                }
                var preorder: [PreorderItem] = []
                if let json = preorderJSON, let data = json.data(using: .utf8) {
                    preorder = (try? JSONDecoder().decode([PreorderItem].self, from: data)) ?? []
                }
                return Reservation(id: uuid, date: date, time: time, name: name,
                                   title: t, phone: phone, adults: adults,
                                   children: children, note: note, status: s,
                                   preorderItems: preorder)
            }
        }
    }

    func fetchReservations() async throws -> [Reservation] {
        let response = try await getJSON(action: "getReservations", timeout: 20, as: ReservationsResponse.self)
        return (response.reservations ?? []).compactMap { $0.toReservation() }
    }

    func createReservation(_ r: Reservation) async throws {
        let body = CreateReservationBody(reservation: ReservationPayload(from: r))
        let _: GenericOKResponse = try await postJSON(body, as: GenericOKResponse.self, timeout: 20)
    }

    func updateReservation(_ r: Reservation) async throws {
        let body = UpdateReservationBody(reservation: ReservationPayload(from: r))
        let _: GenericOKResponse = try await postJSON(body, as: GenericOKResponse.self, timeout: 20)
    }

    func deleteReservation(id: UUID) async throws {
        let body = DeleteReservationBody(id: id.uuidString)
        let _: GenericOKResponse = try await postJSON(body, as: GenericOKResponse.self, timeout: 20)
    }

    // MARK: - Blacklist

    private struct BlacklistResponse: Decodable {
        let ok: Bool?
        let phones: [String]?
    }

    private struct AddBlacklistBody: Encodable {
        let action = "addToBlacklist"
        let phone: String
    }

    func fetchBlacklist() async throws -> [String] {
        let response = try await getJSON(action: "getBlacklist", timeout: 15, as: BlacklistResponse.self)
        return response.phones ?? []
    }

    func addToBlacklist(phone: String) async throws {
        let body = AddBlacklistBody(phone: phone)
        let _: GenericOKResponse = try await postJSON(body, as: GenericOKResponse.self, timeout: 15)
    }
}
