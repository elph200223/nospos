//
//  CheckoutSheet.swift
//  NostalPos
//

import SwiftUI

struct CheckoutSheet: View {
    let totalAmount: Int
    let onSelect: (PaymentMethod) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("選擇支付方式")
                .font(.title3.bold())

            Text("本次金額：\(totalAmount) 元")
                .font(.headline)

            VStack(spacing: 12) {
                Button {
                    onSelect(.cash)
                } label: {
                    Text("現金")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.peacock)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button {
                    onSelect(.linePay)
                } label: {
                    Text("LINE Pay")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.peacock, lineWidth: 1)
                        )
                        .foregroundColor(.peacock)
                }

                Button {
                    onSelect(.tapPay)
                } label: {
                    Text("TapPay")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.peacock, lineWidth: 1)
                        )
                        .foregroundColor(.peacock)
                }
            }

            Button(role: .cancel) {
                onCancel()
            } label: {
                Text("取消")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color.posBg)
    }
}

