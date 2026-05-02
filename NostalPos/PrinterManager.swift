//
//  PrinterManager.swift
//  SimplePOS / NostalPos
//

import Foundation
import Network
import CoreFoundation
import UIKit

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

    // MARK: - UIImage → ESC/POS GS v 0 點陣圖資料

    private func imageToRasterData(_ image: UIImage) -> Data {
        guard let cgImage = image.cgImage else { return Data() }

        let width        = cgImage.width
        let height       = cgImage.height
        let bytesPerLine = (width + 7) / 8     // 576px → 72 bytes/行

        // 把 UIImage 畫進 8-bit 灰階 bitmap（需翻轉 y 軸，因 CGContext 原點在左下）
        var pixels = [UInt8](repeating: 255, count: width * height)
        let graySpace = CGColorSpaceCreateDeviceGray()
        guard let bitmapCtx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: graySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }

        // UIGraphicsImageRenderer 輸出的 cgImage row-0 在頂部；
        // CoreGraphics 原點在左下，所以需翻轉才能讓 pixels[0] = 頂端第一列。
        bitmapCtx.translateBy(x: 0, y: CGFloat(height))
        bitmapCtx.scaleBy(x: 1.0, y: -1.0)
        bitmapCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 轉 1-bit（< 128 視為黑色 = bit 1）
        var bits = [UInt8](repeating: 0, count: bytesPerLine * height)
        for row in 0..<height {
            for col in 0..<width {
                if pixels[row * width + col] < 128 {
                    bits[row * bytesPerLine + col / 8] |= 0x80 >> (col % 8)
                }
            }
        }

        // 組裝 GS v 0 指令
        var data = Data()
        data.append(contentsOf: [0x1D, 0x76, 0x30, 0x00])           // GS v 0, normal
        data.append(UInt8( bytesPerLine       & 0xFF))               // xL
        data.append(UInt8((bytesPerLine >> 8) & 0xFF))               // xH
        data.append(UInt8( height             & 0xFF))               // yL
        data.append(UInt8((height      >> 8)  & 0xFF))               // yH
        data.append(contentsOf: bits)
        return data
    }

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

    // MARK: - 新版：用 CartLine 出單（圖片式排版）

    func printReceiptForCart(
        cart: [CartLine],
        tableName: String,
        payMethod: String,
        amount: Int
    ) {
        guard !printerIP.isEmpty else { return }

        let image = ReceiptRenderer.renderReceiptImage(
            cart: cart,
            tableName: tableName,
            payMethod: payMethod,
            amount: amount
        )
        let rasterData = imageToRasterData(image)

        let connection = NWConnection(
            host: NWEndpoint.Host(printerIP),
            port: NWEndpoint.Port(rawValue: printerPort)!,
            using: .tcp
        )
        connection.start(queue: .global())

        func send(_ bytes: [UInt8]) {
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }

        send(esc_init)
        connection.send(content: rasterData, completion: .contentProcessed { _ in })

        let pay = payMethod.uppercased()
        let isCash = pay.contains("CASH") || pay.contains("現金")
        if isCash {
            send(esc_kickDrawer)
        }

        send(esc_cut)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
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

        let image = ReceiptRenderer.renderReceiptImage(
            cart: cart,
            tableName: tableName,
            payMethod: payMethod,
            amount: amount
        )
        let rasterData = imageToRasterData(image)

        let connection = NWConnection(
            host: NWEndpoint.Host(printerIP),
            port: NWEndpoint.Port(rawValue: printerPort)!,
            using: .tcp
        )
        connection.start(queue: .global())

        func send(_ bytes: [UInt8]) {
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }

        send(esc_init)
        connection.send(content: rasterData, completion: .contentProcessed { _ in })
        send(esc_cut)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            connection.cancel()
        }
    }
}

