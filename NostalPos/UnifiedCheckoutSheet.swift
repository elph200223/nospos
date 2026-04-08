//
//  UnifiedCheckoutSheet.swift
//  NostalPos
//

import SwiftUI

struct UnifiedCheckoutSheet: View {

    let totalAmount: Int

    let onCashConfirm: (Int) -> Void      // 現金結帳，傳入「實收金額」
    let onLinePay: () -> Void             // 按下 LINE Pay 時交給外層處理（外層負責開掃碼畫面）
    let onTapPay: () -> Void              // TapPay 完成後通知外層
    let onCancel: () -> Void              // 關閉結帳視窗

    @State private var cashReceivedText: String = ""

    // 實收金額（轉成 Int）
    private var cashReceived: Int {
        Int(cashReceivedText) ?? 0
    }

    // 找零金額
    private var change: Int {
        max(cashReceived - totalAmount, 0)
    }

    var body: some View {
        HStack(spacing: 24) {

            // MARK: 左邊：金額 + 現金輸入 + 計算機
            VStack(alignment: .leading, spacing: 16) {
                Text("結帳")
                    .font(.title2.bold())

                // 三行：應收 / 實收 / 找零（數字一樣大）
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("應收金額")
                            .font(.headline)
                        Spacer()
                        Text("NT$ \(totalAmount)")
                            .font(.title2.bold())
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

                // 實收 TextField（可以直接打數字）
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

                // 計算機按鈕區（圓角 + 灰色粗體）
                VStack(spacing: 8) {

                    HStack(spacing: 8) {
                        calcButton("1") { appendDigit("1") }
                        calcButton("2") { appendDigit("2") }
                        calcButton("3") { appendDigit("3") }
                        calcButton("100") { addAmount(100) }
                    }

                    HStack(spacing: 8) {
                        calcButton("4") { appendDigit("4") }
                        calcButton("5") { appendDigit("5") }
                        calcButton("6") { appendDigit("6") }
                        calcButton("500") { addAmount(500) }
                    }

                    HStack(spacing: 8) {
                        calcButton("7") { appendDigit("7") }
                        calcButton("8") { appendDigit("8") }
                        calcButton("9") { appendDigit("9") }
                        calcButton("1000") { addAmount(1000) }
                    }

                    HStack(spacing: 8) {
                        calcButton("00") { appendDoubleZero() }
                        calcButton("0") { appendDigit("0") }
                        calcButton("⌫") { backspace() }
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
                        // 如果沒輸入，就當作「實收 = 應收」
                        let received = cashReceived > 0 ? cashReceived : totalAmount
                        onCashConfirm(received)
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

            // MARK: 右邊：支付方式圓形按鈕
            VStack(spacing: 28) {

                VStack(spacing: 8) {
                    Button {
                        // ✅ 這裡「只」通知外層 CartPanel，要開掃描畫面
                        onLinePay()
                    } label: {
                        paymentCircleView(color: .green, title: "LINE\nPay")
                    }
                    Text("LINE Pay")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    Button {
                        onTapPay()
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

    private func calcButton(_ title: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(.gray)                  // 灰色粗體字
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)   // 圓圓方方
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
        if cashReceivedText == "0" {
            cashReceivedText = digit
        } else {
            cashReceivedText += digit
        }
    }

    private func appendDoubleZero() {
        if cashReceivedText.isEmpty {
            cashReceivedText = "0"
        } else {
            cashReceivedText += "00"
        }
    }

    private func addAmount(_ value: Int) {
        let current = cashReceived
        cashReceivedText = String(current + value)
    }

    private func backspace() {
        guard !cashReceivedText.isEmpty else { return }
        cashReceivedText.removeLast()
    }

    private func clearAll() {
        cashReceivedText = ""
    }

    // MARK: - 小圓圈 UI

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

