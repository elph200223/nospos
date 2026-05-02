//
//  ContentView.swift
//  NostalPos
//

import SwiftUI

// MARK: - 顏色

extension Color {
    static let posBg = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let peacock = Color(red: 0.02, green: 0.42, blue: 0.55)
}

// MARK: - Root -------------------------------------------------------

struct ContentView: View {
    @StateObject private var vm = POSViewModel()
    
    @State private var showingAdminPanel = false
    @State private var showingTodayOrders = false
    @State private var showingCloseShift = false
    
    // 桌位歷史訂單 sheet（你原本就有）
    @State private var showingTableHistory = false
    @State private var selectedHistoryTableName: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // 左邊桌位區
            LeftTableArea(
                vm: vm,
                onTapAdmin: { showingAdminPanel = true },
                onTapTodayOrders: { showingTodayOrders = true },
                onTapCloseShift: { showingCloseShift = true },
                onTapTableHistory: { name in
                    vm.switchTable(vm.tableNames.firstIndex(of: name) ?? 0)
                    vm.showOrderSheet(for: name)
                }
            )
            
            Divider()

            // 右邊：選了桌才顯示菜單+點單，否則顯示主控台
            if vm.isTableActive {
                RightOrderArea(vm: vm)
            } else {
                DashboardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.posBg.ignoresSafeArea())
        .task { await vm.loadMenu() }
        .onAppear {
            vm.startAutoRefreshTodayOrders(interval: 60)
            LinePayCameraManager.shared.warmUp()
        }
        .onDisappear {
            vm.stopAutoRefreshTodayOrders()
        }

        .sheet(item: $vm.activeTableSheet) { info in
            TableOrdersSheet(
                tableName: info.tableName,
                onDelete: { }
            )
            .environmentObject(vm)
        }





        // 點品項選項 sheet
        // 點品項選項 sheet
        .sheet(item: $vm.showingOptionsForItem) { item in
            ItemOptionsSheet(
                mode: .add(item: item),
                appToggles: vm.appToggles,
                onConfirm: { line in
                    vm.addToCart(line)
                }
            )
        }

        // 後台管理
        .sheet(isPresented: $showingAdminPanel) {
            AdminPanelView().environmentObject(vm)
        }

        // 今日訂單總覽（pending 編輯 / 聯合結帳）
        .sheet(isPresented: $showingTodayOrders) {
            TodayOrdersView(
                onModifyPendingOrder: { order in
                    showingTodayOrders = false
                    vm.startModifying(order: order)
                },
                onCombinedCheckout: { table, orderIds in
                    showingTodayOrders = false
                    vm.beginCombinedPendingCheckout(for: table, orderIds: orderIds)
                }
            )
        }

        // 關帳
        .sheet(isPresented: $showingCloseShift) {
            CloseShiftView()
        }
    }

    
    // MARK: - 左側：桌位 / 計時 -------------------------------------------
    
    struct LeftTableArea: View {
        @ObservedObject var vm: POSViewModel
        let onTapAdmin: () -> Void
        let onTapTodayOrders: () -> Void
        let onTapCloseShift: () -> Void
        let onTapTableHistory: (String) -> Void
        
        private func index(of name: String) -> Int {
            vm.tableNames.firstIndex(of: name) ?? 0
        }

        private func card(_ name: String) -> some View {
            let idx = index(of: name)
            let snap = vm.snapshot(for: name)
            let isPaid = (snap?.isPaid ?? false) || !((snap?.payMethod ?? "").isEmpty)

            return TableCard(
                name: name,
                isSelected: vm.currentTableIndex == idx && vm.isTableActive,
                hasOrder: vm.tableHasOrder(name),
                isPending: vm.hasPendingOrder(for: name) && !isPaid,
                timer: vm.tableTimer(forTable: name),
                
                // ⭐ 左下：看訂單（打開這桌的 TableOrderSheet）
                onLeftTap: {
                    vm.switchTable(idx)          // 順便切到這桌
                    onTapTableHistory(name)      // 實際做的事是 vm.showOrderSheet(for: name)
                },
                
                // ⭐ 右下：控制計時（開始 / 歸零），邏輯在 ViewModel 裡
                onRightTap: {
                    let t = vm.tableTimer(forTable: name)
                    if t.isActive {
                        vm.resetStop(for: name)  // 已在跑 → 歸零 & 停止
                    } else {
                        vm.startTimer(for: name) // 沒在跑 → 開始計時
                    }
                },
                
                // ⭐ 點整張卡片：選桌（已選同一桌再點 = 收回主控台）
                onTap: {
                    if vm.currentTableIndex == idx && vm.isTableActive {
                        vm.isTableActive = false
                    } else {
                        vm.switchTable(idx)
                        vm.isTableActive = true
                    }
                },
                
                // 🔄 這桌是否有清桌備份 → 決定要不要顯示「復原」按鈕
                canUndoClear: vm.hasUndoClearBackup(for: name),

                
                // 🔄 按下「復原」時要做的事
                onUndoClear: {
                    vm.undoClearTable(for: name)
                }
            )
            .onDrag {
                vm.draggingTableName = name
                return NSItemProvider(object: name as NSString)
            }
            .onDrop(of: ["public.text"], isTargeted: nil) { _ in
                if let from = vm.draggingTableName {
                    vm.moveTable(from: from, to: name)
                    vm.draggingTableName = nil
                    return true
                }
                return false
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("桌位 / 計時")
                    .font(.headline)
                    .foregroundColor(.peacock)
                    .padding(.horizontal, 6)
                
                HStack(spacing: 16) {
                    card("吧外")
                    card("吧2")
                    card("吧3")
                    card("吧內")
                }
                
                HStack(spacing: 16) {
                    Spacer(minLength: 0)
                    card("圓窗")
                    card("圓梯")
                    Spacer(minLength: 0)
                }
                
                HStack(spacing: 16) {
                    card("臺窗")
                    card("臺二")
                    card("臺三")
                    card("臺四")
                }
                
                HStack(spacing: 16) {
                    card("大沙")
                    card("戶外")
                    card("矮桌")
                    card("外帶")
                }
                
                HStack(spacing: 12) {
                    Button(action: onTapAdmin) {
                        Text("後台管理")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.peacock)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: onTapTodayOrders) {
                        Text("訂單查詢")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .foregroundColor(.peacock)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.peacock)
                            )
                    }

                    Button(action: onTapCloseShift) {
                        Text("關帳")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .foregroundColor(.peacock)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.peacock)
                            )
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 6)

                ScrollView {
                    TodoSection()
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(width: 420)
            .background(Color.white)
        }
    }
    
    // MARK: - 右側：分類 / 品項 / 訂單 -----------------------------------
    
    struct RightOrderArea: View {
        @ObservedObject var vm: POSViewModel
        
        var body: some View {
            VStack(spacing: 0) {
                // 錯誤訊息
                if let msg = vm.errorMessage {
                    Text(msg)
                        .foregroundColor(.red)
                        .padding(.vertical, 4)
                }
                
                // 標題 + 刷新按鈕（兩段式：菜單 + 今日訂單）
                HStack(spacing: 8) {
                    Text("菜單")
                        .font(.headline)
                        .foregroundColor(.peacock)
                    
                    Button {
                        Task {
                            await vm.loadMenu()          // 第一步：刷新菜單
                            await vm.reloadTodayOrders() // 第二步：順便刷新今日訂單
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.peacock)
                    .padding(6)
                    .background(Color.peacock.opacity(0.12))
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)
                
                // 大分類橫向 Scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.categories) { cat in
                            Button {
                                vm.selectedCategoryId = cat.categoryId
                            } label: {
                                Text(cat.name)
                                    .font(.headline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        vm.selectedCategoryId == cat.categoryId
                                        ? Color.peacock
                                        : Color.white
                                    )
                                    .foregroundColor(
                                        vm.selectedCategoryId == cat.categoryId
                                        ? .white
                                        : .peacock
                                    )
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                Divider()
                
                // 品項＋右側點單明細
                HStack(spacing: 0) {
                    // 品項區
                    ScrollView {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 12),
                                count: 3
                            ),
                            spacing: 12
                        ) {
                            ForEach(vm.filteredItems) { item in
                                ItemButton(item: item) {
                                    vm.showingOptionsForItem = item
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    Divider()
                    
                    // 右側點單明細
                    CartPanel(viewModel: vm)
                        .frame(width: 260)
                }
            }
        }
    }
    
    // MARK: - 品項按鈕 ----------------------------------------------------
    
    struct ItemButton: View {
        let item: MenuItem
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.peacock)
                    Text("NT$\(item.price)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }
}
