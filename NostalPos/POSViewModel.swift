//
//  POSViewModel.swift
//  NostalPos
//

import Foundation
import SwiftUI


// 一張訂單的顯示用快照（不影響後端與購物車）
struct TableOrderSnapshot {
    var lines: [CartLine]
    var payMethod: String?
    var isPaid: Bool
}

// 用來顯示桌位訂單 sheet
struct TableSheetInfo: Identifiable, Equatable {
    let id = UUID()
    let tableName: String
}

enum TableStatus {
    case empty       // 無訂單
    case pending     // 尚未結帳（本機 cart 有東西 or 後端 PENDING）
    case completed   // 已結帳（後端 todayOrders 有記錄）
}

@MainActor
class POSViewModel: ObservableObject {

    // MARK: - Table Key Canonicalization
    /// 統一桌名 key：trim + 將「台」統一成「臺」
    /// 目的：避免清桌/搬桌/後端回傳 tableName 的字形差異造成 key 分裂
    private func canonTable(_ table: String) -> String {
        table
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "台", with: "臺")
    }

    /// ✅ 清桌狀態持久化：讓清桌跨重 Run 仍有效
    private func persistClearedTables() {
        ClearedTablesStore.shared.save(clearedTables)
    }

    /// ✅ 清桌復原備份持久化：讓重 build 後仍可復原上一輪明細＋時間
    private func persistUndoBackups() {
        ClearedTablesStore.shared.saveUndoBackups(
            sheetBackups: clearedSheetBackups,
            timerBackups: clearedTimerBackups,
            roundStartBackups: clearedRoundStartBackups
        )
    }

    /// ✅ 啟動時把清桌復原備份載回來
    private func restoreUndoBackupsFromStore() {
        let restored = ClearedTablesStore.shared.loadUndoBackups()
        clearedSheetBackups = restored.sheetBackups
        clearedTimerBackups = restored.timerBackups
        clearedRoundStartBackups = restored.roundStartBackups
    }

    // 是否正在操作某一桌（false = 顯示主控台）
    @Published var isTableActive: Bool = false

    init() {
        // 重開/重 Run 後，還原已清桌桌位（僅影響前端桌位狀態，不會刪除後端訂單）
        self.clearedTables = ClearedTablesStore.shared.load()
        restoreUndoBackupsFromStore()
    }
    
    @MainActor
    func payPendingOrderDebug(for table: String) async {
        let t = canonTable(table)
        if var snap = tableSheetLines[t] {
            snap.isPaid = true
            snap.payMethod = "DEBUG"
            tableSheetLines[t] = snap
        }
    }
    
    private func isSettledStatus(_ status: String?) -> Bool {
        let s = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return s == "PAID" || s == "CLOSED"
    }





    // 後端菜單資料
    @Published var categories: [Category] = []
    @Published var items: [MenuItem] = []
    @Published var categoryAddOns: [CategoryAddOn] = []

    // UI 狀態
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // 今日訂單（從後端抓）
    @Published var todayOrders: [TodayOrderDTO] = []
    @Published var isLoadingTodayOrders: Bool = false
    
    // MARK: - createdAt 快取（只解析一次，供排序/本輪/顯示共用）
    private var createdAtDateCache: [String: Date] = [:]     // key = orderId
    private var createdAtTextCache: [String: String] = [:]   // key = orderId（已格式化後可直接顯示）

    private static let createdAtDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy/MM/dd HH:mm"   // 你若要到秒，改成 "yyyy/MM/dd HH:mm:ss"
        return f
    }()
    
    // ✅ 支援後端 createdAt 為 JS Date 字串：
    // 例：Fri Jan 16 2026 15:21:39 GMT+0800 (台北標準時間)
    private static let jsCreatedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0) // 字串內含 GMT+0800，這裡設 0 即可
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"
        return f
    }()



    // 桌位名稱
    @Published var tableNames: [String] = [
        "吧外","吧2","吧3","吧內",
        "圓窗","圓梯","臺窗","臺二","臺三","臺四",
        "大沙","戶外","矮桌","外帶"
    ]

    @Published var currentTableIndex: Int = 0

    // 👉 改單模式相關
    @Published var isModifyingOrder: Bool = false
    @Published var modifyingOrderId: String? = nil

    // 每桌購物車（前端 cart）
    @Published var tableCarts: [String: [CartLine]] = [:]

    // 每桌今天是否曾經出過單（給你之後要用的話，暫時保留）
    @Published var tableHasHistory: [String: Bool] = [:]

    // 每桌計時器（lazy 建立）
    @Published var tableTimers: [String: TableTimer] = [:]

    // 目前拖曳中的桌位名稱（拖桌位→放到別桌）
    @Published var draggingTableName: String? = nil

    // 桌位訂單 sheet
    @Published var activeTableSheet: TableSheetInfo? = nil

    // 點品項選項 sheet
    @Published var showingOptionsForItem: MenuItem? = nil

    // 分類
    @Published var selectedCategoryId: String? = nil

    // 已清桌的桌位（本機標記：客人離開，下一位使用）
    @Published var clearedTables: Set<String> = []

    // 搬桌中：避免搬桌/同步瞬間被判 empty 造成桌卡閃爍
    @Published var movingTables: Set<String> = []

    // 搬桌落地前：用 orderId 覆寫 tableName，避免 reload 把單又抓回舊桌造成閃/回跳
    @Published var pendingMoveOverrides: [String: String] = [:]   // [orderId: targetTableName]

    // 每桌給 TableOrderSheet 顯示用的明細（不動購物車）
    @Published var tableSheetLines: [String: TableOrderSnapshot] = [:]

    // 今日訂單自動刷新用（每 10 秒）
    private var autoRefreshTodayOrdersTask: Task<Void, Never>?

    // 清桌備份：每一桌一份，直到該桌開始下一輪點餐才清除
    @Published var clearedCartBackups: [String: [CartLine]] = [:]

    // 清桌備份：卡片內容（訂單明細快照）
    @Published var clearedSheetBackups: [String: TableOrderSnapshot] = [:]

    // 清桌時順便備份計時器狀態（經過多久、是否在跑）
    @Published var clearedTimerBackups: [String: (elapsed: TimeInterval, isActive: Bool)] = [:]
    
    // 清桌備份：本輪起點（清桌=結束本輪；復原=回到同一輪）
    @Published var clearedRoundStartBackups: [String: TimeInterval] = [:]

    // 單張 pending：編輯 / 單張結帳時，記住原本那張訂單 id
    @Published var checkoutPendingOrderId: String? = nil

    // 單張 pending 正式編輯模式：改品項 / 改數量 / 改備註時要更新原單
    @Published var editingPendingOrderId: String? = nil

    // 多張 pending 勾選：聯合結帳用
    @Published var selectedPendingOrderIds: Set<String> = []



    // MARK: - 計算屬性 ------------------------------

    var currentTableName: String {
        canonTable(tableNames[currentTableIndex])
    }
    
    
    
    // MARK: - Table Snapshot / Backup helpers (給 View 用，避免 key 分裂)
    /// 讀取此桌的顯示快照（自動 canonicalize key）
    func snapshot(for table: String) -> TableOrderSnapshot? {
        tableSheetLines[canonTable(table)]
    }

    /// 判斷此桌是否存在「清桌復原」備份（自動 canonicalize key）
    func hasUndoClearBackup(for table: String) -> Bool {
        clearedSheetBackups[canonTable(table)] != nil
    }



    func tableTimer(forTable table: String) -> TableTimer {
        let table = canonTable(table)
        if let t = tableTimers[table] {
            return t
        }

        let t = TableTimer()
        tableTimers[table] = t

        // ✅ 新增：嘗試從持久化還原（重 Run / 重開 app 會靠這裡救回來）
        let (savedStart, savedActive) = TableTimerStore.shared.load(table: table)
        if let savedStart {
            let elapsed = Date().timeIntervalSince(savedStart)

            // ✅ 重 build 後，只要這桌還有有效 startTime，就應維持使用中的計時狀態
            // 避免舊的 savedActive=false 把桌卡顯示成灰色
            let shouldBeActive = savedActive || elapsed > 0

            t.restore(elapsed: elapsed, isActive: shouldBeActive)
            t.startTime = savedStart
        }

        return t
    }

    func cart(for table: String) -> [CartLine] {
        tableCarts[canonTable(table)] ?? []
    }

    var currentCart: [CartLine] {
        cart(for: currentTableName)
    }

    var currentTotal: Int {
        currentCart.reduce(0) { $0 + $1.lineTotal }
    }

    var filteredItems: [MenuItem] {
        guard let catId = selectedCategoryId else { return items }
        return items.filter { $0.categoryId == catId }
    }

    // 只清除右邊點單明細（這桌的購物車），不影響計時器等其它狀態
    func clearCurrentCartOnly() {
        let table = canonTable(currentTableName)
        tableCarts[table] = []
    }

    // MARK: - Pending helper (保命線的狀態來源) -----------------------

    /// ✅ 判斷此桌是否「有未結帳(PENDING)」狀態
    /// 規則：優先看 snapshot（最貼近畫面），沒有 snapshot 就看後端今天最後一張單
    /// ✅ 判斷此桌是否「有未結帳(PENDING)」狀態
    /// 規則：
    /// 1) 若有後端資料 → 只看後端最後一張（或任何一張）Status == PENDING
    /// 2) snapshot 只作為顯示，不再用 payMethod 推導 paid（避免不一致）
    func hasPendingOrder(for table: String) -> Bool {
        let t = canonTable(table)

        // ✅ 真相來源只看後端未結帳單
        // status == PENDING 且 payMethod 為空，才算真正 pending
        if ordersForTable(t).contains(where: {
            let st = String($0.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let pm = ($0.payMethod ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return st == "PENDING" && pm.isEmpty
        }) {
            return true
        }

        // ✅ snapshot 保留給 tableStatus(for:) 做畫面顯示，
        // 不再拿來當 pending 真相來源，避免清桌按鈕被誤吃掉
        return false
    }

    
    // MARK: - Cancel Pending Order -----------------------

    /// 取消某桌的 PENDING 訂單（客人臨時取消）
    /// - 行為定義：
    ///   1. 後端：將最後一張 PENDING 訂單標記為 VOID
    ///   2. 前端：
    ///      - 清空 snapshot
    ///      - 清空 cart
    ///      - 停止並清除計時器
    ///      - 桌位正式釋放為 empty
    func cancelPendingOrder(for table: String) {
        let table = canonTable(table)

        guard hasPendingOrder(for: table) else {
            print("⚠️ cancelPendingOrder: \(table) has no pending order")
            return
        }

        // 找出最後一張 PENDING
        guard let lastPending = ordersForTable(table)
            .last(where: { String($0.status ?? "").uppercased() == "PENDING" })
        else {
            print("⚠️ cancelPendingOrder: \(table) pending not found")
            return
        }

        // ✅ 唯一正確：TodayOrderDTO.orderId 是 String（所以不要 guard let）
        let orderId: String = lastPending.orderId
        guard !orderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ cancelPendingOrder: \(table) orderId is empty")
            return
        }


        print("🧨 cancelPendingOrder: table=\(table), orderId=\(orderId)")

        Task { @MainActor in
            do {
                // ✅ 修正：用 APIClient.shared.voidOrder（底層是 deleteOrder）
                let resp = try await APIClient.shared.voidOrder(orderId: orderId)
                let ok = resp.ok ?? false

                guard ok else {
                    print("❌ cancelPendingOrder backend failed: \(resp.error ?? "unknown")")
                    self.errorMessage = "取消訂單失敗，請稍後再試"
                    return
                }

                // 釋放桌位（維持你原本的收斂策略）
                tableSheetLines[table] = nil
                tableCarts[table] = []
                resetStop(for: table)
                loadRoundStartTimesIfNeeded()
                if let ts = roundStartTimes[table] {
                    clearedRoundStartBackups[table] = ts
                }

                clearRoundStart(for: table)

                tableHasHistory[table] = false
                clearedTables.insert(table)
                persistClearedTables()
                persistUndoBackups()

                if canonTable(activeTableSheet?.tableName ?? "") == table {
                    activeTableSheet = nil
                }

                await reloadTodayOrders()

                print("✅ cancelPendingOrder done for \(table)")

            } catch {
                print("❌ cancelPendingOrder error: \(error.localizedDescription)")
                self.errorMessage = "取消訂單失敗：\(error.localizedDescription)"
            }
        }
    }


    // MARK: - 出單前：統一處理桌位計時邏輯 -----------------------

    private func prepareTableTimerBeforePrint(for table: String) {
        let table = canonTable(table)
        // 先確保有 timer
        let timer = tableTimer(forTable: table)

        // 目前記錄：這桌「這一輪」是否已經出過單
        var hasHistory = tableHasHistory[table] ?? false

        // 1️⃣ 如果這桌有被標記為已清桌，代表是「新一輪客人」
        //    → 一律視為沒出過單（新一輪必須重啟時間）
        if clearedTables.contains(table) {
            hasHistory = false
        }
        // 2️⃣ 如果 hasHistory 為 true，但 timer 卻沒有 startTime
        //    → 狀態不一致（例如重開 app）
        //    → 視為新一輪
        else if hasHistory && timer.startTime == nil {
            hasHistory = false
        }

        // 3️⃣ 如果經過上面的校正後，判斷為「這一輪第一次出單」
        if !hasHistory {
            // 如果計時器沒在跑，或雖然有 startTime 但 isActive 為 false，一律重啟
            if timer.startTime == nil || !timer.isActive {
                timer.restart()
            }

            // ✅ 新增：把「這一輪的 startTime」存起來（重 Run 也能算回 elapsed/顏色/離桌時間）
            TableTimerStore.shared.save(
                table: table,
                startTime: timer.startTime,
                isActive: true
            )
            
        


            // 標記這桌「這一輪」已經出過單
            tableHasHistory[table] = true
            
            // ✅ 本輪起點：只在「本輪第一次出單」建立一次（不改啟動點，只補齊原本該做的事）
            ensureRoundStartIfNeeded(for: table, preferred: timer.startTime ?? Date())
            ensureRoundStartIfNeeded(for: table, preferred: timer.startTime ?? Date())
            print("🧭 roundStart after ensure:", roundStartTime(for: table) as Any)
            print("🧭 timer.startTime:", timer.startTime as Any)


            // 出單後一定不是清桌狀態
            clearedTables.remove(table)
            persistClearedTables()
        }
        

    }

    // MARK: - 載入菜單 -----------------------------

    func loadMenu() async {
        isLoading = true
        errorMessage = nil
        do {
            let menu = try await APIClient.shared.fetchMenu()
            categories = menu.categories.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            items = menu.items
            categoryAddOns = menu.categoryAddOns

            if let first = categories.first {
                selectedCategoryId = first.categoryId
            }
        } catch {
            errorMessage = "載入菜單失敗：\(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - 桌位 / 計時器 ------------------------

    func switchTable(_ index: Int) {
        guard tableNames.indices.contains(index) else { return }
        currentTableIndex = index
        _ = tableTimer(forTable: currentTableName)   // 確保有 timer（也會在這裡 restore）
    }

    /// 右下：重新計時（重設並開始倒數）
    func restartTimer(for table: String) {
        let table = canonTable(table)
        let t = tableTimer(forTable: table)
        t.restart()
        // ✅ 同步存
        TableTimerStore.shared.save(table: table, startTime: t.startTime, isActive: t.isActive)
    }

    /// 左下（未啟動）：開始計時
    func startTimer(for table: String) {
        let table = canonTable(table)
        let t = tableTimer(forTable: table)
        t.restart()
        // ✅ 同步存
        TableTimerStore.shared.save(table: table, startTime: t.startTime, isActive: t.isActive)
    }

    /// 左下（已啟動）：歸零並停止（顯示 --:--）
    func resetStop(for table: String) {
        let table = canonTable(table)
        let t = tableTimer(forTable: table)
        t.stop()
        t.startTime = nil        // 清掉開始時間，顯示回 "--:--"
        // ✅ 清掉持久化，避免重開後「詐屍」
        TableTimerStore.shared.clear(table: table)
    }

    func moveTable(from source: String, to target: String) {
        let source = canonTable(source)
        let target = canonTable(target)
        guard !source.isEmpty, !target.isEmpty, source != target else { return }

        Task { @MainActor in
            // 0) 暫停自動刷新，避免搬桌時競態造成閃爍/跳回
            stopAutoRefreshTodayOrders()

            // 1) 搬桌期間只保護目標桌，來源桌要立刻釋放為空桌，不能殘留
            movingTables.remove(source)
            movingTables.insert(target)

            // ✅ 搬桌前先清掉兩桌的「清桌旗標」，避免回跳或被判 empty
            clearedTables.remove(source)
            clearedTables.remove(target)
            persistClearedTables()
            defer {
                movingTables.remove(target)
                startAutoRefreshTodayOrders()
            }

            // 2) 先備份（失敗可回滾）
            let backupTodayOrders = todayOrders

            // ✅ 清桌旗標也要備份（搬桌失敗要能回滾）
            let backupClearedTables = clearedTables
            let backupSourceCart  = tableCarts[source] ?? []
            let backupTargetCart  = tableCarts[target] ?? []
            let backupSourceTimer = tableTimers[source]
            let backupTargetTimer = tableTimers[target]
            let backupSourceSnap  = tableSheetLines[source]
            let backupTargetSnap  = tableSheetLines[target]
            let backupSourceClearedCart = clearedCartBackups[source]
            let backupTargetClearedCart = clearedCartBackups[target]
            let backupSourceClearedTimer = clearedTimerBackups[source]
            let backupTargetClearedTimer = clearedTimerBackups[target]
            let backupSourceClearedRoundStart = clearedRoundStartBackups[source]
            let backupTargetClearedRoundStart = clearedRoundStartBackups[target]
            let backupSourceClearedSheet = clearedSheetBackups[source]
            let backupTargetClearedSheet = clearedSheetBackups[target]
            let wasShowingSheet   = (canonTable(activeTableSheet?.tableName ?? "") == source)

            // ✅ 新增：timer 持久化也要備份（搬桌失敗要能回滾）
            let backupSourcePersist = TableTimerStore.shared.load(table: source)
            let backupTargetPersist = TableTimerStore.shared.load(table: target)

            // 3) 只搬 source 桌「本輪」訂單的 orderIds（不再搬今天全部單）
            let movedIds = roundOrdersForTable(source).map { $0.orderId }

            // ✅ 建立搬桌覆寫：在後端落地完成前，任何 reload 都強制把這些單顯示在 target
            for id in movedIds {
                pendingMoveOverrides[id] = target
            }

            // ========= A) 先做「樂觀更新」：UI 立刻搬過去 =========

            // A1) 今日訂單：立刻把 movedIds 的 tableName 換成 target
            if !movedIds.isEmpty {
                todayOrders = todayOrders.map { o in
                    if movedIds.contains(o.orderId) {
                        return TodayOrderDTO(
                            orderId: o.orderId,
                            createdAt: o.createdAt,
                            tableName: target,
                            payMethod: o.payMethod,
                            amount: o.amount,
                            note: o.note,
                            status: o.status,
                            items: o.items
                        )
                    }
                    return o
                }
            }

            // A2) 本機購物車：source → target（語意：整桌搬過去）
            if !backupSourceCart.isEmpty {
                var dst = backupTargetCart
                dst.append(contentsOf: backupSourceCart)
                tableCarts[target] = dst
            }
            tableCarts[source] = []

            // A3) timer：source → target（若 target 原本有 timer，以 source 覆蓋）
            if let t = backupSourceTimer {
                tableTimers[target] = t
                tableTimers[source] = nil

                // ✅ 同步搬移「持久化 timer」
                if let sStart = backupSourcePersist.startTime {
                    TableTimerStore.shared.save(table: target, startTime: sStart, isActive: backupSourcePersist.isActive)
                } else {
                    TableTimerStore.shared.clear(table: target)
                }
                TableTimerStore.shared.clear(table: source)
            }

            // ✅ roundStart 也要一起搬（本輪切割一致）
            moveRoundStart(from: source, to: target)

            // ✅ 搬到 target 後，target 不能再保留舊的清桌復原備份
            clearedCartBackups[target] = nil
            clearedTimerBackups[target] = nil
            clearedRoundStartBackups[target] = nil
            clearedSheetBackups[target] = nil

            // A4) 訂單明細快照：優先搬 source snapshot；若沒有就依搬完後的 target 本輪即時重建
            if let snap = backupSourceSnap {
                tableSheetLines[target] = snap
            } else {
                tableSheetLines[target] = makeSnapshotFromRoundOrders(for: target)
            }
            tableSheetLines[source] = nil

            // A5) 若明細正在看 source，立刻切到 target（畫面不中斷）
            if wasShowingSheet {
                activeTableSheet = TableSheetInfo(tableName: target)
            }

            // A6) 拖曳收尾
            draggingTableName = nil

            // ✅ A7) 來源桌位要立刻變空桌：清掉所有「讓它看起來有單」的狀態
            clearedTables.insert(source)
            clearedTables.remove(target)
            persistClearedTables()
            tableHasHistory[source] = false
            clearedCartBackups[source] = nil
            clearedTimerBackups[source] = nil
            clearedRoundStartBackups[source] = nil
            clearedSheetBackups[source] = nil
            persistUndoBackups()

            // 來源桌已搬空：確保這些也乾淨（防止 tableStatus 誤判）
            tableSheetLines[source] = nil
            tableCarts[source] = []
            tableTimers[source] = nil

            // ========= B) 再做「後端落地」：讓 Spreadsheet 真正搬桌 =========

            // 若這桌其實沒有本輪後端訂單（純本機），就不必打後端
            let sourceHasBackend = !movedIds.isEmpty

            guard sourceHasBackend else {
                return
            }

            do {
                let resp = try await APIClient.shared.moveTable(source: source, target: target)
                let ok = (resp.ok ?? false)
                let updated = resp.updated ?? 0

                guard ok, updated > 0 else {
                    print("❌ moveTable backend failed/no-op: \(resp.error ?? "unknown")")
                    if let raw = resp.rawText { print("🧾 moveTable raw: \(raw)") }

                    for id in movedIds {
                        if pendingMoveOverrides[id] == target {
                            pendingMoveOverrides.removeValue(forKey: id)
                        }
                    }

                    todayOrders = backupTodayOrders
                    tableCarts[source] = backupSourceCart
                    tableCarts[target] = backupTargetCart
                    tableTimers[source] = backupSourceTimer
                    tableTimers[target] = backupTargetTimer
                    tableSheetLines[source] = backupSourceSnap
                    tableSheetLines[target] = backupTargetSnap
                    clearedCartBackups[source] = backupSourceClearedCart
                    clearedCartBackups[target] = backupTargetClearedCart
                    clearedTimerBackups[source] = backupSourceClearedTimer
                    clearedTimerBackups[target] = backupTargetClearedTimer
                    clearedRoundStartBackups[source] = backupSourceClearedRoundStart
                    clearedRoundStartBackups[target] = backupTargetClearedRoundStart
                    clearedSheetBackups[source] = backupSourceClearedSheet
                    clearedSheetBackups[target] = backupTargetClearedSheet
                    if wasShowingSheet {
                        activeTableSheet = TableSheetInfo(tableName: source)
                    }

                    persistUndoBackups()

                    if let ss = backupSourcePersist.startTime {
                        TableTimerStore.shared.save(table: source, startTime: ss, isActive: backupSourcePersist.isActive)
                    } else {
                        TableTimerStore.shared.clear(table: source)
                    }
                    if let ts = backupTargetPersist.startTime {
                        TableTimerStore.shared.save(table: target, startTime: ts, isActive: backupTargetPersist.isActive)
                    } else {
                        TableTimerStore.shared.clear(table: target)
                    }

                    return
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await reloadTodayOrders()

                    for id in movedIds {
                        if pendingMoveOverrides[id] == target {
                            pendingMoveOverrides.removeValue(forKey: id)
                        }
                    }
                }

            } catch {
                print("❌ moveTable backend error: \(error.localizedDescription)")

                for id in movedIds {
                    if pendingMoveOverrides[id] == target {
                        pendingMoveOverrides.removeValue(forKey: id)
                    }
                }

                todayOrders = backupTodayOrders
                tableCarts[source] = backupSourceCart
                tableCarts[target] = backupTargetCart
                tableTimers[source] = backupSourceTimer
                tableTimers[target] = backupTargetTimer
                tableSheetLines[source] = backupSourceSnap
                tableSheetLines[target] = backupTargetSnap
                clearedCartBackups[source] = backupSourceClearedCart
                clearedCartBackups[target] = backupTargetClearedCart
                clearedTimerBackups[source] = backupSourceClearedTimer
                clearedTimerBackups[target] = backupTargetClearedTimer
                clearedRoundStartBackups[source] = backupSourceClearedRoundStart
                clearedRoundStartBackups[target] = backupTargetClearedRoundStart
                clearedSheetBackups[source] = backupSourceClearedSheet
                clearedSheetBackups[target] = backupTargetClearedSheet
                if wasShowingSheet {
                    activeTableSheet = TableSheetInfo(tableName: source)
                }

                clearedTables = backupClearedTables
                persistClearedTables()
                persistUndoBackups()

                if let ss = backupSourcePersist.startTime {
                    TableTimerStore.shared.save(table: source, startTime: ss, isActive: backupSourcePersist.isActive)
                } else {
                    TableTimerStore.shared.clear(table: source)
                }
                if let ts = backupTargetPersist.startTime {
                    TableTimerStore.shared.save(table: target, startTime: ts, isActive: backupTargetPersist.isActive)
                } else {
                    TableTimerStore.shared.clear(table: target)
                }
            }
        }
    }

    // MARK: - 購物車 -------------------------------

    func addToCart(_ line: CartLine) {
        var list = tableCarts[currentTableName] ?? []

        // ⏰ 如果這桌目前是空的，代表是新的一輪點餐
        //    → 把這桌舊的清桌備份清掉（不能再復原上一輪）
        if list.isEmpty {
            clearedCartBackups[currentTableName] = nil
            clearedSheetBackups[currentTableName] = nil
            clearedTimerBackups[currentTableName] = nil
            clearedRoundStartBackups[currentTableName] = nil
            persistUndoBackups()
        }

        list.append(line)
        tableCarts[currentTableName] = list

        // 有新點單，這桌一定不是清桌
        clearedTables.remove(currentTableName)
        persistClearedTables()

        // 計時器：第一次出單時再處理
    }

    // ✅ 新增：覆蓋購物車某一筆（用於「點購物車品項→重新選選項」）
    func updateCartLine(old: CartLine, new: CartLine, in table: String) {
        let table = canonTable(table)
        guard var list = tableCarts[table] else { return }
        guard let idx = list.firstIndex(where: { $0.id == old.id }) else { return }

        list[idx] = new
        tableCarts[table] = list
    }

    func clearCart(for table: String) {
        let table = canonTable(table)
        let current = tableCarts[table] ?? []
        clearedCartBackups[table] = current
        print("🧹 clearCart：\(table)，備份 \(current.count) 筆（只來自 cart）")
        tableCarts[table] = []
    }

    /// 內部：修改某桌某一行的數量（delta 可以是 +1 或 -1）
    private func changeQuantity(of line: CartLine, by delta: Int, in table: String) {
        let table = canonTable(table)
        guard var list = tableCarts[table] else { return }
        guard let idx = list.firstIndex(where: { $0.id == line.id }) else { return }

        var target = list[idx]
        let newQty = target.quantity + delta

        if newQty <= 0 {
            list.remove(at: idx)
        } else {
            target.quantity = newQty
            list[idx] = target
        }
        tableCarts[table] = list
    }

    /// 數量 +1
    func incrementLine(_ line: CartLine, in table: String) {
        changeQuantity(of: line, by: 1, in: table)
    }

    /// 數量 -1（若到 0 會自動刪掉）
    func decrementLine(_ line: CartLine, in table: String) {
        changeQuantity(of: line, by: -1, in: table)
    }

    // MARK: - 建立訂單 & 出單 -----------------------

    /// 把某桌的 CartLine 轉成 OrderRequest（給出單機）
    private func makeOrderRequest(for table: String, payMethod: String) -> OrderRequest? {
        let table = canonTable(table)
        let cart = tableCarts[table] ?? []
        guard !cart.isEmpty else { return nil }

        let backendItems: [OrderItem] = cart.map { line in
            let qty = line.quantity
            let unitPrice = qty > 0 ? line.lineTotal / qty : line.lineTotal
            return OrderItem(name: line.displayName, price: unitPrice, qty: qty)
        }

        let amount = cart.reduce(0) { $0 + $1.lineTotal }
        let note = "桌位：\(table)"          // PrinterManager 會從 note 裡抓桌位

        let order = OrderRequest(
            orderId: UUID().uuidString,
            amount: amount,
            items: backendItems,
            payMethod: payMethod,
            note: note,
            transactionId: nil,
            tableName: table
        )
        return order
    }

    func printOrder(for table: String, payMethod: String = "現金") {
        let table = canonTable(table)
        let cart = tableCarts[table] ?? []
        guard !cart.isEmpty else { return }

        let amount = cart.reduce(0) { $0 + $1.lineTotal }

        // ✅ 在出單前，統一處理「這一輪是不是第一次出單」＋「計時器要不要啟動」
        prepareTableTimerBeforePrint(for: table)

        // 出單
        PrinterManager.shared.printReceiptForCart(
            cart: cart,
            tableName: table,
            payMethod: payMethod,
            amount: amount
        )

        // 這裡還是保留今天有出過單的標記（給你之後如果其他地方要用）
        tableHasHistory[table] = true
        // 有出單就代表桌位重新被使用，不再視為已清桌
        clearedTables.remove(table)
        persistClearedTables()
    }

    /// ✅ 重印：不依賴購物車；優先用 tableSheetLines 快照，沒有才用後端最後一張訂單
    func reprintOrder(for table: String) {
        let table = canonTable(table)
        // 1) 先用顯示快照（你現在 TableOrderSheet 就是靠這個顯示）
        if let snap = tableSheetLines[table], !snap.lines.isEmpty {
            let amount = snap.lines.reduce(0) { $0 + $1.lineTotal }
            let pm = snap.payMethod ?? "現金"

            print("🧾 [REPRINT] table=\(table) source=snapshot lines=\(snap.lines.count) amount=\(amount) pay=\(pm)")

            PrinterManager.shared.printReceiptForCart(
                cart: snap.lines,
                tableName: table,
                payMethod: pm,
                amount: amount
            )
            return
        }

        // 2) 沒快照就退回用後端最後一張訂單
        if let last = ordersForTable(table).last {
            let lines = makeCartLines(from: last)
            guard !lines.isEmpty else {
                print("🧾 [REPRINT] table=\(table) source=backend lastOrder but lines empty")
                return
            }

            let amount = lines.reduce(0) { $0 + $1.lineTotal }
            let pm = last.payMethod ?? "現金"

            print("🧾 [REPRINT] table=\(table) source=backend lines=\(lines.count) amount=\(amount) pay=\(pm)")

            PrinterManager.shared.printReceiptForCart(
                cart: lines,
                tableName: table,
                payMethod: pm,
                amount: amount
            )
            return
        }

        print("🧾 [REPRINT] table=\(table) no snapshot and no backend order -> skip")
    }


    /// 清空目前桌位的點單（給結帳後用，不等於客人離開）
    func clearcurrentCart(for table: String) {
        let table = canonTable(table)
        // 先把現在這桌的購物車內容存起來
        let current = tableCarts[table] ?? []
        clearedCartBackups[table] = current

        // 再清空購物車
        tableCarts[table] = []

        // ❗不要在這裡動計時 / todayOrders，單純只把「這一輪桌邊點單」清掉
    }


    /// 你的流程：清桌後桌卡變空、計時歸零；但會出現垃圾桶可復原「卡片內容＋計時」
    func clearTableForNextGuest(_ table: String) {
        let table = canonTable(table)

        // ✅ 保命線：只要桌上有 PENDING，禁止清桌釋放（方案 A）
        if hasPendingOrder(for: table) {
            errorMessage = "此桌尚未結帳，請先結帳"
            return
        }

        // 0) 先備份「卡片內容」：優先用 snapshot（最符合畫面當下）
        if let snap = tableSheetLines[table], !snap.lines.isEmpty {
            clearedSheetBackups[table] = snap
        } else if let roundSnapshot = makeSnapshotFromRoundOrders(for: table) {
            clearedSheetBackups[table] = roundSnapshot
        } else {
            // 真的完全沒有資料就不要備份（垃圾桶也不該出現）
            clearedSheetBackups[table] = nil
        }

        // 1) 備份計時器狀態（你原本這段保留）
        let t = tableTimer(forTable: table)
        clearedTimerBackups[table] = (elapsed: t.elapsed, isActive: t.isActive)

        // 1.5) 備份本輪起點：復原時要能回到同一輪
        loadRoundStartTimesIfNeeded()
        if let ts = roundStartTimes[table] {
            clearedRoundStartBackups[table] = ts
        } else if let start = t.startTime {
            clearedRoundStartBackups[table] = start.timeIntervalSince1970
        } else {
            clearedRoundStartBackups.removeValue(forKey: table)
        }

        // 2) 清空本機點單 cart（這裡不再用 clearCart(for:) 的「只備份 cart」邏輯）
        tableCarts[table] = []

        // 3) 清空計時器顯示（這裡會順便 clear 持久化）
        resetStop(for: table)

        clearRoundStart(for: table)

        // 4) 這輪結束：相關狀態歸零
        tableHasHistory[table] = false
        clearedTables.insert(table)
        persistClearedTables()

        // 5) 卡片明細清掉（桌卡變空）
        tableSheetLines[table] = nil

        // 6) 關閉 sheet（回主畫面）
        activeTableSheet = nil

        // 7) 持久化清桌復原備份，讓重 build 後仍可復原上一輪
        persistUndoBackups()
    }

    /// 清桌復原：把「卡片快照 + 計時 + 本輪狀態」完整復原回來（不改後端訂單）
    func undoClearTable(for table: String) {
        let table = canonTable(table)
        guard let snap = clearedSheetBackups[table], !snap.lines.isEmpty else {
            print("🔄 undoClearTable：\(table) 沒有卡片備份")
            return
        }

        // 1) 還原卡片顯示內容
        tableSheetLines[table] = snap

        // 2) 解除清桌狀態（垃圾桶消失、桌卡回到有單狀態）
        clearedTables.remove(table)
        persistClearedTables()

        // 3) 這桌仍屬於同一輪
        tableHasHistory[table] = true

        // 4) 還原本輪起點；若沒有 roundStart 備份，後面再用 timer backup 反推
        loadRoundStartTimesIfNeeded()
        var restoredStartDate: Date? = nil
        if let ts = clearedRoundStartBackups[table] {
            roundStartTimes[table] = ts
            persistRoundStartTimes()
            restoredStartDate = Date(timeIntervalSince1970: ts)
        }

        // 5) 還原計時器：有明細可復原時，桌卡就應回到使用中，不應維持灰色
        let t = tableTimer(forTable: table)
        if let timerBackup = clearedTimerBackups[table] {
            let effectiveStart: Date
            if let restoredStartDate {
                effectiveStart = restoredStartDate
            } else if let currentStart = t.startTime {
                effectiveStart = currentStart
            } else if timerBackup.elapsed > 0 {
                effectiveStart = Date().addingTimeInterval(-timerBackup.elapsed)
            } else {
                effectiveStart = Date()
            }

            let effectiveElapsed = max(timerBackup.elapsed, Date().timeIntervalSince(effectiveStart), 0)
            t.restore(elapsed: effectiveElapsed, isActive: true)
            t.startTime = effectiveStart

            if restoredStartDate == nil {
                let ts = effectiveStart.timeIntervalSince1970
                roundStartTimes[table] = ts
                persistRoundStartTimes()
            }

            TableTimerStore.shared.save(table: table, startTime: effectiveStart, isActive: true)
        } else if let restoredStartDate {
            let elapsed = max(0, Date().timeIntervalSince(restoredStartDate))
            t.restore(elapsed: elapsed, isActive: true)
            t.startTime = restoredStartDate
            TableTimerStore.shared.save(table: table, startTime: restoredStartDate, isActive: true)
        }

        // 6) 清掉備份（避免重複復原）
        clearedSheetBackups[table] = nil
        clearedTimerBackups[table] = nil
        clearedRoundStartBackups[table] = nil
        persistUndoBackups()
    }



    /// 回傳這桌目前的狀態：空桌 / 未結帳 / 已結帳
    func tableStatus(for table: String) -> TableStatus {
        let table = canonTable(table)

        // ✅ 0️⃣ 搬桌中：強制視為「非空桌」，避免 UI 因 empty 直接把卡片移除造成閃爍
        if movingTables.contains(table) {
            if let snap = tableSheetLines[table] {
                return snap.isPaid ? .completed : .pending
            }
            return .pending
        }

        // ✅ 1️⃣ 先看「後端/快照是否 PENDING」：這是保命線的狀態來源
        if hasPendingOrder(for: table) {
            if clearedTables.contains(table) {
                clearedTables.remove(table)
                persistClearedTables()
            }
            return .pending
        }

        // ✅ 2️⃣ snapshot 最準確：即使被 cleared，也不能把 snapshot 蓋掉（避免狀態炸裂）
        if let snap = tableSheetLines[table] {
            return snap.isPaid ? .completed : .pending
        }

        // ✅ 3️⃣ cart 有東西 → 尚未結帳（同樣不能被 cleared 蓋掉）
        if let cart = tableCarts[table], !cart.isEmpty {
            return .pending
        }

        // ✅ 4️⃣ 使用者曾手動清桌：若此時桌上沒有 snapshot/cart/pending
        //    → 才視為空桌（你原本要的「清桌遮住已結帳」效果仍保留）
        if clearedTables.contains(table) {
            return .empty
        }

    
        // 5️⃣ 看「本輪」訂單：以最後一張為準
        if let order = roundOrdersForTable(table).last {
            let pm = (order.payMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let paid = !pm.isEmpty || isSettledStatus(order.status)   // ✅ 有付款方式就視為已結帳（只影響顯示狀態）
            return paid ? .completed : .pending
        }




        // 6️⃣ 以上皆無 → 空桌
        return .empty
    }
    
    // ✅ 本輪起點（業務定義）獨立於 timer：避免 resetStop / restore / 重建 timer 導致本輪消失
    private let roundStartStoreKey = "NostalPos.roundStartTimes.v1"
    private var roundStartTimes: [String: TimeInterval] = [:]
    private var didLoadRoundStartTimes = false

    private func loadRoundStartTimesIfNeeded() {
        guard !didLoadRoundStartTimes else { return }
        didLoadRoundStartTimes = true
        if let dict = UserDefaults.standard.dictionary(forKey: roundStartStoreKey) as? [String: TimeInterval] {
            roundStartTimes = dict
        }
    }

    private func persistRoundStartTimes() {
        UserDefaults.standard.set(roundStartTimes, forKey: roundStartStoreKey)
    }

    /// 本輪起點：優先用 roundStart（穩定），fallback 才用 timer.startTime（兼容舊狀態）
    func roundStartTime(for table: String) -> Date? {
        let t = canonTable(table)
        loadRoundStartTimesIfNeeded()

        guard let ts = roundStartTimes[t] else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
    
    @MainActor
    func markRoundStartOnFirstCommittedOrder(for table: String, committedAt: Date) {
        // 只在不存在時建立；存在就不動（符合「只寫一次」）
        ensureRoundStartIfNeeded(for: table, preferred: committedAt)
    }


    /// 本輪開始：只在尚未存在 roundStart 時才建立（不會被加點/結帳改寫）
    private func ensureRoundStartIfNeeded(for table: String, preferred: Date? = nil) {
        let t = canonTable(table)
        loadRoundStartTimesIfNeeded()
        if roundStartTimes[t] != nil { return }

        let d = preferred ?? Date()
        roundStartTimes[t] = d.timeIntervalSince1970
        persistRoundStartTimes()
    }

    /// 本輪結束（清桌/下一位）：清除 roundStart
    private func clearRoundStart(for table: String) {
        let t = canonTable(table)
        loadRoundStartTimesIfNeeded()
        roundStartTimes.removeValue(forKey: t)
        persistRoundStartTimes()
    }

    /// 搬桌時：roundStart 也要一起搬（避免本輪切割錯桌）
    private func moveRoundStart(from source: String, to target: String) {
        let s = canonTable(source)
        let t = canonTable(target)
        loadRoundStartTimesIfNeeded()

        if let ts = roundStartTimes[s] {
            roundStartTimes[t] = ts
            roundStartTimes.removeValue(forKey: s)
            persistRoundStartTimes()
        }
    }

    // MARK: - Round (本輪) Helpers

    func parseOrderDate(_ raw: String) -> Date {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .distantPast }

        // ✅ 先去掉尾端括號內容： " ... GMT+0800 (台北標準時間)" → " ... GMT+0800"
        if let i = s.firstIndex(of: "(") {
            s = String(s[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // ✅ 優先嘗試解析 JS Date 格式（你目前後端回的就是這種）
        if let d = Self.jsCreatedAtFormatter.date(from: s) {
            return d
        }



        // 1️⃣ 純數字：UNIX timestamp（秒 or 毫秒）
        if let n = Double(s) {
            if n > 1_000_000_000_000 {   // 毫秒
                return Date(timeIntervalSince1970: n / 1000)
            } else if n > 1_000_000_000 { // 秒
                return Date(timeIntervalSince1970: n)
            }

            // 2️⃣ Google Sheets 日期序列值（天數）
            if n > 30_000 { // 約 1982 年之後
                // Google Sheets 的 0 = 1899-12-30
                let base = Date(timeIntervalSince1970: -2209161600)
                return base.addingTimeInterval(n * 86400)
            }
        }

        // 3️⃣ ISO 8601（含毫秒 / Z）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) {
            return d
        }
        let iso2 = ISO8601DateFormatter()
        if let d = iso2.date(from: s) {
            return d
        }

        // 4️⃣ 明確格式清單（本地時間）
        let fmts = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm"
        ]

        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = f
            if let d = df.date(from: s) {
                return d
            }
        }

        // 5️⃣ 最後保底：回 distantPast（但「有 Date」，不再是 nil）
        return .distantPast
    }
    
    // MARK: - createdAt cache accessors

    /// 取得此訂單的 createdAt Date（若快取沒有就解析一次並寫入快取）
    func createdAtDate(for order: TodayOrderDTO) -> Date {
        if let cached = createdAtDateCache[order.orderId] { return cached }
        let d = parseOrderDate(order.createdAt)
        createdAtDateCache[order.orderId] = d
        createdAtTextCache[order.orderId] = Self.createdAtDisplayFormatter.string(from: d)
        return d
    }

    /// 取得此訂單的顯示用時間字串（不再在 UI 端各自解析）
    func createdAtText(for order: TodayOrderDTO) -> String {
        if let cached = createdAtTextCache[order.orderId] { return cached }
        _ = createdAtDate(for: order) // 會順便把文字快取補齊
        return createdAtTextCache[order.orderId] ?? "-"
    }


    /// 本輪訂單（不再用「本桌今日所有訂單」）
    func roundOrdersForTable(_ table: String) -> [TodayOrderDTO] {
        let t = canonTable(table)
        let all = todayOrders.filter { ($0.status ?? "") != "VOID" && canonTable($0.tableName) == t }

        guard let start = roundStartTime(for: t) else {
            // 沒有 startTime => 視為尚未開始本輪（或已清桌）
            return []
        }
        
        // 🔎 Debug：本輪為何被刷掉（用 VM 快取，不會重複解析）
        if !all.isEmpty {
            let ds = all.map { createdAtDate(for: $0) }.sorted()
            print("🧪 roundOrdersForTable",
                  "table:", t,
                  "start:", start,
                  "count:", all.count,
                  "earliest:", ds.first as Any,
                  "latest:", ds.last as Any)

            // 只印最多 6 筆，避免 console 炸裂
            for o in all.prefix(6) {
                let d = createdAtDate(for: o)
                print("   • id:", o.orderId,
                      "raw:", o.createdAt,
                      "parsed:", d,
                      "keep:", d >= start)
            }
        } else {
            print("🧪 roundOrdersForTable table:", t, "all=0 (no orders matched table/status filter)")
        }


        return all.filter { o in
            let d = createdAtDate(for: o)
            return d >= start
        }


    }

   

    private func isPendingOrder(_ o: TodayOrderDTO) -> Bool {
        let pm = (o.payMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !pm.isEmpty { return false }
        let st = (o.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return st == "PENDING"
    }


    /// 本輪「最後活動時間」：給桌位排序用
    func lastActivityTime(for table: String) -> Date {
        let t = canonTable(table)

        // 1) 本輪最後一張訂單時間
        let orders = roundOrdersForTable(t)
        if let maxOrderDate = orders.map({ createdAtDate(for: $0) }).max() {
            return maxOrderDate
        }


        // 2) 桌上有 cart 或 snapshot，至少用本輪開始時間當作活動時間
        if let snap = tableSheetLines[t], !snap.lines.isEmpty {
            return tableTimer(forTable: t).startTime ?? Date.distantPast
        }
        if let cart = tableCarts[t], !cart.isEmpty {
            return tableTimer(forTable: t).startTime ?? Date()
        }

        return Date.distantPast
    }

    /// 桌位排序：由新到舊
    func sortedTableNamesByRecent() -> [String] {
        // tie-break：保留你原本 tableNames 的相對順序，避免排序抖動
        let baseIndex: [String: Int] = Dictionary(uniqueKeysWithValues: tableNames.enumerated().map { ($0.element, $0.offset) })

        return tableNames.sorted { a, b in
            let da = lastActivityTime(for: a)
            let db = lastActivityTime(for: b)
            if da != db { return da > db }
            return (baseIndex[a] ?? 0) < (baseIndex[b] ?? 0)
        }
    }



    /// 判斷這桌現在是否「有訂單」（給桌位卡片小圓點用）
    func tableHasOrder(_ table: String) -> Bool {
        switch tableStatus(for: table) {
        case .empty:
            return false
        case .pending, .completed:
            return true
        }
    }

    // MARK: - 從後端訂單產生本機 cart line -----------------------

    /// 把一張 TodayOrderDTO 轉成 CartLine 陣列（給顯示 / 改單用）
    private func makeCartLines(from order: TodayOrderDTO) -> [CartLine] {
        var newLines: [CartLine] = []

        for itemDTO in order.items {
            // 先用名稱 + 價格找對應的 MenuItem
            let matchedMenuItem =
                items.first(where: { $0.name == itemDTO.name && $0.price == itemDTO.price })
                ?? items.first(where: { $0.name == itemDTO.name })

            let menuItem: MenuItem

            if let m = matchedMenuItem {
                menuItem = m
            } else {
                // 找不到就做一個臨時的 MenuItem（名字＆價格正確，其他先空）
                menuItem = MenuItem(
                    itemId: "history-\(UUID().uuidString)",
                    categoryId: "",
                    name: itemDTO.name,
                    price: itemDTO.price,
                    allowOat: false,
                    addOns: nil
                )
            }

            // ⚠️ 從歷史訂單回來，目前拿不到溫度/甜度，只能先給預設
            let line = CartLine(
                item: menuItem,
                quantity: itemDTO.qty,
                temperature: .none,
                sweetness: nil,
                isOatMilk: false,
                isRefill: false,
                isEcoCup: false,
                isTakeawayAfterMeal: false,
                needsCutlery: false
            )

            newLines.append(line)
        }

        return newLines
    }

    /// 只用「本輪訂單」建立當前桌位快照；沒有本輪就回 nil
    private func makeSnapshotFromRoundOrders(for table: String) -> TableOrderSnapshot? {
        let t = canonTable(table)
        let roundOrders = roundOrdersForTable(t)

        guard !roundOrders.isEmpty else { return nil }

        let sortedOrders = roundOrders.sorted { a, b in
            let da = createdAtDate(for: a)
            let db = createdAtDate(for: b)
            return da > db
        }

        var mergedLines: [CartLine] = []
        for order in sortedOrders {
            mergedLines.append(contentsOf: makeCartLines(from: order))
        }

        guard !mergedLines.isEmpty else { return nil }

        let lastPayMethod = roundOrders.reversed().first(where: { !($0.payMethod ?? "").isEmpty })?.payMethod
        let allSettled = roundOrders.allSatisfy { isSettledStatus($0.status) || !((($0.payMethod ?? "")).isEmpty) }

        return TableOrderSnapshot(
            lines: mergedLines,
            payMethod: lastPayMethod,
            isPaid: allSettled
        )
    }

    /// 提供給畫面顯示用：把後端 TodayOrderDTO 轉成 CartLine 陣列
    /// 不會動到 tableCarts，只是單純轉換一次。
    func cartLinesForDisplay(from order: TodayOrderDTO) -> [CartLine] {
        return makeCartLines(from: order)
    }

    // MARK: - 改單模式：把今日訂單灌回購物車 -----------------------

    private func clearPendingCheckoutContext() {
        checkoutPendingOrderId = nil
        editingPendingOrderId = nil
        selectedPendingOrderIds.removeAll()
    }

    func finishPendingEditing(clearCart: Bool = true) {
        isModifyingOrder = false
        modifyingOrderId = nil
        clearPendingCheckoutContext()
        if clearCart {
            clearCurrentCartOnly()
        }
    }

    func cancelCombinedPendingCheckout(clearCart: Bool = true) {
        clearPendingCheckoutContext()
        if clearCart {
            clearCurrentCartOnly()
        }
    }

    func isPendingOrderForEditing(_ order: TodayOrderDTO) -> Bool {
        String(order.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "PENDING"
    }

    func startModifying(order: TodayOrderDTO) {
        print("➡️ 開始更改訂單：\(order.orderId)")

        let statusUpper = String(order.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard statusUpper == "PENDING" else {
            self.errorMessage = "只有未結帳訂單可以直接修改原單"
            return
        }

        // 標記目前在改單模式，而且是編輯原本這張 pending 單
        self.isModifyingOrder = true
        self.modifyingOrderId = order.orderId
        self.checkoutPendingOrderId = order.orderId
        self.editingPendingOrderId = order.orderId
        self.selectedPendingOrderIds.removeAll()

        // 後端若桌位是空字串，視為「外帶」
        let tableName = canonTable(order.tableName.isEmpty ? "外帶" : order.tableName)

        // 切換到這個桌位（找不到就退到外帶）
        if let idx = tableNames.firstIndex(where: { canonTable($0) == tableName }) {
            currentTableIndex = idx
        } else if let idx = tableNames.firstIndex(of: "外帶") {
            currentTableIndex = idx
        }

        // 用 helper 產生 CartLine 陣列
        let newLines = makeCartLines(from: order)

        // 把灌好的品項塞回這張桌子的購物車
        tableCarts[tableName] = newLines
        tableSheetLines[tableName] = TableOrderSnapshot(
            lines: newLines,
            payMethod: nil,
            isPaid: false
        )

        // 確保有計時器，沒有的話就開啟
        let timer = tableTimer(forTable: tableName)
        if !timer.isActive {
            timer.restart()
            TableTimerStore.shared.save(table: tableName, startTime: timer.startTime, isActive: timer.isActive)
        }

        // 這桌已經是使用中
        clearedTables.remove(tableName)
        persistClearedTables()

        print("🔥 已把 \(newLines.count) 筆品項灌入 \(tableName) 的購物車（原單編輯模式）")
    }

    func isPendingOrderSelected(_ orderId: String) -> Bool {
        selectedPendingOrderIds.contains(orderId)
    }

    func togglePendingOrderSelection(_ orderId: String) {
        let trimmed = orderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if selectedPendingOrderIds.contains(trimmed) {
            selectedPendingOrderIds.remove(trimmed)
        } else {
            selectedPendingOrderIds.insert(trimmed)
        }
    }

    func clearPendingOrderSelections() {
        selectedPendingOrderIds.removeAll()
    }

    @MainActor
    func beginCombinedPendingCheckout(for table: String, orderIds: [String]) {
        let table = canonTable(table)
        let normalizedIds = Set(orderIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })

        guard !normalizedIds.isEmpty else {
            errorMessage = "請先勾選未結帳訂單"
            return
        }

        let targets = ordersForTable(table).filter { order in
            let statusUpper = String(order.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return statusUpper == "PENDING" && normalizedIds.contains(order.orderId)
        }

        guard !targets.isEmpty else {
            errorMessage = "找不到可聯合結帳的未結帳訂單"
            return
        }

        // 切到正確桌位（讓右側 CartPanel 對齊）
        if let idx = tableNames.firstIndex(where: { canonTable($0) == table }) {
            currentTableIndex = idx
        }

        // 多張 pending 聯合結帳：購物車顯示為合併內容
        let mergedLines = targets.flatMap { makeCartLines(from: $0) }
        guard !mergedLines.isEmpty else {
            errorMessage = "訂單內容為空，無法聯合結帳"
            return
        }

        clearPendingCheckoutContext()
        selectedPendingOrderIds = Set(targets.map { $0.orderId })

        tableCarts[table] = mergedLines
        tableSheetLines[table] = TableOrderSnapshot(
            lines: mergedLines,
            payMethod: nil,
            isPaid: false
        )

        if clearedTables.contains(table) {
            clearedTables.remove(table)
            persistClearedTables()
        }

        print("🧾 已載入 \(targets.count) 張 pending 單到 \(table) 準備聯合結帳")
    }

    // MARK: - Sheet 控制 ---------------------------
    func showOrderSheet(for table: String) {
        let table = canonTable(table)
        
        // ✅ 清桌遮罩：只有在「沒有 PENDING」時才阻擋開卡片
        //    若有 PENDING，必須允許查看明細（並自洽解除 cleared）
        // ✅ CHANGE 8：清桌不阻擋看明細（你已確定：結帳永遠不該隱藏訂單）
        if clearedTables.contains(table) && hasPendingOrder(for: table) {
            // 若有 pending，解除清桌遮罩（維持你原本自洽）
            clearedTables.remove(table)
            persistClearedTables()
        }

        if clearedTables.contains(table) && hasPendingOrder(for: table) {
            clearedTables.remove(table)
            persistClearedTables()
        }
        
        // 1️⃣ 若已有 snapshot，直接用 snapshot 顯示
        if tableSheetLines[table] != nil {
            activeTableSheet = TableSheetInfo(tableName: table)
            return
        }
        
        // 2️⃣ 沒 snapshot → 看「本輪」訂單（你已經改成 roundOrdersForTable）
        var tableOrders = roundOrdersForTable(table)
        if tableOrders.isEmpty {
            tableOrders = ordersForTable(table)   // 顯示用 fallback：避免放大鏡空白
        }

        guard !tableOrders.isEmpty else {
            tableSheetLines[table] = nil
            activeTableSheet = nil
            return
        }

        
        // ✅ 本輪訂單：依 createdAt 由新到舊排序（最新的在前）
        let sortedOrders = tableOrders.sorted { a, b in
            let da = createdAtDate(for: a)
            let db = createdAtDate(for: b)
            return da > db
        }

        
        // 建立 snapshot：依排序後的訂單合併顯示
        var mergedLines: [CartLine] = []
        for o in sortedOrders {
            mergedLines.append(contentsOf: makeCartLines(from: o))
        }
        
        // payMethod：取本輪最後一個非空的（更符合結帳資訊）
        let lastPayMethod = tableOrders.reversed().first(where: { !($0.payMethod ?? "").isEmpty })?.payMethod
        
        // isPaid：本輪只要還有任何一張不是 settled，就視為未結
        let allSettled = tableOrders.allSatisfy { isSettledStatus($0.status) || !((($0.payMethod ?? "")).isEmpty) }
        
        let snapshot = TableOrderSnapshot(
            lines: mergedLines,
            payMethod: lastPayMethod,
            isPaid: allSettled
        )
        
        tableSheetLines[table] = snapshot
        activeTableSheet = TableSheetInfo(tableName: table)
    }

    // MARK: - 從桌位明細導回「一般結帳流程」（共用 CartPanel 的 UnifiedCheckoutSheet）

    // MARK: - 從桌位明細導回「一般結帳流程」（共用 CartPanel 的 UnifiedCheckoutSheet）
    @MainActor
    func checkoutPendingFromTableSheet(_ table: String) {
        let table = canonTable(table)

        // 必須是 pending
        guard tableStatus(for: table) == .pending else {
            errorMessage = "此桌目前不是未結帳狀態"
            return
        }

        // 找最後一張 PENDING（後端單）
        guard let lastPending = ordersForTable(table)
            .last(where: { String($0.status ?? "").uppercased() == "PENDING" })
        else {
            errorMessage = "找不到未結帳訂單"
            return
        }

        clearPendingCheckoutContext()

        // ✅ 記住這張 pending（後續結帳/改單要用）
        checkoutPendingOrderId = lastPending.orderId
        editingPendingOrderId = lastPending.orderId

        // ✅ 用該訂單重建購物車（右側 CartPanel 會顯示）
        let lines = makeCartLines(from: lastPending)
        guard !lines.isEmpty else {
            errorMessage = "訂單內容為空，無法結帳"
            return
        }

        // 切到該桌（讓右邊 CartPanel 對齊）
        if let idx = tableNames.firstIndex(where: { canonTable($0) == table }) {
            currentTableIndex = idx
        }

        tableCarts[table] = lines
        tableSheetLines[table] = TableOrderSnapshot(lines: lines, payMethod: nil, isPaid: false)

        if clearedTables.contains(table) {
            clearedTables.remove(table)
            persistClearedTables()
        }
    }

    @MainActor
    func checkoutPendingFromTableSheet(_ table: String, orderId: String) {
        let table = canonTable(table)

        guard tableStatus(for: table) == .pending else {
            errorMessage = "此桌目前不是未結帳狀態"
            return
        }

        guard let target = ordersForTable(table)
            .first(where: {
                $0.orderId == orderId &&
                String($0.status ?? "").uppercased() == "PENDING"
            })
        else {
            errorMessage = "找不到指定的未結帳訂單"
            return
        }

        clearPendingCheckoutContext()

        checkoutPendingOrderId = target.orderId
        editingPendingOrderId = target.orderId

        let lines = makeCartLines(from: target)
        guard !lines.isEmpty else {
            errorMessage = "訂單內容為空，無法結帳"
            return
        }

        if let idx = tableNames.firstIndex(where: { canonTable($0) == table }) {
            currentTableIndex = idx
        }

        tableCarts[table] = lines
        tableSheetLines[table] = TableOrderSnapshot(
            lines: lines,
            payMethod: nil,
            isPaid: false
        )

        if clearedTables.contains(table) {
            clearedTables.remove(table)
            persistClearedTables()
        }
    }



    func closeOrderSheet() {
        activeTableSheet = nil
    }

    // MARK: - 今日訂單（從後端讀） ------------------

    /// 從後端讀取「今日所有訂單」
    func reloadTodayOrders() async {
        await MainActor.run { self.isLoadingTodayOrders = true }
        defer { Task { @MainActor in self.isLoadingTodayOrders = false } }

        do {
            let orders = try await APIClient.shared.fetchTodayOrders()
            let filteredOrders = orders.filter { o in
                let s = (o.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return s != "CLOSED"
            }
            // ✅ 套用搬桌覆寫：避免後端延遲時，reload 把單又放回舊桌造成閃/回跳
            let overrides = pendingMoveOverrides
            let merged = filteredOrders.map { o -> TodayOrderDTO in

                if let forced = overrides[o.orderId] {
                    return TodayOrderDTO(
                        orderId: o.orderId,
                        createdAt: o.createdAt,
                        tableName: forced,
                        payMethod: o.payMethod,
                        amount: o.amount,
                        note: o.note,
                        status: o.status,
                        items: o.items
                    )
                }
                return o
            }
            let normalized = merged.map { o in
                TodayOrderDTO(
                    orderId: o.orderId,
                    createdAt: o.createdAt,
                    tableName: canonTable(o.tableName),
                    payMethod: o.payMethod,
                    amount: o.amount,
                    note: o.note,
                    status: o.status,
                    items: o.items
                )
            }

            await MainActor.run {
                self.todayOrders = normalized
                self.rebuildCreatedAtCache()
                
                self.rebuildTableSheetLinesIfNeeded()
            }



        } catch {
            await MainActor.run {
                self.errorMessage = "載入今日訂單失敗：\(error.localizedDescription)"
            }
        }

    }
   
    // MARK: - createdAt 快取重建（只做資料整理，不改流程）
    private func rebuildCreatedAtCache() {
        createdAtDateCache.removeAll(keepingCapacity: true)
        createdAtTextCache.removeAll(keepingCapacity: true)

        for o in todayOrders {
            // ✅ 用「原始解析器」重建，不要在 rebuild 內呼叫 createdAtDate(for:)
            let d = parseOrderDate(o.createdAt)
            createdAtDateCache[o.orderId] = d
            createdAtTextCache[o.orderId] = Self.createdAtDisplayFormatter.string(from: d)
        }
    }
    
    // MARK: - 重建桌位顯示快照（for 重開 / rebuild）
    private func rebuildTableSheetLinesIfNeeded() {
        for table in tableNames.map({ canonTable($0) }) {

            // 已清桌且沒有 pending：不要被 reload 從歷史單重建回佔用
            if clearedTables.contains(table) && !hasPendingOrder(for: table) {
                tableSheetLines[table] = nil
                continue
            }

            // 若已有 snapshot（使用中或剛點過），不要動它
            if let snap = tableSheetLines[table], !snap.lines.isEmpty {
                continue
            }

            guard let snapshot = makeSnapshotFromRoundOrders(for: table) else {
                tableSheetLines[table] = nil
                continue
            }

            tableSheetLines[table] = snapshot
        }
    }




    func ordersForTable(_ table: String) -> [TodayOrderDTO] {
        let t = canonTable(table)
        return todayOrders.filter {
            $0.status != "VOID" && canonTable($0.tableName) == t
        }
    }

    // MARK: - 自動刷新今日訂單（每 10 秒） -----------

    func startAutoRefreshTodayOrders(interval: TimeInterval = 10) {
        // 先取消舊的，避免重複開
        autoRefreshTodayOrdersTask?.cancel()

        autoRefreshTodayOrdersTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                await self.reloadTodayOrders()
                // 休息 interval 秒
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefreshTodayOrders() {
        autoRefreshTodayOrdersTask?.cancel()
        autoRefreshTodayOrdersTask = nil
    }

    // MARK: - 關帳後重置本日狀態 --------------------

    /// 關帳：清空所有桌位的點單 & 計時器 & 清桌標記
    func resetAfterCloseShift() {
        for name in tableNames {
            let name = canonTable(name)
            clearCart(for: name)
            resetStop(for: name)
            tableHasHistory[name] = false
            tableSheetLines[name] = nil

            // ✅ 關帳後也要清掉持久化 timer，避免隔天復活
            TableTimerStore.shared.clear(table: name)
        }
        clearedTables.removeAll()
        ClearedTablesStore.shared.clearAll()
        todayOrders = []

        // 關帳後備份一律清掉，避免殘留
        clearedCartBackups.removeAll()
        clearedSheetBackups.removeAll()
        clearedTimerBackups.removeAll()
        clearedRoundStartBackups.removeAll()
        ClearedTablesStore.shared.clearUndoBackups()
    }
}

