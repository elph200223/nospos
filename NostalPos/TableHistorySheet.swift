//
//  TableHistorySheet.swift
//  NostalPos
//

import SwiftUI

// MARK: - 後端 DTO（本地用結構，不再靠 Codable 解 JSON）

struct TableHistoryItem: Identifiable {
    var id = UUID()
    let name: String
    let price: Int
    let qty: Int
}

struct TableHistoryOrder: Identifiable {
    let orderId: String
    let createdAt: String
    let tableName: String
    let payMethod: String
    let amount: Int
    let note: String
    let status: String
    let items: [TableHistoryItem]

    var id: String { orderId }
}

// MARK: - ViewModel

@MainActor
final class TableHistoryViewModel: ObservableObject {
    let tableName: String

    @Published var orders: [TableHistoryOrder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // ⚠️ 一定要跟 APIClient 裡的 baseURLString 同一個 URL
    private let posBackendURL = URL(string: "https://script.google.com/macros/s/AKfycbxKvvyOh3V31Gf_-EsyE1rWcPNwmLXl1MZ3YnihCYpBcON4gVD4aQGgkl3c4Kouow3PNw/exec")!

    init(tableName: String) {
        self.tableName = tableName
    }

    // 小工具：從 Any 轉 String / Int，比較不容易壞
    private func asString(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let d = any { return String(describing: d) }
        return ""
    }

    private func asInt(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String, let v = Int(s) { return v }
        return 0
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            var comps = URLComponents(url: posBackendURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "action", value: "getTodayOrders")
            ]
            guard let url = comps.url else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            // 方便之後除錯用
            if let raw = String(data: data, encoding: .utf8) {
                print("🔍 TableHistory raw response =\n\(raw)")
            }

            // 不用 Decodable，改用 JSONSerialization，避免「missing」錯誤
            guard
                let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            else {
                throw NSError(
                    domain: "TableHistory",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "後端回傳格式不是 JSON 物件"]
                )
            }

            // 如果後端是錯誤訊息（沒有 orders）
            if let err = root["error"] as? String {
                throw NSError(
                    domain: "TableHistory",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "後端錯誤：\(err)"]
                )
            }

            guard let ordersArray = root["orders"] as? [[String: Any]] else {
                throw NSError(
                    domain: "TableHistory",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "後端沒有回傳 orders 欄位"]
                )
            }

            var result: [TableHistoryOrder] = []

            for obj in ordersArray {
                let orderTableName = asString(obj["tableName"])
                // 只保留指定桌位
                if orderTableName != tableName { continue }

                let orderId    = asString(obj["orderId"])
                let createdAt  = asString(obj["createdAt"])
                let payMethod  = asString(obj["payMethod"])
                let amount     = asInt(obj["amount"])
                let note       = asString(obj["note"])
                let status     = asString(obj["status"])

                var items: [TableHistoryItem] = []
                if let arr = obj["items"] as? [[String: Any]] {
                    for it in arr {
                        let name  = asString(it["name"])
                        let price = asInt(it["price"])
                        let qty   = asInt(it["qty"])
                        if name.isEmpty { continue }
                        items.append(TableHistoryItem(name: name, price: price, qty: qty))
                    }
                }

                let order = TableHistoryOrder(
                    orderId: orderId,
                    createdAt: createdAt,
                    tableName: orderTableName,
                    payMethod: payMethod,
                    amount: amount,
                    note: note,
                    status: status,
                    items: items
                )
                result.append(order)
            }

            // 新的在上面
            result.sort { $0.createdAt > $1.createdAt }

            self.orders = result
        } catch {
            self.errorMessage = "讀取訂單紀錄失敗：\(error.localizedDescription)"
        }

        isLoading = false
    }

    func payMethodDisplay(_ method: String) -> String {
        let upper = method.uppercased()
        switch upper {
        case "CASH": return "現金"
        case "LINEPAY": return "LINE Pay"
        case "TAPPAY", "CARD": return "TapPay / 卡"
        default: return method
        }
    }

    func statusDisplay(_ status: String) -> String {
        let upper = status.uppercased()
        switch upper {
        case "PAID": return "已付款"
        case "PENDING": return "未付款"
        case "CLOSED": return "已關帳"
        default: return status
        }
    }
}

// MARK: - View

struct TableHistorySheet: View {
    let tableName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TableHistoryViewModel

    init(tableName: String) {
        self.tableName = tableName
        _vm = StateObject(wrappedValue: TableHistoryViewModel(tableName: tableName))
    }

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading {
                    VStack {
                        ProgressView()
                        Text("讀取 \(tableName) 的訂單紀錄中…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)

                        Button("重新整理") {
                            Task { await vm.load() }
                        }
                    }
                    .padding()
                } else if vm.orders.isEmpty {
                    Text("今天目前沒有「\(tableName)」的訂單紀錄。")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(vm.orders) { order in
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(order.createdAt)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(vm.payMethodDisplay(order.payMethod))
                                            .font(.subheadline)
                                        Text(vm.statusDisplay(order.status))
                                            .font(.subheadline)
                                            .foregroundColor(order.status.uppercased() == "PAID" ? .green : .orange)
                                    }

                                    HStack {
                                        Text("金額：")
                                        Spacer()
                                        Text("\(order.amount) 元")
                                            .bold()
                                    }
                                    .font(.subheadline)

                                    if !order.note.isEmpty {
                                        Text("備註：\(order.note)")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }

                                    if !order.items.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(order.items) { item in
                                                HStack {
                                                    Text(item.name)
                                                    Spacer()
                                                    Text("x\(item.qty)")
                                                    Text("\(item.price)")
                                                }
                                                .font(.footnote)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("桌位：\(tableName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                }
            }
            .task {
                await vm.load()
            }
        }
    }
}
