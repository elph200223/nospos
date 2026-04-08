//
//  TodayOrdersView.swift
//  NostalPos
//

import SwiftUI
import Foundation

// MARK: - DTO

struct TodayOrderItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var price: Int
    var qty: Int

    enum CodingKeys: String, CodingKey {
        case name, price, qty
    }
}

struct TodayOrderDTO: Identifiable, Codable, Hashable {
    var id: String { orderId }

    let orderId: String
    let createdAt: String
    let tableName: String
    let payMethod: String
    let amount: Int
    let note: String?
    let status: String?
    let items: [TodayOrderItem]

    enum CodingKeys: String, CodingKey {
        case orderId
        case createdAt
        case tableName
        case payMethod
        case amount
        case note
        case status
        case items
    }
}

// MARK: - ViewModel

@MainActor
final class TodayOrdersViewModel: ObservableObject {

    @Published var orders: [TodayOrderDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await APIClient.shared.fetchTodayOrders()
            orders = fetched.sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = "載入今日訂單失敗：\(error.localizedDescription)"
            print("❌ load today orders error:", error)
        }
    }

    func delete(order: TodayOrderDTO) async {
        errorMessage = nil

        do {
            try await APIClient.shared.deleteOrderAsync(orderId: order.orderId)
            orders.removeAll { $0.orderId == order.orderId }
        } catch {
            errorMessage = "刪除訂單失敗：\(error.localizedDescription)"
            print("❌ delete order error:", error)
        }
    }

    func reprint(order: TodayOrderDTO) async {
        errorMessage = nil

        do {
            try await APIClient.shared.reprintOrderAsync(orderId: order.orderId)
        } catch {
            errorMessage = "重新列印失敗：\(error.localizedDescription)"
            print("❌ reprint order error:", error)
        }
    }
}

// MARK: - 主畫面

struct TodayOrdersView: View {
    let onModifyPendingOrder: ((TodayOrderDTO) -> Void)?
    let onCombinedCheckout: ((String, [String]) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = TodayOrdersViewModel()
    @State private var selectedOrder: TodayOrderDTO?
    @State private var showErrorAlert = false

    @State private var isCombinedSelectionMode = false
    @State private var selectedPendingOrderIds: Set<String> = []
    @State private var selectedPendingTableName: String? = nil

    init(
        onModifyPendingOrder: ((TodayOrderDTO) -> Void)? = nil,
        onCombinedCheckout: ((String, [String]) -> Void)? = nil
    ) {
        self.onModifyPendingOrder = onModifyPendingOrder
        self.onCombinedCheckout = onCombinedCheckout
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if viewModel.isLoading && viewModel.orders.isEmpty {
                    ProgressView("載入今日訂單中…")
                } else if viewModel.orders.isEmpty {
                    VStack(spacing: 8) {
                        Text("今天還沒有任何訂單")
                            .foregroundColor(.secondary)
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Label("重新整理", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.orders) { order in
                            Button {
                                handleTap(order: order)
                            } label: {
                                TodayOrderRow(
                                    order: order,
                                    showsSelectionControl: isCombinedSelectionMode && isPending(order),
                                    isSelected: selectedPendingOrderIds.contains(order.orderId),
                                    isSelectionDisabled: isCombinedSelectionMode && isPending(order) && !canToggleSelection(for: order)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isCombinedSelectionMode && isPending(order) && !canToggleSelection(for: order))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if isPending(order) {
                                    Button {
                                        if let cb = onModifyPendingOrder {
                                            cb(order)
                                        }
                                        dismiss()
                                    } label: {
                                        Label("編輯", systemImage: "square.and.pencil")
                                    }
                                    .tint(.blue)
                                }

                                Button(role: .destructive) {
                                    Task { await viewModel.delete(order: order) }
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }

                                Button {
                                    Task { await viewModel.reprint(order: order) }
                                } label: {
                                    Label("重印", systemImage: "printer")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) {
                        if isCombinedSelectionMode {
                            combinedCheckoutBar
                        }
                    }
                }
            }
            .navigationTitle("今日訂單")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") { dismiss() }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)

                    Button(isCombinedSelectionMode ? "取消勾選" : "聯合結帳") {
                        toggleCombinedSelectionMode()
                    }
                    .disabled(pendingOrders.isEmpty)
                }
            }
            .task {
                await viewModel.load()
            }
            .onChange(of: viewModel.errorMessage) { newValue in
                showErrorAlert = (newValue != nil)
            }
            .alert("錯誤", isPresented: $showErrorAlert, actions: {
                Button("好") { }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .sheet(item: $selectedOrder) { order in
                TodayOrderDetailSheet(
                    order: order,
                    onReprint: {
                        Task { await viewModel.reprint(order: order) }
                    },
                    onDelete: {
                        Task {
                            await viewModel.delete(order: order)
                            selectedOrder = nil
                        }
                    },
                    onModifyPendingOrder: isPending(order) ? {
                        if let cb = onModifyPendingOrder {
                            cb(order)
                        }
                        dismiss()
                    } : nil
                )
            }
        }
    }

    private var pendingOrders: [TodayOrderDTO] {
        viewModel.orders.filter { isPending($0) }
    }

    private var selectedPendingOrders: [TodayOrderDTO] {
        viewModel.orders.filter { selectedPendingOrderIds.contains($0.orderId) }
    }

    private var selectedCombinedAmount: Int {
        selectedPendingOrders.reduce(0) { $0 + $1.amount }
    }

    private var combinedCheckoutBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已勾選 \(selectedPendingOrderIds.count) 張未結帳單")
                        .font(.headline)
                    Text(selectedPendingTableName?.isEmpty == false ? "桌位：\(selectedPendingTableName!)" : "請勾選同一桌的未結帳單")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("NT$ \(selectedCombinedAmount)")
                    .font(.title3.bold())
            }

            Button {
                beginCombinedCheckout()
            } label: {
                Text("聯合結帳")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedPendingOrderIds.isEmpty ? Color.gray.opacity(0.3) : Color.peacock)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedPendingOrderIds.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.thinMaterial)
    }

    private func handleTap(order: TodayOrderDTO) {
        if isCombinedSelectionMode && isPending(order) {
            toggleSelection(for: order)
            return
        }
        selectedOrder = order
    }

    private func isPending(_ order: TodayOrderDTO) -> Bool {
        (order.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "PENDING"
    }

    private func normalizedTableName(_ order: TodayOrderDTO) -> String {
        order.tableName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canToggleSelection(for order: TodayOrderDTO) -> Bool {
        guard isPending(order) else { return false }
        if selectedPendingOrderIds.contains(order.orderId) { return true }
        guard let selectedTable = selectedPendingTableName, !selectedTable.isEmpty else { return true }
        return selectedTable == normalizedTableName(order)
    }

    private func toggleSelection(for order: TodayOrderDTO) {
        guard isPending(order) else { return }

        let orderId = order.orderId
        let tableName = normalizedTableName(order)

        if selectedPendingOrderIds.contains(orderId) {
            selectedPendingOrderIds.remove(orderId)
            if selectedPendingOrderIds.isEmpty {
                selectedPendingTableName = nil
            }
            return
        }

        if let selectedTable = selectedPendingTableName,
           !selectedTable.isEmpty,
           selectedTable != tableName {
            viewModel.errorMessage = "聯合結帳一次只能勾選同一桌的未結帳單"
            return
        }

        selectedPendingOrderIds.insert(orderId)
        selectedPendingTableName = tableName
    }

    private func toggleCombinedSelectionMode() {
        isCombinedSelectionMode.toggle()
        if !isCombinedSelectionMode {
            selectedPendingOrderIds.removeAll()
            selectedPendingTableName = nil
        }
    }

    private func beginCombinedCheckout() {
        guard let tableName = selectedPendingTableName,
              !tableName.isEmpty,
              !selectedPendingOrderIds.isEmpty
        else {
            return
        }

        let ids = selectedPendingOrders
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.orderId }

        guard !ids.isEmpty else { return }

        onCombinedCheckout?(tableName, ids)
        dismiss()
    }
}

// MARK: - 列表 Row

struct TodayOrderRow: View {
    let order: TodayOrderDTO
    let showsSelectionControl: Bool
    let isSelected: Bool
    let isSelectionDisabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsSelectionControl {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelectionDisabled && !isSelected ? .gray.opacity(0.5) : .peacock)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(order.tableName.isEmpty ? "外帶" : order.tableName)
                        .font(.headline)
                    if let status = order.status, !status.isEmpty {
                        Text(statusDisplay(status))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.15))
                            .foregroundColor(statusColor(status))
                            .cornerRadius(4)
                    }
                }

                Text("金額：\(order.amount)")
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(order.payMethod)
                    Text(order.createdAt)
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                if let note = order.note, !note.isEmpty {
                    Text("備註：\(note)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !order.items.isEmpty {
                    Text("品項：\(order.items.map { $0.name }.joined(separator: "、"))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func statusDisplay(_ status: String) -> String {
        switch status.uppercased() {
        case "PAID":
            return "已結帳"
        case "CANCELLED":
            return "已取消"
        case "VOID":
            return "已作廢"
        case "PENDING":
            return "未結帳"
        default:
            return status
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "PAID":
            return .green
        case "CANCELLED", "VOID":
            return .red
        case "PENDING":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - 詳細內容 Sheet

struct TodayOrderDetailSheet: View {
    let order: TodayOrderDTO
    let onReprint: () -> Void
    let onDelete: () -> Void
    let onModifyPendingOrder: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("訂單資訊")) {
                    infoRow("桌位", order.tableName.isEmpty ? "外帶" : order.tableName)
                    infoRow("時間", order.createdAt)
                    infoRow("金額", "\(order.amount)")
                    infoRow("付款方式", order.payMethod)

                    if let status = order.status {
                        infoRow("狀態", status)
                    }

                    if let note = order.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("備註")
                            Text(note)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("品項")) {
                    ForEach(order.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text("單價：\(item.price)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("x\(item.qty)")
                        }
                    }
                }

                Section(header: Text("操作")) {
                    if let onModifyPendingOrder {
                        Button {
                            onModifyPendingOrder()
                        } label: {
                            Text("編輯未結帳單")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button {
                        onReprint()
                    } label: {
                        Text("重新列印")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("刪除訂單")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle("訂單明細")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
    }
}
