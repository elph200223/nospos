//
//  Models.swift
//  SimplePOS
//

import Foundation

// MARK: - 後端回傳整體結構 ------------------------------

struct MenuResponse: Codable {
    let categories: [Category]
    let items: [MenuItem]
    let categoryAddOns: [CategoryAddOn]
}

// MARK: - Category / Item / AddOn -----------------------

struct Category: Identifiable, Codable, Hashable {
    let categoryId: String
    let name: String
    let sortOrder: Int?

    var id: String { categoryId }
}

struct MenuItem: Identifiable, Codable, Hashable {
    let itemId: String
    let categoryId: String
    let name: String
    let price: Int
    let allowOat: Bool
    let addOns: [ItemAddOn]?

    var id: String { itemId }
}

struct CategoryAddOn: Identifiable, Codable, Hashable {
    let addOnId: String
    let categoryId: String
    let name: String
    let price: Int

    var id: String { addOnId }
}

// MARK: - Options / AddOns（從後端 OptionsJSON / AddOnsJSON 解析後得到）

struct OptionGroup: Codable, Hashable {
    let name: String
    let values: [String]
    let optional: Bool?

    init(name: String, values: [String], optional: Bool? = nil) {
        self.name = name
        self.values = values
        self.optional = optional
    }
}

struct ItemAddOn: Identifiable, Codable, Hashable {
    let name: String
    let price: Int

    var id: String { name }
}

// MARK: - 前端用的選項 Enum -----------------------------
enum Temperature: String, CaseIterable, Codable, Equatable {
    case none = "不選"   // ⭐ 新增「不選」
    case hot = "熱"
    case iced = "冰"
    case oneIce = "一顆冰"

    var display: String { rawValue }
}


enum Sweetness: String, CaseIterable, Codable {
    case none = "無糖"
    case sweet = "有糖"

    var display: String { rawValue }
}

// MARK: - 購物車 / 訂單行 ------------------------------

struct CartLine: Identifiable, Hashable {
    let id = UUID()
    let item: MenuItem
    var quantity: Int
    
    var temperature: Temperature
    var sweetness: Sweetness?
    var isOatMilk: Bool
    var isRefill: Bool
    var isEcoCup: Bool
    var isTakeawayAfterMeal: Bool
    var needsCutlery: Bool
    
    // 單杯價格計算（不含其他附加 AddOnsJSON，之後要可以再加）
    var unitPrice: Int {
        var p = item.price
        if isRefill { p -= 20 }
        if isEcoCup { p -= 5 }
        if isOatMilk { p += 20 }
        return max(p, 0)
    }
    
    var lineTotal: Int {
        unitPrice * quantity
    }
    
    var displayName: String {
        var parts: [String] = [item.name]
        
        // ⭐ 溫度是 .none（不選）就不要顯示
        if temperature != .none {
            parts.append(temperature.display)
        }
        
        if let s = sweetness {
            parts.append(s.display)
        }
        
        if isOatMilk {
            parts.append("燕麥奶(+20)")
        }
        if isRefill {
            parts.append("續點(-20)")
        }
        if isEcoCup {
            parts.append("環保杯(-5)")
        }
        if isTakeawayAfterMeal {
            parts.append("餐後外帶")
        }
        if needsCutlery {
            parts.append("要餐具")
        }
        
        return parts.joined(separator: " / ")
    }
    var detailDescription: String? {
        var parts: [String] = []

        // 溫度（如果你不想顯示 .none，可照 displayName 的規則）
        if temperature != .none {
            parts.append(temperature.display)
        }

        // 甜度
        if let s = sweetness {
            parts.append(s.display)
        }

        // 其他旗標
        if isOatMilk { parts.append("燕麥") }
        if isRefill { parts.append("續杯") }
        if isEcoCup { parts.append("環保杯") }
        if isTakeawayAfterMeal { parts.append("餐後外帶") }
        if needsCutlery { parts.append("要餐具") }

        let text = parts.joined(separator: " / ")
        return text.isEmpty ? nil : text
    }

}


// 用來記錄「清桌前」的備份：有哪些品項、計時器從什麼時候開始
struct CartBackup {
    var lines: [CartLine]
    var startTime: Date?
}
