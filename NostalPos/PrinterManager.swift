//
//  PrinterManager.swift
//  SimplePOS / NostalPos
//

import Foundation
import Network
import CoreFoundation

class PrinterManager {
    static let shared = PrinterManager()
    private init() {}

    // 你的出單機 IP / Port
    var printerIP: String = "192.168.0.11"
    var printerPort: UInt16 = 9100

    // Big5 編碼
    private let big5Encoding: String.Encoding = {
        let cfEnc = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        return String.Encoding(rawValue: nsEnc)
    }()

    // MARK: - ESC/POS 指令
    private let esc_init: [UInt8]   = [0x1B, 0x40]
    private let esc_center: [UInt8] = [0x1B, 0x61, 0x01]
    private let esc_left: [UInt8]   = [0x1B, 0x61, 0x00]
    private let esc_fontA: [UInt8]  = [0x1B, 0x4D, 0x00]
    private let esc_fontB: [UInt8]  = [0x1B, 0x4D, 0x01]   // 比較像黑體
    private let esc_big: [UInt8]    = [0x1D, 0x21, 0x11]   // 2 倍寬高
    private let esc_normal: [UInt8] = [0x1D, 0x21, 0x00]
    private let esc_cut: [UInt8]    = [0x1D, 0x56, 0x42, 0x00]
    private let esc_kickDrawer: [UInt8] = [0x1B, 0x70, 0x00, 0x19, 0xFA]   // 開前盤

    // MARK: - 舊版：用 OrderRequest 出單（保留給重印等情境）

    func printReceipt(for order: OrderRequest) {
        guard !printerIP.isEmpty else { return }

        let connection = NWConnection(
            host: NWEndpoint.Host(printerIP),
            port: NWEndpoint.Port(rawValue: printerPort)!,
            using: .tcp
        )
        connection.start(queue: .global())

        func send(_ bytes: [UInt8]) {
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }

        func sendText(_ text: String) {
            guard let data = text.data(using: big5Encoding) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        // ====== 開始列印 ======
        send(esc_init)
        send(esc_fontB)

        // 店名置中 + 放大
        send(esc_center)
        send(esc_big)
        sendText("眷鳥咖啡商行\n")
        send(esc_normal)
        send(esc_left)

        // 桌位 + 時間（同一行，桌位大字）
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeStr = formatter.string(from: Date())

        let tableName: String = {
            // 兼容你之前奇怪的 String?? 寫法
            if let t = (order.tableName as String??) ?? nil {
                if !t.isEmpty { return t }
            }
            return "外帶"
        }()

        send(esc_big)
        sendText("\(tableName)  \(timeStr)\n")
        send(esc_normal)
        sendText("--------------------------------\n")

        // 這個舊版就照原來一行印 name / qty / price
        for item in order.items {
            let line = "\(item.name)  x\(item.qty)  \(item.price * item.qty)"
            sendText(line + "\n")
        }

        sendText("--------------------------------\n")

        // 總計金額（放大）
        send(esc_big)
        sendText("總計：\(order.amount) 元\n")
        send(esc_normal)
        sendText("\n")

        // 已結帳（支付方式）在最下方
        let pay = order.payMethod.uppercased()
        sendText("已結帳（\(pay)）\n")
        sendText("\n\n")

        // 只有現金結帳才開前盤
        let isCash = pay.contains("CASH") || pay.contains("現金")
        if isCash {
            send(esc_kickDrawer)
        }

        // 切紙
        send(esc_cut)

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            connection.cancel()
        }
    }

    // MARK: - 新版：用 CartLine 出單（品項一行、大字；附加選項下一行、小字）

    func printReceiptForCart(
        cart: [CartLine],
        tableName: String,
        payMethod: String,
        amount: Int
    ) {
        guard !printerIP.isEmpty else { return }

        let connection = NWConnection(
            host: NWEndpoint.Host(printerIP),
            port: NWEndpoint.Port(rawValue: printerPort)!,
            using: .tcp
        )
        connection.start(queue: .global())

        func send(_ bytes: [UInt8]) {
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }

        func sendText(_ text: String) {
            guard let data = text.data(using: big5Encoding) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        // ====== 開始列印 ======
        send(esc_init)
        send(esc_fontB)

        // 店名置中 + 放大
        send(esc_center)
        send(esc_big)
        sendText("眷鳥咖啡商行\n")
        send(esc_normal)
        send(esc_left)

        // 桌位 + 時間（同一行，桌位大字）
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeStr = formatter.string(from: Date())

        let table = tableName.isEmpty ? "外帶" : tableName

        send(esc_big)
        sendText("\(table)  \(timeStr)\n")
        send(esc_normal)
        sendText("--------------------------------\n")

        // ====== 用 CartLine 印每一個品項 ======
        for line in cart {
            let baseName = line.item.name
            let qtyPrice = "x\(line.quantity)  \(line.lineTotal)"

            // 第一行：品項 + 數量 + 小計（大字）
            send(esc_big)
            sendText("\(baseName)  \(qtyPrice)\n")
            send(esc_normal)

            // 第二行：附加選項（小字，一行）
            var options: [String] = []

            // ✅ 溫度：只有不是 .none 才印，而且用 display（會是「熱 / 冰 / 一顆冰」）
            if line.temperature != .none {
                options.append(line.temperature.display)
            }

            // ✅ 甜度：有選才印（nil = 不選）
            if let s = line.sweetness {
                options.append(s.display)
            }
            if line.isOatMilk {
                options.append("燕麥奶")
            }
            if line.isRefill {
                options.append("續點")
            }
            if line.isEcoCup {
                options.append("環保杯")
            }

            if !options.isEmpty {
                let optionLine = "○ " + options.joined(separator: " / ")
                sendText("  \(optionLine)\n")
            }

            // 品項之間空一行
            sendText("\n")
        }

        sendText("--------------------------------\n")

        // 總計金額（放大）
        send(esc_big)
        sendText("總計：\(amount) 元\n")
        send(esc_normal)
        sendText("\n")

        // 已結帳（支付方式）在最下方
        let pay = payMethod.uppercased()
        sendText("已結帳（\(pay)）\n")
        sendText("\n\n")

        // 只有現金結帳才開前盤
        let isCash = pay.contains("CASH") || pay.contains("現金")
        if isCash {
            send(esc_kickDrawer)
        }

        // 切紙
        send(esc_cut)

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            connection.cancel()
        }
    }
    func printReprintReceipt(
        cart: [CartLine],
        tableName: String,
        payMethod: String?,
        amount: Int
    ) {
        guard !printerIP.isEmpty else { return }

        let connection = NWConnection(
            host: NWEndpoint.Host(printerIP),
            port: NWEndpoint.Port(rawValue: printerPort)!,
            using: .tcp
        )
        connection.start(queue: .global())

        func send(_ bytes: [UInt8]) {
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }

        func sendText(_ text: String) {
            guard let data = text.data(using: big5Encoding) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        send(esc_init)
        send(esc_fontB)

        send(esc_center)
        send(esc_big)
        sendText("眷鳥咖啡商行\n")
        send(esc_normal)
        send(esc_left)

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeStr = formatter.string(from: Date())

        let table = tableName.isEmpty ? "外帶" : tableName

        send(esc_big)
        sendText("\(table)  \(timeStr)\n")
        send(esc_normal)
        sendText("--------------------------------\n")

        for line in cart {
            let baseName = line.item.name
            let qtyPrice = "x\(line.quantity)  \(line.lineTotal)"

            send(esc_big)
            sendText("\(baseName)  \(qtyPrice)\n")
            send(esc_normal)

            var options: [String] = []
            if line.temperature != .none {
                options.append(line.temperature.display)
            }
            if let s = line.sweetness {
                options.append(s.display)
            }
            if line.isOatMilk {
                options.append("燕麥奶")
            }
            if line.isRefill {
                options.append("續點")
            }
            if line.isEcoCup {
                options.append("環保杯")
            }

            if !options.isEmpty {
                let optionLine = "○ " + options.joined(separator: " / ")
                sendText("  \(optionLine)\n")
            }

            sendText("\n")
        }

        sendText("--------------------------------\n")

        send(esc_big)
        sendText("總計：\(amount) 元\n")
        send(esc_normal)
        sendText("\n")

        let pay = (payMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if pay.isEmpty {
            sendText("未結帳（重印）\n")
        } else {
            sendText("已結帳（\(pay.uppercased())）\n")
        }
        sendText("\n\n")

        send(esc_cut)

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            connection.cancel()
        }
    }
}

