//
//  TableOrderSheet.swift
//  NostalPos
//

import SwiftUI

struct TableOrderSheet: View {
    @EnvironmentObject var vm: POSViewModel
    @Environment(\.dismiss) private var dismiss

    let tableName: String
    let orderTime: Date
    let lines: [CartLine]
    let note: String
    let totalAmount: Int
    let payMethod: String?

    let onReprint: () -> Void
    let onDelete: () -> Void

    @State private var showHint = false
    @State private var hintText = ""

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    private var statusText: (text: String, color: Color)? {
        if lines.isEmpty { return nil }

        if let method = payMethod, !method.isEmpty {
            return ("已結帳（\(method)）", .green)
        }

        if currentPendingOrder != nil {
            return ("尚未結帳", .red)
        }

        return ("已結帳", .green)
    }

    private var isPending: Bool {
        currentPendingOrder != nil
    }

    private var currentPendingOrder: TodayOrderDTO? {
        vm.ordersForTable(tableName)
            .filter {
                String($0.status ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() == "PENDING"
            }
            .sorted { vm.createdAtDate(for: $0) > vm.createdAtDate(for: $1) }
            .first
    }

    private func toast(_ msg: String) {
        hintText = msg
        showHint = true
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    itemsCard
                    actionSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("訂單明細")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
        .frame(maxWidth: 480)
        .background(Color(.systemGroupedBackground))
        .alert("提示", isPresented: $showHint) {
            Button("好") { showHint = false }
        } message: {
            Text(hintText)
        }
        .onAppear {
            vm.clearPendingOrderSelections()
        }
        .onDisappear {
            vm.clearPendingOrderSelections()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tableName)
                        .font(.title3.weight(.bold))
                    Text("點餐時間：\(Self.timeFormatter.string(from: orderTime))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let status = statusText {
                    Text(status.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(status.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("備註")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(note)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("總計")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(totalAmount)")
                        .font(.title2.bold())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("品項內容")
                    .font(.headline)
                Spacer()
                Text("共 \(lines.count) 筆")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if lines.isEmpty {
                Text("目前沒有品項")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(line.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Text("x\(line.quantity)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 42, alignment: .trailing)

                                Text("$\(line.lineTotal)")
                                    .font(.subheadline.bold())
                                    .frame(width: 72, alignment: .trailing)
                            }

                            if let desc = line.detailDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.bottom, 10)

                        if line.id != lines.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            TicketActionButton(title: "", icon: "printer", kind: .secondary, action: onReprint)

            if isPending {
                TicketActionButton(title: "編輯", icon: "square.and.pencil", kind: .secondary) {
                    guard let order = currentPendingOrder else {
                        toast("找不到可編輯的未結帳單")
                        return
                    }
                    vm.startModifying(order: order)
                    dismiss()
                }

                TicketActionButton(title: "結帳", icon: "creditcard", kind: .primary) {
                    if lines.isEmpty {
                        toast("目前沒有品項，無法結帳")
                        return
                    }
                    vm.checkoutPendingFromTableSheet(tableName)
                    dismiss()
                }

                TicketActionButton(title: "取消訂單", icon: "xmark.circle", kind: .danger) {
                    vm.cancelPendingOrder(for: tableName)
                    dismiss()
                }

                TicketActionButton(title: "清桌", icon: "trash", kind: .secondary) {
                    toast("此桌尚未結帳，請先結帳或取消訂單")
                }

                Text("未結帳單不可直接清桌；若客人取消，請使用「取消訂單」。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            } else {
                TicketActionButton(title: "清桌", icon: "trash", kind: .danger) {
                    vm.clearTableForNextGuest(tableName)
                    dismiss()
                }

                Text("清桌代表此桌本輪結束，將清空桌位與計時，但仍可立即復原。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}


// MARK: - 多單版本：小票橫向排列 + 合併結帳

struct TableOrdersSheet: View {
    @EnvironmentObject var vm: POSViewModel
    @Environment(\.dismiss) private var dismiss

    let tableName: String
    let onDelete: () -> Void

    @State private var showHint = false
    @State private var hintText = ""

    private func toast(_ msg: String) {
        hintText = msg
        showHint = true
    }

    private func isPending(_ o: TodayOrderDTO) -> Bool {
        let st = (o.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return st == "PENDING"
    }

    private func parseCreatedAt(_ raw: String?) -> Date? {
        guard let s0 = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s0.isEmpty else { return nil }

        if let v = Double(s0) {
            let seconds = (v > 1_000_000_000_000) ? (v / 1000.0) : v
            return Date(timeIntervalSince1970: seconds)
        }

        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s0) { return d }

        let fmts = ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd HH:mm:ss"]
        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = f
            if let d = df.date(from: s0) { return d }
        }
        return nil
    }

    private var selectedPendingOrderIdsForThisTable: [String] {
        let allPendingIds = Set(
            vm.ordersForTable(tableName)
                .filter { isPending($0) }
                .map { $0.orderId }
        )
        return vm.selectedPendingOrderIds.filter { allPendingIds.contains($0) }.sorted()
    }

    private var selectedPendingTotal: Int {
        vm.ordersForTable(tableName)
            .filter { selectedPendingOrderIdsForThisTable.contains($0.orderId) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tableName)
                            .font(.system(size: 17, weight: .bold))
                        Text("左右滑動查看同桌所有明細")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    TicketMiniButton(title: "清桌", icon: "trash", kind: .danger) {
                        if vm.hasPendingOrder(for: tableName) {
                            toast("此桌尚未結帳，請先結帳或取消訂單")
                            return
                        }
                        vm.clearTableForNextGuest(tableName)
                        onDelete()
                        dismiss()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                let orders = vm.roundOrdersForTable(tableName)
                    .sorted { a, b in
                        let da = parseCreatedAt(a.createdAt) ?? .distantPast
                        let db = parseCreatedAt(b.createdAt) ?? .distantPast
                        if da != db { return da > db }
                        return a.orderId > b.orderId
                    }

                if orders.isEmpty {
                    Spacer()
                    Text("此桌目前沒有訂單")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(orders, id: \.orderId) { o in
                                ReceiptTicket(
                                    tableName: tableName,
                                    order: o,
                                    timeText: vm.createdAtText(for: o),
                                    pending: isPending(o),
                                    isSelected: vm.isPendingOrderSelected(o.orderId),
                                    lines: vm.cartLinesForDisplay(from: o),
                                    onEdit: {
                                        vm.startModifying(order: o)
                                        dismiss()
                                    },
                                    onReprint: {
                                        PrinterManager.shared.printReprintReceipt(
                                            cart: vm.cartLinesForDisplay(from: o),
                                            tableName: tableName,
                                            payMethod: {
                                                let pm = (o.payMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                                return pm.isEmpty ? nil : pm
                                            }(),
                                            amount: o.amount
                                        )
                                    },
                                    onToggleSelection: {
                                        vm.togglePendingOrderSelection(o.orderId)
                                    },
                                    onCheckout: {
                                        let displayLines = vm.cartLinesForDisplay(from: o)
                                        if displayLines.isEmpty {
                                            toast("訂單內容為空，無法結帳")
                                            return
                                        }
                                        vm.checkoutPendingFromTableSheet(tableName, orderId: o.orderId)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    if selectedPendingOrderIdsForThisTable.count >= 2 {
                        HStack(spacing: 10) {
                            Text("已勾選 \(selectedPendingOrderIdsForThisTable.count) 張")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("合計 $\(selectedPendingTotal)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Button {
                                vm.beginCombinedPendingCheckout(for: tableName, orderIds: selectedPendingOrderIdsForThisTable)
                                dismiss()
                            } label: {
                                Text("進入合併結帳")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                    }
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("本桌所有訂單")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .alert("提示", isPresented: $showHint) {
            Button("好") { showHint = false }
        } message: {
            Text(hintText)
        }
        .onAppear {
            vm.clearPendingOrderSelections()
        }
        .onDisappear {
            if vm.selectedPendingOrderIds.count < 2 {
                vm.clearPendingOrderSelections()
            }
        }
    }
}

// MARK: - 單張小票（橫向排列用）

private struct ReceiptTicket: View {
    let tableName: String
    let order: TodayOrderDTO
    let timeText: String
    let pending: Bool
    let isSelected: Bool
    let lines: [CartLine]
    let onEdit: () -> Void
    let onReprint: () -> Void
    let onToggleSelection: () -> Void
    let onCheckout: () -> Void

    private func payMethodText() -> String {
        let pm = (order.payMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return pm.isEmpty ? "" : pm
    }

    private func splitTime(_ s: String) -> (hm: String, md: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return ("", "") }

        if t.contains("/") && t.contains(":") {
            let parts = t.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                let p0 = parts[0]
                let p1 = parts[1]
                if p0.contains("/") && p1.contains(":") { return (p1, p0) }
                if p0.contains(":") && p1.contains("/") { return (p0, p1) }
            }
        }

        return (t, "")
    }

    private var displayPayMethod: String {
        payMethodText()
    }

    var body: some View {
        let tt = splitTime(timeText)
        let pm = displayPayMethod

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TicketMiniButton(title: "", icon: "printer", kind: .warningYellow, action: onReprint)

                if pending {
                    TicketMiniButton(title: "結帳", icon: "", kind: .danger, action: onCheckout)
                    TicketMiniButton(title: "編輯", icon: "", kind: .primaryBlue, action: onEdit)
                    MergeSelectionButton(isSelected: isSelected, action: onToggleSelection)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tt.hm)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    if !tt.md.isEmpty {
                        Text(tt.md)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(tableName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }

            if !pm.isEmpty {
                Text(pm)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    Text("（無品項）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 6)

                                Text("x\(line.quantity)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .trailing)

                                Text("$\(line.lineTotal)")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 58, alignment: .trailing)
                            }

                            if let desc = line.detailDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 6)

                        if index < lines.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack {
                if !pending {
                    Text("已結帳")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Text("$\(order.amount)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
            }
        }
        .padding(12)
        .frame(width: 330, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct MergeSelectionButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 12, weight: .bold))
                Text("合併結帳")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 112)
            .background(isSelected ? Color.black.opacity(0.12) : Color(.secondarySystemBackground))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Buttons

private enum TicketButtonKind {
    case primary
    case primaryBlue
    case secondary
    case danger
    case warningYellow
}

private struct TicketActionButton: View {
    let title: String
    let icon: String
    let kind: TicketButtonKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: icon)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 12)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary: return .accentColor
        case .primaryBlue: return .blue
        case .secondary: return Color(.secondarySystemBackground)
        case .danger: return Color.red
        case .warningYellow: return Color.yellow
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .primaryBlue: return .white
        case .secondary: return .primary
        case .danger: return .white
        case .warningYellow: return .primary
        }
    }
}

private struct TicketMiniButton: View {
    let title: String
    let icon: String
    let kind: TicketButtonKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: icon.isEmpty ? 0 : 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 14, alignment: .center)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary: return .accentColor
        case .primaryBlue: return .blue
        case .secondary: return Color(.secondarySystemBackground)
        case .danger: return Color.red.opacity(0.14)
        case .warningYellow: return Color.yellow
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .primaryBlue: return .white
        case .secondary: return .primary
        case .danger: return .red
        case .warningYellow: return .primary
        }
    }
}
