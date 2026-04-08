//
//  CloseShiftView.swift
//  SimplePOS / NostalPos
//

import SwiftUI
import Foundation

// MARK: - DTO（給畫面用）

struct LiveBusinessSummaryDTO {
    let date: String
    let liveTotalAmount: Int
    let paidTotalAmount: Int
    let pendingTotalAmount: Int
    let totalCash: Int
    let totalCard: Int
    let totalLinePay: Int
    let totalTapPay: Int
    let paidOrderCount: Int
    let pendingOrderCount: Int
    let message: String?
}

struct CloseShiftSummaryDTO {
    let date: String
    let closeableTotalAmount: Int
    let totalCash: Int
    let totalCard: Int
    let totalLinePay: Int
    let totalTapPay: Int
    let orderCount: Int
    let message: String?
}

// MARK: - ViewModel

@MainActor
final class CloseShiftViewModel: ObservableObject {

    @Published var liveSummary: LiveBusinessSummaryDTO?
    @Published var closeSummary: CloseShiftSummaryDTO?
    @Published var isLoading = false
    @Published var isClosing = false
    @Published var errorMessage: String?

    // MARK: - 讀取畫面所需資料

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let liveResponse = APIClient.shared.fetchLiveBusinessSummary()
            async let closeResponse = APIClient.shared.fetchCloseShiftSummary()

            let (live, close) = try await (liveResponse, closeResponse)

            if let ok = live.ok, !ok {
                throw NSError(
                    domain: "CloseShift",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: live.error ?? live.message ?? "營業中總覽載入失敗"]
                )
            }

            if let ok = close.ok, !ok {
                throw NSError(
                    domain: "CloseShift",
                    code: -1002,
                    userInfo: [NSLocalizedDescriptionKey: close.error ?? close.message ?? "關帳總覽載入失敗"]
                )
            }

            self.liveSummary = LiveBusinessSummaryDTO(
                date: live.date,
                liveTotalAmount: live.liveTotalAmount,
                paidTotalAmount: live.paidTotalAmount,
                pendingTotalAmount: live.pendingTotalAmount,
                totalCash: live.totalCash,
                totalCard: live.totalCard,
                totalLinePay: live.totalLinePay,
                totalTapPay: live.totalTapPay,
                paidOrderCount: live.paidOrderCount,
                pendingOrderCount: live.pendingOrderCount,
                message: live.message
            )

            self.closeSummary = CloseShiftSummaryDTO(
                date: close.date,
                closeableTotalAmount: close.closeableTotalAmount,
                totalCash: close.totalCash,
                totalCard: close.totalCard,
                totalLinePay: close.totalLinePay,
                totalTapPay: close.totalTapPay,
                orderCount: close.orderCount,
                message: close.message
            )

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 執行關帳

    func closeShift() async {
        isClosing = true
        errorMessage = nil
        defer { isClosing = false }

        do {
            let result = try await APIClient.shared.closeShift()

            if let ok = result.ok, !ok {
                throw NSError(
                    domain: "CloseShift",
                    code: -1003,
                    userInfo: [NSLocalizedDescriptionKey: result.error ?? result.message ?? "關帳失敗"]
                )
            }

            self.closeSummary = CloseShiftSummaryDTO(
                date: result.date,
                closeableTotalAmount: result.closeableTotalAmount,
                totalCash: result.totalCash,
                totalCard: result.totalCard,
                totalLinePay: result.totalLinePay,
                totalTapPay: result.totalTapPay,
                orderCount: result.orderCount,
                message: result.message
            )

            // 關帳後再重抓一次，讓營業中總覽 / 可關帳總覽都同步最新資料
            await load()

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct CloseShiftView: View {

    @StateObject private var viewModel = CloseShiftViewModel()

    var body: some View {
        NavigationView {
            content
                .navigationTitle("關帳")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading || viewModel.isClosing)
                    }
                }
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.liveSummary == nil && viewModel.closeSummary == nil {
            VStack {
                ProgressView()
                Text("載入關帳資料中…")
                    .padding(.top, 8)
            }
        } else if viewModel.liveSummary != nil || viewModel.closeSummary != nil {
            Form {
                Section(header: Text("日期")) {
                    Text(displayDate)
                }

                if let live = viewModel.liveSummary {
                    Section(header: Text("營業中總覽（含未結帳）")) {
                        row(label: "目前累積總額", value: live.liveTotalAmount)
                        row(label: "已收款金額", value: live.paidTotalAmount)
                        row(label: "未收款掛帳", value: live.pendingTotalAmount)
                        row(label: "已收款訂單數", value: live.paidOrderCount)
                        row(label: "未結帳訂單數", value: live.pendingOrderCount)
                    }

                    Section(header: Text("已收款付款方式")) {
                        row(label: "現金", value: live.totalCash)
                        row(label: "刷卡", value: live.totalCard)
                        row(label: "Line Pay", value: live.totalLinePay)
                        row(label: "TapPay", value: live.totalTapPay)
                    }

                    if let msg = live.message, !msg.isEmpty {
                        Section(header: Text("營業中訊息")) {
                            Text(msg)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let close = viewModel.closeSummary {
                    Section(header: Text("正式關帳總覽（本次可關帳）")) {
                        row(label: "可關帳總額", value: close.closeableTotalAmount)
                        row(label: "現金", value: close.totalCash)
                        row(label: "刷卡", value: close.totalCard)
                        row(label: "Line Pay", value: close.totalLinePay)
                        row(label: "TapPay", value: close.totalTapPay)
                        row(label: "可關帳訂單數", value: close.orderCount)
                    }

                    if let msg = close.message, !msg.isEmpty {
                        Section(header: Text("關帳訊息")) {
                            Text(msg)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button {
                            Task { await viewModel.closeShift() }
                        } label: {
                            if viewModel.isClosing {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Text(" 關帳中…")
                                    Spacer()
                                }
                            } else {
                                Text("執行關帳")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .disabled(viewModel.isClosing || close.orderCount == 0)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let err = viewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(8)
                }
            }
        } else if let err = viewModel.errorMessage {
            VStack(spacing: 12) {
                Text("載入失敗")
                    .font(.headline)

                Text(err)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("重試") {
                    Task { await viewModel.load() }
                }
                .padding(.top, 8)
            }
            .padding()
        } else {
            Text("尚無關帳資料")
                .foregroundColor(.secondary)
        }
    }

    private var displayDate: String {
        if let close = viewModel.closeSummary, !close.date.isEmpty {
            return close.date
        }
        if let live = viewModel.liveSummary, !live.date.isEmpty {
            return live.date
        }
        return "—"
    }

    private func row(label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
        }
    }
}

#Preview {
    CloseShiftView()
}
