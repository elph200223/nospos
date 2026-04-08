//
//  OrderModels.swift
//  NostalPos
//

import Foundation

/// 後端用的訂單品項（給出單機 & API）
struct OrderItem: Identifiable, Codable {
    var id = UUID()
    var name: String       // 品名（含溫度/甜度/加購字串）
    var price: Int         // 單價
    var qty: Int           // 數量

    enum CodingKeys: String, CodingKey {
        case name, price, qty
    }
}

/// 後端用的整張訂單（PrinterManager、APIClient 都會用到）
struct OrderRequest: Codable {
    var orderId: String        // 自動產生的訂單編號（UUID）
    var amount: Int            // 總金額
    var items: [OrderItem]     // 品項列表
    var payMethod: String      // 支付方式（現金 / LINEPAY / TAPPAY）
    var note: String?          // 備註（這裡會塞「桌位：吧2」之類）
    var transactionId: String? // 第三方金流交易編號（目前可先為 nil）
    var tableName: String?     // 桌位名稱（方便後端記錄）
}

