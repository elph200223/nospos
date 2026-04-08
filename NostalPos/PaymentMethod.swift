//
//  PaymentMethod.swift
//  NostalPos
//

import Foundation

/// 結帳支付方式
enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case cash    = "CASH"
    case linePay = "LINEPAY"
    case tapPay  = "TAPPAY"

    var id: String { rawValue }

    /// 給畫面顯示用的名稱
    var displayName: String {
        switch self {
        case .cash:    return "現金"
        case .linePay: return "LINE Pay"
        case .tapPay:  return "TapPay"
        }
    }
}

