//
//  UnifiedCheckoutSheet.swift
//  NostalPos
//

import SwiftUI

// MARK: - Discount Mode

private enum DiscountMode: String, CaseIterable {
    case none       = "無折扣"
    case percentage = "折數"
    case fixed      = "扣除金額"
}

struct UnifiedCheckoutSheet: View {

    let totalAmount: Int

    let onCashConfirm: (_ received: Int, _ finalAmount: Int) -> Void
    let onLinePay:     (_ finalAmount: Int) -> Void
    let onTapPay:      (_ finalAmount: Int) -> Void
    let onCancel:      () -> Void

    @State private var cashReceivedText: String = ""

    // Discount
    @State private var discountMode: DiscountMode = .none
    @State private var percentText: String = ""   // e.g. "9" or "8.5"
    @State private var fixedText:   String = ""   // fixed amount to deduct

    // 折後應收
    private var discountedTotal: Int {
        switch discountMode {
        case .none:
            return totalAmount
        case .percentage:
            let pct = Double(percentText) ?? 10
            let ratio = min(max(pct, 0), 10) / 10.0
            return Int((Double(totalAmount) * ratio).rounded())
        case .fixed:
            let deduct = Int(fixedText) ?? 0
            return max(totalAmount - deduct, 0)
        }
    }

    private var discountAmount: Int { totalAmount - discountedTotal }

    private var cashReceived: Int { Int(cashReceivedText) ?? 0 }
    private var change: Int { max(cashReceived - discountedTotal, 0) }

    var body: some View {
        HStack(spacing: 24) {

            // MARK: 左邊
            VStack(alignment: .leading, spacing: 16) {
                Text("結帳")
                    .font(.title2.bold())

                // ── 折扣區 ──────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    // 模式選擇
                    Picker("折扣", selection: $discountMode) {
                        ForEach(DiscountMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if discountMode == .percentage {
                        VStack(alignment: .leading, spacing: 6) {
                            // 快捷按鈕
                            HStack(spacing: 6) {
                                ForEach(["9", "8.5", "8", "7"], id: \.self) { p in
                                    Button("\(p)折") { percentText = p }
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(percentText == p ? Color.peacock : Color.white)
                                        )
                                        .foregroundColor(percentText == p ? .white : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }

                            HStack {
                                TextField("自訂折數（例：8.5）", text: $percentText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                Text("折")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if discountMode == .fixed {
                        HStack {
                            Text("扣除")
                                .font(.subheadline)
                            TextField("輸入折扣金額", text: $fixedText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Text("元")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(discountMode == .none ? Color.clear : Color.orange.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(discountMode == .none ? Color.clear : Color.orange.opacity(0.3),
                                        lineWidth: 1)
                        )
                )

                // ── 金額摘要 ─────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    if discountMode != .none {
                        HStack {
                            Text("原價")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("NT$ \(totalAmount)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("折扣")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Spacer()
                            Text("－ NT$ \(discountAmount)")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        Divider()
                    }

                    HStack {
                        Text("應收金額")
                            .font(.headline)
                        Spacer()
                        Text("NT$ \(discountedTotal)")
                            .font(.title2.bold())
                            .foregroundColor(discountMode == .none ? .primary : .red)
                    }

                    HStack {
                        Text("實收金額")
                            .font(.headline)
                        Spacer()
                        Text("NT$ \(cashReceived)")
                            .font(.title2.bold())
                    }

                    HStack {
                        Text("找零")
                            .font(.headline)
                        Spacer()
                        Text("NT$ \(change)")
                            .font(.title2.bold())
                    }
                }

                // ── 現金輸入 ─────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("輸入實收金額")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("點下面按鈕或直接輸入", text: $cashReceivedText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Text("元")
                            .font(.subheadline)
                    }
                    .frame(width: 260)
                }

                // ── 計算機 ───────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        calcButton("1")    { appendDigit("1") }
                        calcButton("2")    { appendDigit("2") }
                        calcButton("3")    { appendDigit("3") }
                        calcButton("100")  { addAmount(100) }
                    }
                    HStack(spacing: 8) {
                        calcButton("4")    { appendDigit("4") }
                        calcButton("5")    { appendDigit("5") }
                        calcButton("6")    { appendDigit("6") }
                        calcButton("500")  { addAmount(500) }
                    }
                    HStack(spacing: 8) {
                        calcButton("7")    { appendDigit("7") }
                        calcButton("8")    { appendDigit("8") }
                        calcButton("9")    { appendDigit("9") }
                        calcButton("1000") { addAmount(1000) }
                    }
                    HStack(spacing: 8) {
                        calcButton("00")   { appendDoubleZero() }
                        calcButton("0")    { appendDigit("0") }
                        calcButton("⌫")    { backspace() }
                        calcButton("清除") { clearAll() }
                    }
                }

                Spacer()

                HStack {
                    Button(role: .cancel) {
                        onCancel()
                    } label: {
                        Text("取消")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.12))
                            )
                    }

                    Button {
                        let received = cashReceived > 0 ? cashReceived : discountedTotal
                        onCashConfirm(received, discountedTotal)
                    } label: {
                        Text("現金結帳")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.peacock)
                            )
                            .foregroundColor(.white)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(radius: 4, x: 0, y: 2)
            )

            // MARK: 右邊：支付方式
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Button {
                        onLinePay(discountedTotal)
                    } label: {
                        paymentCircleView(color: .green, title: "LINE\nPay")
                    }
                    Text("LINE Pay")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    Button {
                        onTapPay(discountedTotal)
                    } label: {
                        paymentCircleView(color: .orange, title: "Tap\nPay")
                    }
                    Text("TapPay")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(width: 140)
        }
        .padding()
        .background(Color.posBg.ignoresSafeArea())
    }

    // MARK: - 計算機按鈕 UI

    private func calcButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
    }

    // MARK: - 計算機邏輯

    private func appendDigit(_ digit: String) {
        if cashReceivedText == "0" { cashReceivedText = digit }
        else { cashReceivedText += digit }
    }

    private func appendDoubleZero() {
        if cashReceivedText.isEmpty { cashReceivedText = "0" }
        else { cashReceivedText += "00" }
    }

    private func addAmount(_ value: Int) {
        cashReceivedText = String(cashReceived + value)
    }

    private func backspace() {
        guard !cashReceivedText.isEmpty else { return }
        cashReceivedText.removeLast()
    }

    private func clearAll() { cashReceivedText = "" }

    // MARK: - 圓形按鈕 UI

    private func paymentCircleView(color: Color, title: String) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 80, height: 80)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
    }
}
