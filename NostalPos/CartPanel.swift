//
//  CartPanel.swift
//  NostalPos
//

import SwiftUI
import AVFoundation

struct CartPanel: View {
    @ObservedObject var viewModel: POSViewModel
    
    // 結帳視窗
    @State private var showingCheckoutSheet = false
    // LINE Pay 掃碼視窗
    @State private var showingLinePayScanner = false
    
    // 處理中避免連點
    @State private var isProcessingLinePay = false
    
    // Alert
    @State private var activeAlert: CartAlertType?
    
    // ✅ 購物車編輯：點某一筆 → 打開選項視窗（帶入原狀態）
    @State private var editingLine: CartLine? = nil
    
    enum CartAlertType: Identifiable {
        case camera(String)
        case linePay(String)
        case pending(String)
        
        var id: Int {
            switch self {
            case .camera:  return 0
            case .linePay: return 1
            case .pending: return 2
            }
        }
        
        var title: String {
            switch self {
            case .camera:  return "無法使用相機"
            case .linePay: return "LINE Pay 失敗"
            case .pending: return "先點後結"
            }
        }
        
        var message: String {
            switch self {
            case .camera(let m),
                 .linePay(let m),
                 .pending(let m):
                return m
            }
        }
    }
    
    private var hasItems: Bool {
        !viewModel.currentCart.isEmpty
    }
    
    private var isCheckoutDisabled: Bool {
        !hasItems || isProcessingLinePay
    }
    
    private var totalAmount: Int {
        viewModel.currentTotal
    }
    
    private var isCombinedPendingCheckout: Bool {
        viewModel.selectedPendingOrderIds.count > 1
    }
    
    private var effectivePendingOrderId: String? {
        let editing = viewModel.editingPendingOrderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !editing.isEmpty { return editing }
        let checkout = viewModel.checkoutPendingOrderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !checkout.isEmpty { return checkout }
        return nil
    }
    
    private var isSinglePendingBoundMode: Bool {
        !isCombinedPendingCheckout && effectivePendingOrderId != nil
    }
    
    private var pendingModeHintText: String {
        if isCombinedPendingCheckout {
            return "目前為合併結帳模式；多張未結帳單會保留原 orderId 一起結帳，這裡不可直接改品項。"
        }
        if isSinglePendingBoundMode {
            return "目前正在編輯既有未結帳單；改動會直接更新原本那張 pending 單。"
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 標題
            HStack {
                Text("點單明細")
                    .font(.headline)
                    .foregroundColor(.peacock)
                
                Spacer()
                
                Text(viewModel.currentTableName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            if !pendingModeHintText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isCombinedPendingCheckout ? "link.circle.fill" : "pencil.circle.fill")
                        .foregroundColor(.orange)
                    Text(pendingModeHintText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                
                Divider()
            }
            
            // 點單列表
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.currentCart, id: \.id) { line in
                        HStack(spacing: 8) {
                            Text(line.displayName)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            
                            Spacer(minLength: 8)
                            
                            Text("\(line.lineTotal)")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .trailing)
                            
                            HStack(spacing: 4) {
                                Button {
                                    changeQuantityAndSync(line: line, delta: -1)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 18))
                                }
                                .disabled(isCombinedPendingCheckout)
                                
                                Text("\(line.quantity)")
                                    .font(.subheadline)
                                    .frame(minWidth: 20)
                                
                                Button {
                                    changeQuantityAndSync(line: line, delta: 1)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                }
                                .disabled(isCombinedPendingCheckout)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isCombinedPendingCheckout else {
                                activeAlert = .pending("合併結帳模式不可直接修改品項；若要改單，請回到各張未結帳單分別編輯。")
                                return
                            }
                            editingLine = line
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.posBg)
            
            Divider()
            
            // 總金額 + 按鈕區
            VStack(spacing: 8) {
                HStack {
                    Text("總金額")
                        .font(.headline)
                    Spacer()
                    Text("NT$ \(totalAmount)")
                        .font(.title2.bold())
                }
                .padding(.horizontal)
                
                HStack(spacing: 10) {
                    Button(action: {
                        if isSinglePendingBoundMode {
                            savePendingChanges()
                        } else if isCombinedPendingCheckout {
                            cancelCombinedPendingMode()
                        } else {
                            performPendingPrint()
                        }
                    }) {
                        Text(isProcessingLinePay ? "處理中…" : primaryActionButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(primaryActionButtonDisabled ? Color.gray.opacity(0.25) : Color.gray.opacity(0.18))
                            .foregroundColor(.peacock)
                            .cornerRadius(12)
                    }
                    .disabled(primaryActionButtonDisabled)

                    Button(action: {
                        showingCheckoutSheet = true
                    }) {
                        Text(isProcessingLinePay ? "處理中…" : checkoutButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isCheckoutDisabled ? Color.gray.opacity(0.4) : Color.peacock)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(isCheckoutDisabled)
                }
                .padding(.horizontal)
                
                Text(footerText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
        }
        .sheet(item: $editingLine) { line in
            ItemOptionsSheet(
                mode: .edit(line: line),
                onConfirm: { updatedLine in
                    applyEditedLineAndSync(old: line, new: updatedLine)
                    editingLine = nil
                }
            )
        }
        .sheet(isPresented: $showingCheckoutSheet) {
            UnifiedCheckoutSheet(
                totalAmount: totalAmount,
                onCashConfirm: { _ in
                    performCheckout(using: .cash)
                    showingCheckoutSheet = false
                },
                onLinePay: {
                    if showingLinePayScanner { return }
                    showingCheckoutSheet = false
                    showingLinePayScanner = true
                },
                onTapPay: {
                    performCheckout(using: .tapPay)
                    showingCheckoutSheet = false
                },
                onCancel: {
                    showingCheckoutSheet = false
                }
            )
        }
        .sheet(isPresented: $showingLinePayScanner) {
            LinePayCameraSheet(
                onScanned: { code in
                    startOfflineLinePay(oneTimeKey: code)
                },
                onCancel: {
                    showingLinePayScanner = false
                }
            )
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }
    

    private var primaryActionButtonTitle: String {
        if isSinglePendingBoundMode {
            return "儲存變更"
        }
        if isCombinedPendingCheckout {
            return "取消合併"
        }
        return "先點後結"
    }

    private var primaryActionButtonDisabled: Bool {
        if isProcessingLinePay { return true }
        if isCombinedPendingCheckout { return false }
        return !hasItems
    }

    private func savePendingChanges() {
        guard isSinglePendingBoundMode else { return }
        Task { @MainActor in
            do {
                try await syncCurrentPendingOrderToBackend()

                let table = viewModel.currentTableName
                viewModel.printOrder(
                    for: table,
                    payMethod: "未結帳"
                )

                await viewModel.reloadTodayOrders()
                viewModel.finishPendingEditing()
                activeAlert = .pending("未結帳單變更已儲存，並已印單")
            } catch {
                print("❌ 儲存 pending 變更失敗：\(error.localizedDescription)")
                activeAlert = .pending("儲存變更失敗：\(error.localizedDescription)")
            }
        }
    }

    private func cancelCombinedPendingMode() {
        viewModel.cancelCombinedPendingCheckout()
    }

    private var checkoutButtonTitle: String {
        if isCombinedPendingCheckout {
            return "合併結帳"
        }
        return "結帳"
    }
    
    private var footerText: String {
        if isCombinedPendingCheckout {
            return "已選 \(viewModel.selectedPendingOrderIds.count) 張未結帳單，付款後會逐張更新成 PAID。"
        }
        if isSinglePendingBoundMode {
            return "目前為既有未結帳單編輯模式；修改後可先按「儲存變更」，還不需要立即結帳。"
        }
        return ""
    }
    
    // MARK: - ✅ 先點後結（印單 + 寫入 PENDING）
    
    private func performPendingPrint() {
        guard hasItems else { return }
        if isProcessingLinePay { return }
        
        if isSinglePendingBoundMode || isCombinedPendingCheckout {
            activeAlert = .pending("目前正在處理既有未結帳單，不能再從這裡新增一張先點後結；請先完成編輯或結帳。")
            return
        }
        
        let table = viewModel.currentTableName
        let cartSnapshot = viewModel.currentCart
        
        viewModel.printOrder(
            for: table,
            payMethod: "未結帳"
        )
        
        viewModel.tableSheetLines[table] = TableOrderSnapshot(
            lines: cartSnapshot,
            payMethod: nil,
            isPaid: false
        )
        
        let order = makeOrderRequest(payKey: "")
        
        APIClient.shared.createOrder(order) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let id):
                    print("✅ PENDING 訂單已寫入 Google Sheet：\(id)")
                    viewModel.markRoundStartOnFirstCommittedOrder(for: table, committedAt: Date())
                    viewModel.clearCurrentCartOnly()
                    Task { @MainActor in
                        await viewModel.reloadTodayOrders()
                    }
                    
                case .failure(let error):
                    print("❌ PENDING 訂單寫入失敗：\(error.localizedDescription)")
                    activeAlert = .pending("已先出單，但寫入後台失敗：\(error.localizedDescription)\n建議：檢查網路後，到桌位再重試「先點後結」或直接結帳。")
                }
            }
        }
    }
    
    // MARK: - 出單 + 寫入 Google Sheet（結帳）
    
    private func performCheckout(using method: PaymentMethod) {
        let payKey = method.rawValue
        let table = viewModel.currentTableName
        let cartSnapshot = viewModel.currentCart
        
        viewModel.printOrder(for: table, payMethod: payKey)
        if !cartSnapshot.isEmpty {
            viewModel.tableSheetLines[table] = TableOrderSnapshot(
                lines: cartSnapshot,
                payMethod: payKey,
                isPaid: true
            )
        }
        
        Task { @MainActor in
            do {
                // 1) 合併結帳：逐張把原本 pending 轉 paid，不新增單
                if isCombinedPendingCheckout {
                    let ids = Array(viewModel.selectedPendingOrderIds)
                    guard !ids.isEmpty else { return }
                    
                    for orderId in ids {
                        try await APIClient.shared.updateOrderPaymentStatusAsync(
                            orderId: orderId,
                            payMethod: payKey,
                            linePayTransactionId: nil
                        )
                    }
                    
                    viewModel.cancelCombinedPendingCheckout()
                    await viewModel.reloadTodayOrders()
                    viewModel.isTableActive = false
                    return
                }

                // 2) 單張 pending 原單結帳
                if let pendingId = effectivePendingOrderId,
                   !pendingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    try await syncCurrentPendingOrderToBackend()

                    try await APIClient.shared.updateOrderPaymentStatusAsync(
                        orderId: pendingId,
                        payMethod: payKey,
                        linePayTransactionId: nil
                    )

                    if let snap = viewModel.tableSheetLines[table] {
                        viewModel.tableSheetLines[table] = TableOrderSnapshot(
                            lines: snap.lines,
                            payMethod: payKey,
                            isPaid: true
                        )
                    }

                    viewModel.finishPendingEditing()
                    await viewModel.reloadTodayOrders()
                    viewModel.isTableActive = false
                    return
                }

                // 3) 一般直接結帳
                let order = makeOrderRequest(payKey: payKey)

                let newOrderId: String = try await withCheckedThrowingContinuation { cont in
                    APIClient.shared.createOrder(order) { result in
                        switch result {
                        case .success(let id):
                            cont.resume(returning: id)
                        case .failure(let error):
                            cont.resume(throwing: error)
                        }
                    }
                }

                viewModel.markRoundStartOnFirstCommittedOrder(for: table, committedAt: Date())

                try await APIClient.shared.updateOrderPaymentStatusAsync(
                    orderId: newOrderId,
                    payMethod: payKey,
                    linePayTransactionId: nil
                )

                viewModel.clearCurrentCartOnly()
                await viewModel.reloadTodayOrders()
                viewModel.isTableActive = false
                
            } catch {
                print("❌ 結帳失敗：\(error.localizedDescription)")
                activeAlert = .pending("結帳失敗：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - PENDING 改單同步
    
    private func applyEditedLineAndSync(old: CartLine, new: CartLine) {
        if isCombinedPendingCheckout {
            activeAlert = .pending("合併結帳模式不可直接修改品項；若要改單，請回到各張未結帳單分別編輯。")
            return
        }
        
        let table = viewModel.currentTableName
        viewModel.updateCartLine(old: old, new: new, in: table)
        
        if viewModel.currentCart.firstIndex(where: { $0.id == old.id }) != nil {
            let updatedLines = viewModel.currentCart
            viewModel.tableSheetLines[table] = TableOrderSnapshot(
                lines: updatedLines,
                payMethod: nil,
                isPaid: false
            )
            print("✏️ 已更新本機購物車，準備同步 pending 原單")
        }
        
        Task { @MainActor in
            do {
                try await syncCurrentPendingOrderToBackend()
                await viewModel.reloadTodayOrders()
            } catch {
                print("❌ pending 改單同步失敗：\(error.localizedDescription)")
                activeAlert = .pending("已更新畫面，但同步未結帳訂單到後台失敗：\(error.localizedDescription)")
            }
        }
    }
    
    private func changeQuantityAndSync(line: CartLine, delta: Int) {
        if isCombinedPendingCheckout {
            activeAlert = .pending("合併結帳模式不可直接修改數量；若要改單，請回到各張未結帳單分別編輯。")
            return
        }
        
        let table = viewModel.currentTableName
        
        if delta > 0 {
            viewModel.incrementLine(line, in: table)
        } else {
            viewModel.decrementLine(line, in: table)
        }
        
        if isSinglePendingBoundMode {
            viewModel.tableSheetLines[table] = TableOrderSnapshot(
                lines: viewModel.currentCart,
                payMethod: nil,
                isPaid: false
            )
            
            Task { @MainActor in
                do {
                    try await syncCurrentPendingOrderToBackend()
                    await viewModel.reloadTodayOrders()
                } catch {
                    print("❌ pending 數量同步失敗：\(error.localizedDescription)")
                    activeAlert = .pending("已更新畫面，但同步未結帳訂單到後台失敗：\(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func syncCurrentPendingOrderToBackend() async throws {
        guard !isCombinedPendingCheckout else { return }
        guard let pendingId = effectivePendingOrderId,
              !pendingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        
        try await APIClient.shared.updateOrderAsync(
            orderId: pendingId,
            items: viewModel.currentCart,
            amount: viewModel.currentTotal,
            note: "桌位：\(viewModel.currentTableName)"
        )
    }

    // MARK: - 相機權限（保留備用，現在不靠它開關畫面）
    
    private func requestCameraPermission(onGranted: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            onGranted()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    granted ? onGranted() : showNoCameraAlert()
                }
            }
        case .denied, .restricted:
            showNoCameraAlert()
        @unknown default:
            showNoCameraAlert()
        }
    }
    
    private func showNoCameraAlert() {
        activeAlert = .camera("請到「設定 > 隱私權與安全性 > 相機」裡，開啟 NostalPos 的相機權限。")
    }
    
    // MARK: - Offline Line Pay 流程
    
    private func startOfflineLinePay(oneTimeKey: String) {
        showingLinePayScanner = false
        
        guard !oneTimeKey.isEmpty else {
            activeAlert = .linePay("讀取付款碼失敗，請重新掃描。")
            return
        }
        
        let amount = totalAmount
        let orderId = UUID().uuidString
        let productName = "店內消費 - \(viewModel.currentTableName)"
        
        isProcessingLinePay = true
        
        LinePayService.shared.payOffline(
            amount: amount,
            orderId: orderId,
            productName: productName,
            oneTimeKey: oneTimeKey
        ) { result in
            DispatchQueue.main.async {
                self.isProcessingLinePay = false
                
                switch result {
                case .success(let res):
                    let code = res.returnCode
                    let msg = res.returnMessage
                    
                    guard code == "0000" else {
                        if code == "1125" {
                            self.activeAlert = .linePay("付款結果不明（1125）：請確認客人 LINE Pay 是否已扣款，若已扣款請改用現金完成結帳記錄。")
                        } else {
                            self.activeAlert = .linePay("付款失敗：\(code) \(msg)")
                        }
                        return
                    }
                    
                    self.performCheckout(using: .linePay)
                    
                case .failure(let error):
                    let nsErr = error as NSError
                    if nsErr.domain == "LinePayService" && nsErr.code == -1001 {
                        // timeout 後結果不明：金流可能已扣款
                        self.activeAlert = .linePay(nsErr.localizedDescription)
                    } else {
                        self.activeAlert = .linePay("網路錯誤：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - 建立 OrderRequest（維持原本責任：組 payload 給 APIClient）

    private func makeOrderRequest(payKey: String) -> OrderRequest {
        let table = viewModel.currentTableName
        let cart = viewModel.currentCart
        
        let backendItems: [OrderItem] = cart.map { line in
            let qty = line.quantity
            let unitPrice = qty > 0 ? line.lineTotal / qty : line.lineTotal
            return OrderItem(name: line.displayName, price: unitPrice, qty: qty)
        }
        
        let order = OrderRequest(
            orderId: UUID().uuidString,
            amount: totalAmount,
            items: backendItems,
            payMethod: payKey,
            note: "桌位：\(table)",
            tableName: table
        )
        return order
    }
}
