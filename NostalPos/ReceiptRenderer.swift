//
//  ReceiptRenderer.swift
//  NostalPos
//
//  把收據畫成 UIImage（白底黑字），供 PrinterManager 轉成 ESC/POS 點陣圖送印。
//  排版：店名置中 → 桌號/時間 → 分隔線 → 品項（各選項獨立圓角框）→ 分隔線 → 總計 → 結帳方式
//

import UIKit
import SwiftUI

struct ReceiptRenderer {

    // MARK: - Layout

    static let paperWidth:  CGFloat = 576   // 80mm × 8 dots/mm（可視印表機型號微調）
    static let margin:      CGFloat = 28    // 左右邊界，content 寬 = 520

    // Pill（選項框）
    private static let pillPadH:   CGFloat = 10
    private static let pillPadV:   CGFloat = 5
    private static let pillGap:    CGFloat = 7
    private static let pillCorner: CGFloat = 9
    private static let pillStroke: CGFloat = 1.2

    // MARK: - Fonts（.rounded design → 圓黑體感）

    static let shopFont  = roundedFont(size: 20, weight: .medium)
    static let tableFont = roundedFont(size: 36, weight: .bold)
    static let itemFont  = roundedFont(size: 28, weight: .bold)
    static let optFont   = roundedFont(size: 22, weight: .medium)
    static let totalFont = roundedFont(size: 34, weight: .bold)
    static let payFont   = roundedFont(size: 16)

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: desc, size: size)
        }
        return base
    }

    // MARK: - Public entry point

    static func renderReceiptImage(
        cart: [CartLine],
        tableName: String,
        payMethod: String?,
        amount: Int
    ) -> UIImage {
        let totalH = measureHeight(cart: cart)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: paperWidth, height: totalH),
            format: format
        )

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: paperWidth, height: totalH))
            drawContent(
                cart: cart,
                tableName: tableName,
                payMethod: payMethod,
                amount: amount,
                ctx: ctx.cgContext
            )
        }
    }

    // MARK: - Height measurement

    private static func measureHeight(cart: [CartLine]) -> CGFloat {
        var y: CGFloat = 20                          // top padding
        y += shopFont.lineHeight + 16                // shop name + space
        y += tableFont.lineHeight + 10               // table + time
        y += 12                                      // after first divider
        for line in cart {
            y += cartLineHeight(line)
        }
        y += 12                                      // after second divider
        y += totalFont.lineHeight + 8                // total row
        y += payFont.lineHeight + 28                 // pay method + bottom pad
        return ceil(y) + 20                          // +20 safety buffer
    }

    private static func cartLineHeight(_ line: CartLine) -> CGFloat {
        let boxH = itemFont.lineHeight + pillPadV * 2
        let tokens = optionTokens(line)
        if tokens.isEmpty {
            return boxH + 18
        }
        let text  = tokens.joined(separator: " / ")
        let attrs: [NSAttributedString.Key: Any] = [.font: optFont]
        let maxW  = paperWidth - margin * 2 - 8
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: attrs, context: nil
        )
        return boxH + 4 + ceil(bounds.height) + 28
    }

    private static func pillRowsHeight(_ tokens: [String]) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: optFont]
        let maxX = paperWidth - margin - 4
        var rowX = margin + 4
        var totalH: CGFloat = 0
        var rowH:   CGFloat = 0

        for token in tokens {
            let sz = (token as NSString).size(withAttributes: attrs)
            let pw = sz.width  + pillPadH * 2
            let ph = sz.height + pillPadV * 2
            if rowX + pw > maxX && rowX > margin + 4 {
                totalH += rowH + pillGap
                rowX    = margin + 4
                rowH    = 0
            }
            rowH  = max(rowH, ph)
            rowX += pw + pillGap
        }
        return totalH + rowH
    }

    // MARK: - Drawing

    private static func drawContent(
        cart: [CartLine],
        tableName: String,
        payMethod: String?,
        amount: Int,
        ctx: CGContext
    ) {
        let black: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.black]

        var y: CGFloat = 20

        // ── 店名（置中）──
        let shopStr = NSAttributedString(
            string: "眷鳥咖啡商行",
            attributes: black.merging([.font: shopFont]) { $1 }
        )
        let shopW = shopStr.size().width
        shopStr.draw(at: CGPoint(x: (paperWidth - shopW) / 2, y: y))
        y += shopFont.lineHeight + 16

        // ── 桌號（左）+ 時間（右）──
        let fmt = DateFormatter(); fmt.dateFormat = "MM/dd HH:mm"
        let timeText = fmt.string(from: Date())
        let table    = tableName.isEmpty ? "外帶" : tableName
        let tAttrs   = black.merging([.font: tableFont]) { $1 }
        let tableStr = NSAttributedString(string: table,    attributes: tAttrs)
        let timeStr  = NSAttributedString(string: timeText, attributes: tAttrs)
        tableStr.draw(at: CGPoint(x: margin, y: y))
        timeStr.draw(at: CGPoint(x: paperWidth - margin - timeStr.size().width, y: y))
        y += tableFont.lineHeight + 10

        // ── 分隔線 ──
        divider(ctx: ctx, y: y); y += 12

        // ── 品項 ──
        for line in cart {
            y = drawCartLine(line, ctx: ctx, y: y)
        }

        // ── 分隔線 ──
        divider(ctx: ctx, y: y); y += 12

        // ── 總計 ──
        let totAttrs  = black.merging([.font: totalFont]) { $1 }
        let totLabel  = NSAttributedString(string: "總計：",        attributes: totAttrs)
        let totValue  = NSAttributedString(string: "\(amount)",    attributes: totAttrs)
        totLabel.draw(at: CGPoint(x: margin, y: y))
        totValue.draw(at: CGPoint(x: paperWidth - margin - totValue.size().width, y: y))
        y += totalFont.lineHeight + 8

        // ── 結帳方式 ──
        let payText  = payMethod.flatMap { $0.isEmpty ? nil : $0 } ?? "未結帳（重印）"
        let payAttrs = black.merging([.font: payFont]) { $1 }
        NSAttributedString(string: payText, attributes: payAttrs)
            .draw(at: CGPoint(x: margin, y: y))
    }

    @discardableResult
    private static func drawCartLine(_ line: CartLine, ctx: CGContext, y: CGFloat) -> CGFloat {
        var cy = y
        let iAttrs: [NSAttributedString.Key: Any] = [
            .font: itemFont,
            .foregroundColor: UIColor.black
        ]
        let nameStr  = NSAttributedString(string: line.item.name,      attributes: iAttrs)
        let qtyStr   = NSAttributedString(string: "x\(line.quantity)", attributes: iAttrs)
        let priceStr = NSAttributedString(string: "\(line.lineTotal)",  attributes: iAttrs)

        let priceW = priceStr.size().width
        let qtyW   = qtyStr.size().width
        let boxH   = priceStr.size().height + pillPadV * 2

        let qtyBoxW = qtyW + pillPadH * 2
        drawBox(str: qtyStr, x: margin, y: cy, w: qtyBoxW, h: boxH)

        nameStr.draw(at: CGPoint(x: margin + qtyBoxW + 10, y: cy + pillPadV))

        priceStr.draw(at: CGPoint(x: paperWidth - margin - priceW, y: cy + pillPadV))

        cy += boxH + 4

        let tokens = optionTokens(line)
        if !tokens.isEmpty {
            let text  = tokens.joined(separator: " / ")
            let attrs: [NSAttributedString.Key: Any] = [.font: optFont, .foregroundColor: UIColor.black]
            let maxW  = paperWidth - margin * 2 - 8
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: attrs, context: nil
            )
            NSAttributedString(string: text, attributes: attrs)
                .draw(in: CGRect(x: margin + 4, y: cy, width: maxW, height: ceil(bounds.height)))
            cy += ceil(bounds.height) + 28
        } else {
            cy += 14
        }
        return cy
    }

    @discardableResult
    private static func drawPills(tokens: [String], ctx: CGContext, y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: optFont,
            .foregroundColor: UIColor.black
        ]
        let maxX = paperWidth - margin - 4
        var rowX = margin + 4
        var cy   = y
        var rowH: CGFloat = 0

        for token in tokens {
            let tokenStr = NSAttributedString(string: token, attributes: attrs)
            let sz  = tokenStr.size()
            let pw  = sz.width  + pillPadH * 2
            let ph  = sz.height + pillPadV * 2

            // 超出右邊界 → 換行
            if rowX + pw > maxX && rowX > margin + 4 {
                cy   += rowH + pillGap
                rowX  = margin + 4
                rowH  = 0
            }

            // 畫圓角框
            let rect = CGRect(x: rowX, y: cy, width: pw, height: ph)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: pillCorner)
            UIColor.black.setStroke()
            path.lineWidth = pillStroke
            path.stroke()

            // 畫文字
            tokenStr.draw(at: CGPoint(x: rowX + pillPadH, y: cy + pillPadV))

            rowH  = max(rowH, ph)
            rowX += pw + pillGap
        }
        return cy + rowH
    }

    // MARK: - Helpers

    private static func optionTokens(_ line: CartLine) -> [String] {
        var tokens: [String] = []
        if line.temperature != .none { tokens.append(line.temperature.display) }
        if let s = line.sweetness    { tokens.append(s.display) }
        if line.isOatMilk            { tokens.append("燕麥奶(+20)") }
        if line.isRefill             { tokens.append("續點(-20)") }
        if line.isEcoCup             { tokens.append("環保杯(-5)") }
        if line.isTakeawayAfterMeal  { tokens.append("餐後外帶") }
        if line.needsCutlery         { tokens.append("要餐具") }
        for t in line.customToggles {
            if t.priceEffect != 0 {
                tokens.append("\(t.label)(\(t.priceEffect > 0 ? "+" : "")\(t.priceEffect))")
            } else {
                tokens.append(t.label)
            }
        }
        return tokens
    }

    private static func drawBox(str: NSAttributedString, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: pillCorner)
        UIColor.black.setStroke()
        path.lineWidth = pillStroke
        path.stroke()
        str.draw(at: CGPoint(x: x + pillPadH, y: y + pillPadV))
    }

    private static func divider(ctx: CGContext, y: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to:    CGPoint(x: margin,                   y: y))
        ctx.addLine(to: CGPoint(x: paperWidth - margin,      y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

#Preview("收據預覽") {
    let item1 = MenuItem(itemId: "1", categoryId: "c1", name: "美式", price: 80, allowOat: true, addOns: nil)
    let item2 = MenuItem(itemId: "2", categoryId: "c1", name: "拿鐵", price: 120, allowOat: false, addOns: nil)
    let item3 = MenuItem(itemId: "3", categoryId: "c1", name: "卡布奇諾", price: 110, allowOat: false, addOns: nil)
    let cart: [CartLine] = [
        CartLine(
            item: item1, quantity: 2, temperature: .iced, sweetness: .none,
            isOatMilk: true, isRefill: false, isEcoCup: false,
            isTakeawayAfterMeal: false, needsCutlery: false,
            customToggles: [SelectedToggle(label: "少冰", priceEffect: 0)]
        ),
        CartLine(
            item: item2, quantity: 1, temperature: .hot, sweetness: nil,
            isOatMilk: false, isRefill: false, isEcoCup: true,
            isTakeawayAfterMeal: false, needsCutlery: false
        ),
        CartLine(
            item: item3, quantity: 1, temperature: .none, sweetness: nil,
            isOatMilk: false, isRefill: false, isEcoCup: false,
            isTakeawayAfterMeal: false, needsCutlery: false
        )
    ]
    let img = ReceiptRenderer.renderReceiptImage(
        cart: cart, tableName: "桌1", payMethod: "LINE Pay", amount: 460
    )
    return ScrollView {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .padding()
    }
    .background(Color.gray.opacity(0.15))
}
