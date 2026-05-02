//
//  AdminPanelView.swift
//  NostalPos
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - DTO

struct AdminAddOn: Identifiable, Codable {
    var addOnId: String
    var name: String
    var price: Int
    var enabled: Bool

    var id: String { addOnId }
}

struct AdminItem: Identifiable, Codable {
    /// 後端的正式 ID（舊資料會有，新新增的先是 nil）
    var itemId: String?

    /// 本地用的固定 ID，只給 SwiftUI ForEach / Identifiable 用
    /// 不會編碼到 JSON 裡，不影響後端
    var localId: String = UUID().uuidString

    var categoryId: String
    var name: String
    var price: Int
    var enabled: Bool
    var allowOat: Bool
    var addOns: [AdminAddOn]

    /// View 用的穩定識別：優先用 itemId，沒有就用 localId
    var id: String { itemId ?? localId }

    /// 只跟後端交換這幾個欄位，localId 不寫進 JSON
    enum CodingKeys: String, CodingKey {
        case itemId
        case categoryId
        case name
        case price
        case enabled
        case allowOat
        case addOns
    }
}

struct AdminCategory: Identifiable, Codable {
    var categoryId: String
    var name: String
    var sortOrder: Int
    var items: [AdminItem]

    var id: String { categoryId }
}

struct AdminMenuResponse: Codable {
    var categories: [AdminCategory]
}

struct SaveAdminMenuPayload: Codable {
    var action: String = "saveAdminMenu"
    var categories: [AdminCategory]
}

// MARK: - ViewModel

@MainActor
final class AdminPanelViewModel: ObservableObject {
    @Published var categories: [AdminCategory] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // ⚠️ 後端 Web App URL（維持你原本的）
    private let backendURL = URL(string: "https://script.google.com/macros/s/AKfycbxKvvyOh3V31Gf_-EsyE1rWcPNwmLXl1MZ3YnihCYpBcON4gVD4aQGgkl3c4Kouow3PNw/exec")!

    func load() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            var comps = URLComponents(url: backendURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "action", value: "getAdminMenu")
            ]
            guard let url = comps.url else { throw URLError(.badURL) }

            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(AdminMenuResponse.self, from: data)
            self.categories = resp.categories
        } catch {
            self.errorMessage = "載入失敗：\(error.localizedDescription)"
        }

        isLoading = false
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil

        do {
            var request = URLRequest(url: backendURL)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload = SaveAdminMenuPayload(categories: categories)
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let ok = json["ok"] as? Bool, ok {
                    let updated = json["updatedCount"] as? Int ?? 0
                    let created = json["newCount"] as? Int ?? 0
                    self.successMessage = "已儲存（更新 \(updated) 筆，新增 \(created) 筆）"
                } else {
                    let msg = json["error"] as? String ?? "未知錯誤"
                    self.errorMessage = "儲存失敗：\(msg)"
                }
            } else {
                self.successMessage = "已儲存。"
            }
        } catch {
            self.errorMessage = "儲存失敗：\(error.localizedDescription)"
        }

        isSaving = false
    }

    /// 在指定分類新增一個品項（插在最上面 → 新到舊）
    func addItem(to categoryId: String) {
        guard let index = categories.firstIndex(where: { $0.categoryId == categoryId }) else { return }
        let newItem = AdminItem(
            itemId: nil,
            categoryId: categoryId,
            name: "新商品",
            price: 0,
            enabled: true,
            allowOat: false,
            addOns: []
        )
        // 新項目插在 0 → 顯示順序由新到舊
        categories[index].items.insert(newItem, at: 0)
    }
}

// MARK: - Toggle Admin ViewModel

@MainActor
final class ToggleAdminViewModel: ObservableObject {
    @Published var toggles: [AppToggle] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        do {
            toggles = try await APIClient.shared.fetchToggles()
        } catch {
            errorMessage = "載入失敗：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        for i in toggles.indices {
            toggles[i].sortOrder = i
        }
        do {
            try await APIClient.shared.saveToggles(toggles)
            successMessage = "已儲存（\(toggles.count) 個選項）"
        } catch {
            errorMessage = "儲存失敗：\(error.localizedDescription)"
        }
        isSaving = false
    }

    func addToggle() {
        let newId = UUID().uuidString
        toggles.append(AppToggle(
            toggleId: newId,
            label: "新選項",
            priceEffect: 0,
            sortOrder: toggles.count,
            isActive: true
        ))
    }

    func deleteToggle(at offsets: IndexSet) {
        toggles.remove(atOffsets: offsets)
    }

    func moveToggle(from source: IndexSet, to destination: Int) {
        toggles.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Toggle Admin View

struct ToggleAdminView: View {
    @ObservedObject var vm: ToggleAdminViewModel

    var body: some View {
        Group {
            if vm.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("載入中…").foregroundColor(.secondary).font(.subheadline)
                    Spacer()
                }
            } else {
                List {
                    ForEach($vm.toggles) { $toggle in
                        ToggleAdminRow(toggle: $toggle)
                    }
                    .onDelete(perform: vm.deleteToggle)
                    .onMove(perform: vm.moveToggle)

                    Button {
                        vm.addToggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.peacock)
                            Text("新增選項")
                                .foregroundColor(.peacock)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
        }
        .task { await vm.load() }
    }
}

struct ToggleAdminRow: View {
    @Binding var toggle: AppToggle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("選項名稱", text: $toggle.label)
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $toggle.isActive)
                    .labelsHidden()
                    .tint(.peacock)
            }
            HStack {
                Text("加減價")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("0", value: $toggle.priceEffect, format: .number)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.caption)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Text("元（0 = 無加減）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View

struct AdminPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AdminPanelViewModel()
    @StateObject private var toggleVM = ToggleAdminViewModel()

    @State private var selectedTab: Int = 0
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        NavigationView {
            ZStack {
                Color.posBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab 切換
                    Picker("", selection: $selectedTab) {
                        Text("菜單管理").tag(0)
                        Text("自訂選項").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // 狀態訊息
                    let errorMsg = selectedTab == 0 ? vm.errorMessage : toggleVM.errorMessage
                    let successMsg = selectedTab == 0 ? vm.successMessage : toggleVM.successMessage

                    if let error = errorMsg {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                            .shadow(radius: 2)
                            .padding(.horizontal, 16)
                    }
                    if let msg = successMsg {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.green)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                            .shadow(radius: 2)
                            .padding(.horizontal, 16)
                    }

                    if selectedTab == 0 {
                        // 菜單管理（原有內容）
                        if vm.isLoading {
                            Spacer()
                            ProgressView()
                            Text("載入後台資料中…")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach($vm.categories) { $category in
                                        CategoryCard(
                                            category: $category,
                                            allCategories: vm.categories,
                                            isExpanded: expandedCategories.contains(category.categoryId),
                                            toggleExpanded: {
                                                let id = category.categoryId
                                                if expandedCategories.contains(id) {
                                                    expandedCategories.remove(id)
                                                } else {
                                                    expandedCategories.insert(id)
                                                }
                                            },
                                            onAddItem: {
                                                vm.addItem(to: category.categoryId)
                                                expandedCategories.insert(category.categoryId)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    } else {
                        // 自訂選項管理
                        ToggleAdminView(vm: toggleVM)
                    }
                }
            }
            .navigationTitle("後台管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == 0 {
                        Button {
                            Task { await vm.save() }
                        } label: {
                            if vm.isSaving { ProgressView() } else { Text("儲存") }
                        }
                        .disabled(vm.isSaving)
                    } else {
                        Button {
                            Task { await toggleVM.save() }
                        } label: {
                            if toggleVM.isSaving { ProgressView() } else { Text("儲存") }
                        }
                        .disabled(toggleVM.isSaving)
                    }
                }
            }
            .task {
                await vm.load()
            }
        }
    }
}

// MARK: - 大分類卡片

struct CategoryCard: View {
    @Binding var category: AdminCategory
    let allCategories: [AdminCategory]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let onAddItem: () -> Void

    /// 目前正在被拖曳的品項 id
    @State private var draggingItemId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header：分類名稱 + 數量 + 展開箭頭
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.headline)
                        .foregroundColor(.peacock)
                    Text("\(category.items.count) 項品項")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline)
                    .foregroundColor(.peacock)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpanded()
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, 4)

                // 新增品項按鈕（展開內容的最上面）
                Button(action: onAddItem) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("新增品項")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 999)
                            .fill(Color.peacock.opacity(0.08))
                    )
                }

                // 品項列表（平面列，支援拖曳排序）
                VStack(spacing: 0) {
                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, _ in
                        let itemBinding = $category.items[index]

                        AdminItemRow(
                            item: itemBinding,
                            allCategories: allCategories,
                            onDelete: {
                                category.items.remove(at: index)
                            }
                        )
                        // 整列可拖曳排序（視覺上三橫線在售價後面）
                        .onDrag {
                            let id = itemBinding.wrappedValue.id
                            draggingItemId = id
                            return NSItemProvider(object: NSString(string: id))
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ItemDropDelegate(
                                targetItem: itemBinding.wrappedValue,
                                category: $category,
                                draggingItemId: $draggingItemId
                            )
                        )

                        // 中間加細分隔線，最後一列不加
                        if index < category.items.count - 1 {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
    }
}

// MARK: - DropDelegate for 重新排序

struct ItemDropDelegate: DropDelegate {
    let targetItem: AdminItem            // 目前這一列的 item（掉落目標）
    @Binding var category: AdminCategory
    @Binding var draggingItemId: String?

    func dropEntered(info: DropInfo) {
        guard let draggingId = draggingItemId,
              draggingId != targetItem.id,
              let fromIndex = category.items.firstIndex(where: { $0.id == draggingId }),
              let toIndex = category.items.firstIndex(where: { $0.id == targetItem.id })
        else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            let moved = category.items.remove(at: fromIndex)
            category.items.insert(moved, at: toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItemId = nil
        return true
    }
}

// MARK: - 單一品項列

struct AdminItemRow: View {
    @Binding var item: AdminItem
    let allCategories: [AdminCategory]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：名稱 + 售價 + 三橫線拖曳 icon
            HStack(spacing: 8) {
                TextField("品項名稱", text: $item.name)
                    .textFieldStyle(.roundedBorder)

                TextField("售價", text: Binding(
                    get: { String(item.price) },
                    set: { item.price = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                // 三橫線拖曳 icon（視覺提示；實際拖曳是整列）
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .opacity(0.7)
                    .padding(.leading, 2)
            }

            // 第二行：啟用 + 燕麥奶 + 分類 + 刪除按鈕（同一行）
            HStack(spacing: 6) {
                // 啟用（縮小版）
                HStack(spacing: 4) {
                    Text("啟用")
                        .font(.footnote)

                    Toggle("", isOn: $item.enabled)
                        .labelsHidden()
                        .scaleEffect(0.75)
                }

                // 燕麥奶（縮小版）
                HStack(spacing: 4) {
                    Text("燕麥奶")
                        .font(.footnote)

                    Toggle("", isOn: $item.allowOat)
                        .labelsHidden()
                        .scaleEffect(0.75)
                }

                Spacer()

                // 分類選單
                Picker("分類", selection: $item.categoryId) {
                    ForEach(allCategories) { cat in
                        Text(cat.name).tag(cat.categoryId)
                    }
                }
                .font(.footnote)
                .pickerStyle(.menu)

                // 刪除按鈕
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 6)   // 只保留上下間距，不再有卡片背景
    }
}

