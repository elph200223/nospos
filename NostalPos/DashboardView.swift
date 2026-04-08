//
//  DashboardView.swift
//  NostalPos
//

import SwiftUI

// 讓左滑刪除能鎖定外層水平 ScrollView，避免手勢衝突（singleton 避免 LazyHStack 環境丟失）
private class SwipeCoordinator: ObservableObject {
    static let shared = SwipeCoordinator()
    private init() {}
    @Published var isSwiping = false
}

// MARK: - 主控台（未選桌時顯示）

struct DashboardView: View {
    var body: some View {
        // 蛋糕訂單＋訂位合併顯示，佔滿全部空間
        CakeOrdersSection()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }
}

// MARK: - 蛋糕訂單 Section（五天並排）

private struct CakeOrdersSection: View {

    @State private var ordersByDate: [String: [CakeOrder]] = [:]
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @ObservedObject private var reservationStore = ReservationStore.shared
    @ObservedObject private var swipeCoordinator = SwipeCoordinator.shared

    // Sheet 統一在此層管理，避免 LazyHStack 銷毀欄位時 sheet 被關掉
    @State private var addReservationPresetDate: Date = Date()
    @State private var showingAddReservation = false
    @State private var editingReservation: Reservation? = nil

    // 預先渲染：今天前3天 ～ 今天後17天，共21欄
    private let startOffset = -3
    private let totalDays   = 21

    private var allDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<totalDays).map { cal.date(byAdding: .day, value: $0 + startOffset, to: today)! }
    }

    private var todayKey: String { key(for: Date()) }

    private func key(for d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    private func label(for d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "MM/dd EEE"
        return f.string(from: d)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    // 標題列
                    HStack(spacing: 12) {

                        Text("蛋糕訂單 ／ 訂位")
                            .font(.headline)
                            .foregroundColor(.peacock)
                        if let err = errorMsg {
                            Text("⚠️ \(err)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if isLoading { ProgressView().scaleEffect(0.8) }
                        Button("今天") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(todayKey, anchor: .leading)
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.peacock)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        Button { Task { await loadOrders() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.peacock)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    let colWidth = geo.size.width / 5
                    // 用內層 GeometryReader 量到欄位的實際可用高度（已扣掉 section header）
                    GeometryReader { colGeo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 0) {
                                ForEach(allDates, id: \.self) { date in
                                    let k = key(for: date)
                                    DayColumn(
                                        dateLabel: label(for: date),
                                        dateKey: k,
                                        orders: ordersByDate[k] ?? [],
                                        reservations: reservationStore.reservations.filter { $0.date == k },
                                        totalHeight: colGeo.size.height,
                                        onAddReservation: { date in
                                            addReservationPresetDate = date
                                            showingAddReservation = true
                                        },
                                        onEditReservation: { r in
                                            editingReservation = r
                                        }
                                    )
                                    .frame(width: colWidth, height: colGeo.size.height)
                                    .id(k)

                                    Rectangle()
                                        .fill(Color.gray.opacity(0.18))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(minHeight: colGeo.size.height, alignment: .top)
                        }
                        .scrollDisabled(swipeCoordinator.isSwiping)
                        .onAppear { proxy.scrollTo(todayKey, anchor: .leading) }
                    }
                }
                .task { await loadOrders() }
                .background(Color.white)
            }
        }
        // Sheet 在最外層，LazyHStack 的欄位滑出畫面也不會關掉
        .sheet(isPresented: $showingAddReservation) {
            AddReservationSheet(presetDate: addReservationPresetDate) { newReservation in
                reservationStore.add(newReservation)
            }
        }
        .sheet(item: $editingReservation) { r in
            EditReservationSheet(reservation: r) { updated in
                reservationStore.update(updated)
            }
        }
    }

    private func loadOrders() async {
        isLoading = true
        errorMsg = nil
        do {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let from = cal.date(byAdding: .day, value: startOffset, to: today)!
            let to   = cal.date(byAdding: .day, value: startOffset + totalDays - 1, to: today)!
            let orders = try await CakeOrderService.shared.fetchOrders(from: from, to: to)
            var grouped: [String: [CakeOrder]] = [:]
            for o in orders { grouped[o.pickupDate, default: []].append(o) }
            ordersByDate = grouped
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 單日欄位

private struct DayColumn: View {
    let dateLabel: String
    let dateKey: String
    let orders: [CakeOrder]
    let reservations: [Reservation]
    let totalHeight: CGFloat
    let onAddReservation: (Date) -> Void
    let onEditReservation: (Reservation) -> Void

    // totalHeight = 欄位實際可用高度（已由 colGeo 量好，不含 section header）
    // 固定元素：日期標題~46 + 細線~1 + 分隔線~1.5 ≈ 49（按鈕是 overlay，不佔 VStack 空間）
    private var cakeHeight: CGFloat {
        max(60, (totalHeight - 49) * 0.44)
    }

    private var presetDate: Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dateKey) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日期標題
            HStack {
                Text(dateLabel)
                    .font(.subheadline.bold())
                    .foregroundColor(.peacock)
                Spacer()
                let total = orders.count + reservations.count
                if total > 0 {
                    Text("\(total) 筆")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.posBg)

            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)

            // 蛋糕訂單區（略低於一半，可捲動）
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(orders) { order in
                        CakeOrderRow(order: order)
                            .background(Color.white)
                        Rectangle().fill(Color.gray.opacity(0.12)).frame(height: 1)
                    }
                }
            }
            .frame(height: cakeHeight)

            // 固定分隔線（貫穿整列，不在 ScrollView 內）
            Rectangle()
                .fill(Color.peacock.opacity(0.35))
                .frame(height: 1.5)

            // 訂位區（可捲動，下半，底部留給按鈕）
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(reservations) { r in
                        ReservationInlineRow(reservation: r, onEdit: onEditReservation)
                    }
                }
                .padding(.bottom, 33)   // 防止最後一筆被按鈕蓋住
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: totalHeight)   // VStack 固定高度，overlay 才能找到正確底部
        // 新增訂位按鈕：overlay 釘在最底部，不受內容高度影響
        .overlay(alignment: .bottom) {
            Button { onAddReservation(presetDate) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("訂位")
                        .font(.caption)
                }
                .foregroundColor(.peacock.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.posBg)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 品項名稱解析（移除選項標題，只保留值）

private func parsedItemName(_ raw: String) -> (main: String, options: String?) {
    // 同時支援半形 () 與全形 （）
    let openChar: Character = raw.contains("（") ? "（" : "("
    let closeChar: Character = raw.contains("）") ? "）" : ")"
    guard let openParen = raw.firstIndex(of: openChar),
          let closeParen = raw.lastIndex(of: closeChar),
          openParen < closeParen else { return (raw, nil) }
    let main = String(raw[raw.startIndex..<openParen]).trimmingCharacters(in: .whitespaces)
    let inner = String(raw[raw.index(after: openParen)..<closeParen])
    // 每段可能是「標題：值」或單純文字，只保留「值」部分
    let parts = inner.components(separatedBy: CharacterSet(charactersIn: "，、,"))
    let values = parts.compactMap { seg -> String? in
        let s = seg.trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: "：") { return String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? nil : s
    }
    let opts = values.joined(separator: "・")
    return (main, opts.isEmpty ? nil : opts)
}

// MARK: - 單筆蛋糕訂單列

private struct CakeOrderRow: View {
    let order: CakeOrder
    @ObservedObject private var pickupStore = CakePickupStore.shared

    private var isConfirmed: Bool { pickupStore.isConfirmed(String(order.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 品項內容，已取貨時疊上左上→右下斜線
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(order.items, id: \.name) { item in
                        let (main, opts) = parsedItemName(item.name)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("• \(main) × \(item.quantity)")
                                .font(.subheadline)
                            if let opts {
                                Text(opts)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(order.customer).foregroundColor(.secondary)
                        Text(order.pickupTime).foregroundColor(.peacock)
                    }
                    .font(.subheadline)
                    if !order.note.isEmpty {
                        Text("備註：\(order.note)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isConfirmed ? 0.35 : 1)

                // 已取貨：左上→右下斜線（對齊內容 padding）
                if isConfirmed {
                    GeometryReader { g in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                        }
                        .stroke(Color.gray.opacity(0.55), lineWidth: 1.2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            }

            // 取貨扁按鈕：未取貨淺綠，已取貨維持原色不變
            Button { pickupStore.toggle(orderId: String(order.id)) } label: {
                Text(isConfirmed ? "已取貨" : "取貨")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isConfirmed ? Color.gray.opacity(0.15) : Color(red: 0.82, green: 0.95, blue: 0.84))
                    .foregroundColor(isConfirmed ? Color.gray : Color(red: 0.18, green: 0.55, blue: 0.28))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 訂位卡片（左滑顯示刪除）

private struct ReservationInlineRow: View {
    let reservation: Reservation
    let onEdit: (Reservation) -> Void
    @ObservedObject private var store = ReservationStore.shared
    @ObservedObject private var swipeCoordinator = SwipeCoordinator.shared
    @State private var swipeOffset: CGFloat = 0
    private let deleteWidth: CGFloat = 70

    private var nameDisplay: String {
        reservation.name + (reservation.title == .none ? "" : " \(reservation.title.rawValue)")
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 底層：刪除按鈕
            Button {
                withAnimation(.easeOut(duration: 0.15)) { swipeOffset = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    store.delete(id: reservation.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // 上層：白色卡片
            VStack(alignment: .leading, spacing: 0) {
                // 文字區（點此進編輯）
                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.time)
                        .font(.subheadline)
                        .foregroundColor(.peacock)
                    Text(nameDisplay)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("大 \(reservation.adults)・小 \(reservation.children)")
                        .font(.subheadline).foregroundColor(.secondary)
                    if !reservation.phone.isEmpty {
                        Text(reservation.phone).font(.caption).foregroundColor(.secondary)
                    }
                    if !reservation.note.isEmpty {
                        Text(reservation.note).font(.caption).foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 7)
                .contentShape(Rectangle())
                .onTapGesture { onEdit(reservation) }

                // 到達 / No Show
                HStack(spacing: 0) {
                    Button {
                        var u = reservation
                        u.status = reservation.status == .arrived ? .pending : .arrived
                        store.update(u)
                    } label: {
                        Text("到達")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(reservation.status == .arrived ? Color.green : Color(white: 0.95))
                            .foregroundColor(reservation.status == .arrived ? .white : Color(white: 0.55))
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(Color(white: 0.88)).frame(width: 1)

                    Button {
                        var u = reservation
                        u.status = reservation.status == .noShow ? .pending : .noShow
                        store.update(u)
                    } label: {
                        Text("No Show")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(reservation.status == .noShow ? Color.red.opacity(0.82) : Color(white: 0.95))
                            .foregroundColor(reservation.status == .noShow ? .white : Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            .offset(x: swipeOffset)
            .highPriorityGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        // 手勢開始時鎖外層水平 ScrollView
                        if !swipeCoordinator.isSwiping {
                            swipeCoordinator.isSwiping = true
                        }
                        if v.translation.width < 0 {
                            swipeOffset = max(v.translation.width, -deleteWidth)
                        } else {
                            swipeOffset = min(0, swipeOffset + v.translation.width)
                        }
                    }
                    .onEnded { v in
                        swipeCoordinator.isSwiping = false
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            swipeOffset = v.translation.width < -(deleteWidth / 2) ? -deleteWidth : 0
                        }
                    }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - 編輯訂位 Sheet（輕量版，只改時間/人數/備註/狀態）

private struct EditReservationSheet: View {
    var reservation: Reservation
    let onSave: (Reservation) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ReservationStore.shared

    @State private var timeDigits: String
    @State private var adults: Int
    @State private var children: Int
    @State private var note: String
    @State private var numPadMode: EditNumPadMode = .time

    enum EditNumPadMode { case time }

    init(reservation: Reservation, onSave: @escaping (Reservation) -> Void) {
        self.reservation = reservation
        self.onSave = onSave
        _timeDigits = State(initialValue: reservation.time.replacingOccurrences(of: ":", with: ""))
        _adults = State(initialValue: reservation.adults)
        _children = State(initialValue: reservation.children)
        _note = State(initialValue: reservation.note)
    }

    private var formattedTime: String {
        let d = timeDigits.prefix(4)
        guard d.count == 4 else { return String(d) }
        return "\(d.prefix(2)):\(d.suffix(2))"
    }

    private var nameDisplay: String {
        reservation.name + (reservation.title == .none ? "" : " \(reservation.title.rawValue)")
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左欄
            VStack(spacing: 0) {
                // 標題
                HStack {
                    Button("取消") { dismiss() }.foregroundColor(.secondary)
                    Spacer()
                    Text(nameDisplay).font(.headline)
                    Spacer()
                    Text("取消").foregroundColor(.clear)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        // 時間（顯示，點右欄操作）
                        HStack {
                            Text("時間").font(.subheadline).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                            Text(timeDigits.isEmpty ? "—" : formattedTime)
                                .font(.subheadline)
                                .foregroundColor(.peacock)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        Divider()

                        // 大人
                        HStack {
                            Text("大人").font(.subheadline).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                            PartyPicker(label: "", value: $adults)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        Divider()

                        // 小孩
                        HStack {
                            Text("小孩").font(.subheadline).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                            PartyPicker(label: "", value: $children)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        Divider()

                        // 備註
                        HStack {
                            Text("備註").font(.subheadline).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                            TextField("選填", text: $note).submitLabel(.done)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        Divider()

                        // 儲存
                        Button {
                            var updated = reservation
                            updated.time = formattedTime
                            updated.adults = adults
                            updated.children = children
                            updated.note = note
                            onSave(updated)
                            dismiss()
                        } label: {
                            Text("儲存")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(timeDigits.count == 4 ? Color.peacock : Color.gray.opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(timeDigits.count != 4)
                        .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)

            Divider()

            // 右欄：時間數字鍵盤
            VStack(spacing: 0) {
                Text("時間")
                    .font(.subheadline.bold())
                    .foregroundColor(.peacock)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.posBg)

                Divider()

                Text(timeDigits.isEmpty ? "—" : formattedTime)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.peacock)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                Divider()

                let keys = ["1","2","3","4","5","6","7","8","9","C","0","⌫"]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(keys, id: \.self) { key in
                        Button { handleTimeKey(key) } label: {
                            Text(key)
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(key == "C" ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                                .foregroundColor(key == "C" ? .red : .primary)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(14)

                Spacer()
            }
            .frame(width: 260)
            .background(Color.white)
        }
    }

    private func handleTimeKey(_ key: String) {
        switch key {
        case "C": timeDigits = ""
        case "⌫":
            if !timeDigits.isEmpty { timeDigits.removeLast() }
        default:
            guard timeDigits.count < 4 else { return }
            let next = timeDigits + key
            switch next.count {
            case 1:
                if let d = Int(key), d <= 2 { timeDigits += key }
            case 2:
                if timeDigits.hasPrefix("2") {
                    if let d = Int(key), d <= 3 { timeDigits += key }
                } else { timeDigits += key }
            case 3:
                if let d = Int(key), d <= 5 { timeDigits += key }
            case 4:
                timeDigits += key
            default: break
            }
        }
    }
}

// MARK: - 訂位資訊 Section

struct ReservationSection: View {
    @ObservedObject private var store = ReservationStore.shared
    @State private var showingAdd = false

    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // 今天起的訂位
    private var upcomingReservations: [Reservation] {
        store.reservations.filter { $0.date >= todayKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            HStack {
                Text("訂位資訊")
                    .font(.headline)
                    .foregroundColor(.peacock)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.peacock)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if upcomingReservations.isEmpty {
                Text("尚無訂位")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(upcomingReservations) { r in
                            ReservationRow(reservation: r)
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddReservationSheet { newReservation in
                store.add(newReservation)
            }
        }
    }
}

// MARK: - 訂位列

private struct ReservationRow: View {
    let reservation: Reservation
    @ObservedObject private var store = ReservationStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(reservation.date.dropFirst(5).replacingOccurrences(of: "-", with: "/"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(reservation.time)
                        .font(.subheadline.bold())
                        .foregroundColor(.peacock)
                }
                Text(reservation.name + (reservation.title == .none ? "" : " \(reservation.title.rawValue)"))
                    .font(.subheadline)
                Text(reservation.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("大人 \(reservation.adults)・小孩 \(reservation.children)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !reservation.note.isEmpty {
                    Text("備註：\(reservation.note)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button {
                store.delete(id: reservation.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - 新增訂位 Sheet（左欄資料 + 右欄數字鍵盤）

private struct AddReservationSheet: View {
    let onSave: (Reservation) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var showDatePicker = false
    @State private var name = ""
    @State private var title: ReservationTitle = .none
    @State private var phone = ""
    @State private var timeDigits = ""
    @State private var adults = 2
    @State private var children = 0
    @State private var note = ""
    @State private var numPadMode: NumPadMode = .phone  // 右欄目前輸入哪個

    enum NumPadMode { case phone, time }

    init(presetDate: Date = Calendar.current.startOfDay(for: Date()), onSave: @escaping (Reservation) -> Void) {
        self.onSave = onSave
        _selectedDate = State(initialValue: presetDate)
        _showDatePicker = State(initialValue: false)
        _name = State(initialValue: "")
        _title = State(initialValue: .none)
        _phone = State(initialValue: "")
        _timeDigits = State(initialValue: "")
        _adults = State(initialValue: 2)
        _children = State(initialValue: 0)
        _note = State(initialValue: "")
        _numPadMode = State(initialValue: .phone)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "MM/dd（EEE）"
        return f.string(from: selectedDate)
    }

    private var dateKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    private var formattedTime: String {
        let d = timeDigits.prefix(4)
        guard d.count == 4 else { return String(d) }
        return "\(d.prefix(2)):\(d.suffix(2))"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        timeDigits.count == 4 &&
        (adults + children) > 0
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── 左欄：所有資料欄位 ──────────────────────────
            VStack(spacing: 0) {
                // 標題列（只有標題 + 取消）
                HStack {
                    Button("取消") { dismiss() }
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("新增訂位")
                        .font(.headline)
                    Spacer()
                    // 佔位讓標題置中
                    Text("取消").foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                    // 日期
                    formRow(label: "日期") {
                        Button {
                            showDatePicker.toggle()
                        } label: {
                            HStack {
                                Text(dateLabel).foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "calendar").foregroundColor(.peacock)
                            }
                        }
                        if showDatePicker {
                            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                        }
                    }

                    Divider()

                    // 姓名 + 稱謂
                    formRow(label: "姓名") {
                        HStack(spacing: 10) {
                            TextField("姓名", text: $name)
                                .submitLabel(.done)
                            ForEach(ReservationTitle.allCases.filter { $0 != .none }, id: \.self) { t in
                                Button(t.rawValue) { title = t }
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(title == t ? Color.peacock : Color.gray.opacity(0.12))
                                    .foregroundColor(title == t ? .white : .primary)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // 電話（點選 → 切換右欄）
                    formRow(label: "電話") {
                        Button {
                            numPadMode = .phone
                        } label: {
                            HStack {
                                Text(phone.isEmpty ? "點此輸入" : phone)
                                    .foregroundColor(phone.isEmpty ? .secondary : .primary)
                                Spacer()
                                if numPadMode == .phone {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .foregroundColor(.peacock)
                                }
                            }
                        }
                    }

                    Divider()

                    // 時間（點選 → 切換右欄）
                    formRow(label: "時間") {
                        Button {
                            numPadMode = .time
                        } label: {
                            HStack {
                                Text(timeDigits.isEmpty ? "點此輸入" : formattedTime)
                                    .foregroundColor(timeDigits.isEmpty ? .secondary : .primary)
                                Spacer()
                                if numPadMode == .time {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .foregroundColor(.peacock)
                                }
                            }
                        }
                    }

                    Divider()

                    // 人數
                    formRow(label: "大人") { PartyPicker(label: "", value: $adults) }
                    Divider()
                    formRow(label: "小孩") { PartyPicker(label: "", value: $children) }
                    Divider()

                    // 備註
                    formRow(label: "備註") {
                        TextField("選填", text: $note)
                            .submitLabel(.done)
                    }

                    Divider()

                    // 儲存按鈕（欄位填完後自然在下方）
                    Button {
                        let r = Reservation(
                            id: UUID(),
                            date: dateKey,
                            time: formattedTime,
                            name: name.trimmingCharacters(in: .whitespaces),
                            title: title,
                            phone: phone,
                            adults: adults,
                            children: children,
                            note: note.trimmingCharacters(in: .whitespaces)
                        )
                        onSave(r)
                        dismiss()
                    } label: {
                        Text("儲存")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.peacock : Color.gray.opacity(0.25))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)

            Divider()

            // ── 右欄：固定數字鍵盤 ──────────────────────────
            VStack(spacing: 0) {
                // 模式切換
                HStack(spacing: 0) {
                    modeTab("電話", active: numPadMode == .phone) { numPadMode = .phone }
                    modeTab("時間", active: numPadMode == .time)  { numPadMode = .time }
                }
                .background(Color.posBg)

                Divider()

                // 目前值顯示
                let currentValue = numPadMode == .phone ? phone : (timeDigits.isEmpty ? "" : formattedTime)
                Text(currentValue.isEmpty ? "—" : currentValue)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.peacock)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                Divider()

                // 數字按鍵
                let keys = ["1","2","3","4","5","6","7","8","9","C","0","⌫"]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(keys, id: \.self) { key in
                        Button { handleKey(key) } label: {
                            Text(key)
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(key == "C" ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                                .foregroundColor(key == "C" ? .red : .primary)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(14)

                Spacer()
            }
            .frame(width: 260)
            .background(Color.white)
        }
        .background(Color.white)
    }

    private func handleKey(_ key: String) {
        switch key {
        case "C":
            if numPadMode == .phone { phone = "" } else { timeDigits = "" }
        case "⌫":
            if numPadMode == .phone {
                if !phone.isEmpty { phone.removeLast() }
            } else {
                if !timeDigits.isEmpty { timeDigits.removeLast() }
            }
        default:
            if numPadMode == .phone {
                if phone.count < 10 { phone += key }
            } else {
                guard timeDigits.count < 4 else { return }
                let next = timeDigits + key
                // 24 小時制驗證：逐位限制
                switch next.count {
                case 1: // 小時十位：0-2
                    if let d = Int(key), d <= 2 { timeDigits += key }
                case 2: // 小時個位：若十位是2，只能0-3；否則0-9
                    if timeDigits.hasPrefix("2") {
                        if let d = Int(key), d <= 3 { timeDigits += key }
                    } else {
                        timeDigits += key
                    }
                case 3: // 分鐘十位：0-5
                    if let d = Int(key), d <= 5 { timeDigits += key }
                case 4: // 分鐘個位：0-9
                    timeDigits += key
                default: break
                }
            }
        }
    }

    @ViewBuilder
    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func modeTab(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(active ? .peacock : .secondary)
                .overlay(
                    Rectangle().frame(height: 2).foregroundColor(active ? .peacock : .clear),
                    alignment: .bottom
                )
        }
    }
}

// MARK: - 人數選擇器（橫排 0–6）

private struct PartyPicker: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...6, id: \.self) { n in
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.subheadline.bold())
                            .frame(width: 34, height: 34)
                            .background(value == n ? Color.peacock : Color.gray.opacity(0.12))
                            .foregroundColor(value == n ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 自訂數字鍵盤 Sheet

private struct NumPadSheet: View {
    let title: String
    let maxDigits: Int
    let initial: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: String = ""

    private var display: String {
        digits.isEmpty ? "—" : digits
    }

    init(title: String, maxDigits: Int, initial: String, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.maxDigits = maxDigits
        self.initial = initial
        self.onConfirm = onConfirm
        _digits = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顯示區
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 24)

            Text(display)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.peacock)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            Divider()

            // 數字按鍵 (1–9, 清除, 0, 退格)
            let keys: [String] = ["1","2","3","4","5","6","7","8","9","C","0","⌫"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        handleKey(key)
                    } label: {
                        Text(key)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(key == "C" ? Color.red.opacity(0.12) : Color.gray.opacity(0.1))
                            .foregroundColor(key == "C" ? .red : .primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(20)

            // 確認
            Button {
                onConfirm(digits)
                dismiss()
            } label: {
                Text("確認")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(digits.isEmpty ? Color.gray.opacity(0.3) : Color.peacock)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(digits.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium])
    }

    private func handleKey(_ key: String) {
        switch key {
        case "C":
            digits = ""
        case "⌫":
            if !digits.isEmpty { digits.removeLast() }
        default:
            if digits.count < maxDigits { digits += key }
        }
    }
}

// MARK: - 分類顏色 Palette（淡色系，8 組）

private let todoCategoryPalette: [(bg: Color, text: Color)] = [
    (Color(red: 0.78, green: 0.93, blue: 0.91), Color(red: 0.10, green: 0.42, blue: 0.40)), // 薄荷綠
    (Color(red: 0.90, green: 0.85, blue: 0.97), Color(red: 0.37, green: 0.21, blue: 0.69)), // 薰衣草紫
    (Color(red: 0.99, green: 0.91, blue: 0.83), Color(red: 0.73, green: 0.35, blue: 0.10)), // 蜜桃橘
    (Color(red: 0.84, green: 0.94, blue: 0.85), Color(red: 0.18, green: 0.49, blue: 0.25)), // 鼠尾草綠
    (Color(red: 0.99, green: 0.85, blue: 0.87), Color(red: 0.72, green: 0.11, blue: 0.22)), // 玫瑰粉
    (Color(red: 0.83, green: 0.91, blue: 0.98), Color(red: 0.08, green: 0.39, blue: 0.67)), // 天空藍
    (Color(red: 0.97, green: 0.96, blue: 0.82), Color(red: 0.48, green: 0.42, blue: 0.04)), // 檸檬黃
    (Color(red: 0.93, green: 0.84, blue: 0.97), Color(red: 0.49, green: 0.12, blue: 0.64)), // 丁香紫
]

private func todoCategoryColors(_ colorIndex: Int) -> (bg: Color, text: Color) {
    todoCategoryPalette[colorIndex % todoCategoryPalette.count]
}

// MARK: - 待辦事項 Section

struct TodoSection: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var showingAdd   = false
    @State private var editingTodo: TodoItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待辦事項")
                    .font(.headline)
                    .foregroundColor(.peacock)
                Spacer()
                Button { showingAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.peacock)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if store.activeItems.isEmpty {
                Text("沒有待辦事項")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                ForEach(store.activeItems) { item in
                    TodoRow(item: item, onEdit: { editingTodo = item })
                    Divider()
                }
            }
        }
        // 新增
        .sheet(isPresented: $showingAdd) {
            TodoEditSheet()
        }
        // 編輯
        .sheet(item: $editingTodo) { item in
            TodoEditSheet(editing: item)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            store.checkRecurring()
        }
        .onAppear { store.checkRecurring() }
    }
}

// MARK: - 待辦列

private struct TodoRow: View {
    let item: TodoItem
    let onEdit: () -> Void
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        HStack(spacing: 10) {
            // 白框勾選框
            Button { store.complete(item) } label: {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.peacock.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .background(Color.white.cornerRadius(4))
            }
            .buttonStyle(.plain)

            // 分類標籤（淡色系）
            if let cat = store.category(for: item.categoryId) {
                let colors = todoCategoryColors(cat.colorIndex)
                Text(cat.name)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(colors.bg)
                    .foregroundColor(colors.text)
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                // 截止日期顯示
                if let rd = item.reminderDate {
                    let f: DateFormatter = {
                        let f = DateFormatter()
                        f.locale = Locale(identifier: "zh_TW")
                        f.dateFormat = "M/d（EEE）"
                        return f
                    }()
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("截止 \(f.string(from: rd))")
                            .font(.caption2)
                    }
                    .foregroundColor(rd < Date() ? .red : Color(red: 0.3, green: 0.55, blue: 0.3))
                }
            }

            Spacer()

            if item.isRecurring {
                Text("\(item.repeatValue)\(item.repeatUnit.rawValue)")
                    .font(.caption2).foregroundColor(.secondary)
                Image(systemName: "repeat")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .contextMenu {
            Button { onEdit() } label: { Label("編輯", systemImage: "pencil") }
            Button(role: .destructive) { store.delete(id: item.id) } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}

// MARK: - 新增／編輯待辦 Sheet

private struct TodoEditSheet: View {
    private let editingItem: TodoItem?
    @ObservedObject private var store = TodoStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title              = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var isRecurring        = false
    @State private var repeatValue        = 1
    @State private var repeatUnit         = TodoRepeatUnit.hours
    @State private var showingAddCategory = false
    @State private var newCategoryName    = ""
    // 日期時間插入
    @State private var showingDatePicker  = false
    @State private var pickerDate         = Date()
    // 截止日期提醒
    @State private var hasReminder        = false
    @State private var reminderDate       = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var showingReminderPicker = false

    init(editing item: TodoItem? = nil) {
        self.editingItem = item
        _title              = State(initialValue: item?.title ?? "")
        _selectedCategoryId = State(initialValue: item?.categoryId)
        _isRecurring        = State(initialValue: item?.isRecurring ?? false)
        _repeatValue        = State(initialValue: item?.repeatValue ?? 1)
        _repeatUnit         = State(initialValue: item?.repeatUnit ?? .hours)
        let rd = item?.reminderDate
        _hasReminder        = State(initialValue: rd != nil)
        _reminderDate       = State(initialValue: rd ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
    }

    private var isEditing: Bool { editingItem != nil }
    private var canSave: Bool   { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private func formattedDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d（EEE）HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 頂部列
            HStack {
                Button("取消") { dismiss() }.foregroundColor(.secondary)
                Spacer()
                Text(isEditing ? "編輯待辦" : "新增待辦").font(.headline)
                Spacer()
                Button("儲存") {
                    let trimmed  = title.trimmingCharacters(in: .whitespaces)
                    let remDate  = hasReminder ? reminderDate : nil
                    if var existing = editingItem {
                        existing.title        = trimmed
                        existing.categoryId   = selectedCategoryId
                        existing.isRecurring  = isRecurring
                        existing.repeatValue  = repeatValue
                        existing.repeatUnit   = repeatUnit
                        existing.reminderDate = remDate
                        store.update(existing)
                    } else {
                        store.add(TodoItem(
                            title: trimmed,
                            categoryId: selectedCategoryId,
                            isRecurring: isRecurring,
                            repeatValue: repeatValue,
                            repeatUnit: repeatUnit,
                            reminderDate: remDate
                        ))
                    }
                    dismiss()
                }
                .foregroundColor(canSave ? .peacock : .secondary)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // 待辦內容
                    formLabel("待辦內容")
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("輸入待辦事項", text: $title, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(3, reservesSpace: false)
                            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

                        // 插入日期時間按鈕
                        Button {
                            pickerDate = Date()
                            showingDatePicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.caption)
                                Text("插入日期時間")
                                    .font(.caption)
                            }
                            .foregroundColor(.peacock.opacity(0.8))
                            .padding(.horizontal, 20).padding(.bottom, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()

                    // 分類標籤
                    formLabel("分類標籤")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip(name: "無", cat: nil)
                            ForEach(store.categories) { cat in
                                categoryChip(name: cat.name, cat: cat)
                            }
                            Button {
                                showingAddCategory = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.caption.bold())
                                    Text("新增分類").font(.caption.bold())
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.secondary)
                                .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    Divider()

                    // 類型 toggle
                    formLabel("類型")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("週期重複提醒").font(.subheadline)
                            Text("勾選後隔一段時間自動重新出現")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isRecurring).labelsHidden()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)

                    // 截止日期提醒
                    Divider()
                    formLabel("截止日期提醒")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("設定截止日期").font(.subheadline)
                            Text("前一天早上 9:00 跳出提醒通知")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $hasReminder).labelsHidden()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)

                    if hasReminder {
                        Button {
                            showingReminderPicker = true
                        } label: {
                            HStack {
                                let f: DateFormatter = {
                                    let f = DateFormatter()
                                    f.locale = Locale(identifier: "zh_TW")
                                    f.dateFormat = "yyyy/M/d（EEE）"
                                    return f
                                }()
                                Image(systemName: "calendar")
                                    .foregroundColor(.peacock)
                                Text(f.string(from: reminderDate))
                                    .font(.subheadline)
                                    .foregroundColor(.peacock)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }

                    if isRecurring {
                        Divider()
                        formLabel("重複間隔")
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 0) {
                                Button { if repeatValue > 1 { repeatValue -= 1 } } label: {
                                    Image(systemName: "minus")
                                        .frame(width: 40, height: 36)
                                        .background(Color.gray.opacity(0.1))
                                }
                                .buttonStyle(.plain)
                                Text("\(repeatValue)")
                                    .font(.subheadline.bold())
                                    .frame(width: 44, height: 36)
                                    .background(Color.white)
                                Button { if repeatValue < 99 { repeatValue += 1 } } label: {
                                    Image(systemName: "plus")
                                        .frame(width: 40, height: 36)
                                        .background(Color.gray.opacity(0.1))
                                }
                                .buttonStyle(.plain)
                            }
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    ForEach(TodoRepeatUnit.allCases, id: \.self) { unit in
                                        Button { repeatUnit = unit } label: {
                                            Text(unit.rawValue)
                                                .font(.subheadline)
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(repeatUnit == unit ? Color.peacock : Color.gray.opacity(0.08))
                                                .foregroundColor(repeatUnit == unit ? .white : .primary)
                                        }
                                        .buttonStyle(.plain)
                                        if unit != TodoRepeatUnit.allCases.last {
                                            Rectangle().fill(Color.gray.opacity(0.18)).frame(width: 1, height: 36)
                                        }
                                    }
                                }
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                    }

                    Divider()
                }
            }
        }
        .background(Color.white)
        // 截止日期 picker
        .sheet(isPresented: $showingReminderPicker) {
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { showingReminderPicker = false }.foregroundColor(.secondary)
                    Spacer()
                    Text("截止日期").font(.headline)
                    Spacer()
                    Button("確定") { showingReminderPicker = false }.foregroundColor(.peacock)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                Divider()
                DatePicker("", selection: $reminderDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                Text("提醒將在前一天早上 9:00 送出")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .presentationDetents([.medium])
        }
        // 插入日期時間的 picker sheet
        .sheet(isPresented: $showingDatePicker) {
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { showingDatePicker = false }.foregroundColor(.secondary)
                    Spacer()
                    Text("選擇日期時間").font(.headline)
                    Spacer()
                    Button("插入") {
                        title += (title.isEmpty ? "" : " ") + formattedDateTime(pickerDate)
                        showingDatePicker = false
                    }
                    .foregroundColor(.peacock)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                Divider()
                DatePicker("", selection: $pickerDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            .presentationDetents([.medium])
        }
        .alert("新增分類", isPresented: $showingAddCategory) {
            TextField("分類名稱", text: $newCategoryName)
            Button("新增") {
                let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.addCategory(name: name) }
                newCategoryName = ""
            }
            Button("取消", role: .cancel) { newCategoryName = "" }
        }
    }

    @ViewBuilder
    private func categoryChip(name: String, cat: TodoCategory?) -> some View {
        let isSelected = selectedCategoryId == cat?.id
        Button { selectedCategoryId = cat?.id } label: {
            if let cat, !isSelected {
                let colors = todoCategoryColors(cat.colorIndex)
                Text(name)
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(colors.bg)
                    .foregroundColor(colors.text)
                    .cornerRadius(20)
            } else {
                Text(name)
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(isSelected ? Color.peacock : Color.gray.opacity(0.1))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(20)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundColor(.secondary)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    }
}
