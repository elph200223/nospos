import SwiftUI

enum ItemOptionMode {
    case add(item: MenuItem)
    case edit(line: CartLine)
}

struct ItemOptionsSheet: View {
    let mode: ItemOptionMode
    let appToggles: [AppToggle]
    var onConfirm: (CartLine) -> Void

    @Environment(\.dismiss) private var dismiss

    // 不管 add / edit，都用這個 item 畫 UI
    private let item: MenuItem

    @State private var temperature: Temperature = .none
    @State private var sweetness: Sweetness? = nil
    @State private var isOatMilk: Bool = false
    @State private var isRefill: Bool = false
    @State private var isEcoCup: Bool = false
    @State private var isTakeawayAfterMeal: Bool = false
    @State private var needsCutlery: Bool = false
    @State private var quantity: Int = 1
    @State private var selectedCustomToggleIds: Set<String> = []

    init(mode: ItemOptionMode, appToggles: [AppToggle] = [], onConfirm: @escaping (CartLine) -> Void) {
        self.mode = mode
        self.appToggles = appToggles
        self.onConfirm = onConfirm

        switch mode {
        case .add(let item):
            self.item = item
            _temperature = State(initialValue: .none)
            _sweetness  = State(initialValue: nil)
            _isOatMilk  = State(initialValue: false)
            _isRefill   = State(initialValue: false)
            _isEcoCup   = State(initialValue: false)
            _isTakeawayAfterMeal = State(initialValue: false)
            _needsCutlery = State(initialValue: false)
            _quantity   = State(initialValue: 1)
            _selectedCustomToggleIds = State(initialValue: [])

        case .edit(let line):
            self.item = line.item
            _temperature = State(initialValue: line.temperature)
            _sweetness  = State(initialValue: line.sweetness)
            _isOatMilk  = State(initialValue: line.isOatMilk)
            _isRefill   = State(initialValue: line.isRefill)
            _isEcoCup   = State(initialValue: line.isEcoCup)
            _isTakeawayAfterMeal = State(initialValue: line.isTakeawayAfterMeal)
            _needsCutlery = State(initialValue: line.needsCutlery)
            _quantity   = State(initialValue: line.quantity)
            let selectedLabels = Set(line.customToggles.map { $0.label })
            let preselectedIds = Set(appToggles.filter { selectedLabels.contains($0.label) }.map { $0.toggleId })
            _selectedCustomToggleIds = State(initialValue: preselectedIds)
        }
    }

    private var confirmTitle: String {
        switch mode {
        case .add: return "加入"
        case .edit: return "更新"
        }
    }

    private func pill(text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(isSelected ? Color.peacock : Color.white)
            )
            .foregroundColor(isSelected ? .white : .peacock)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.peacock.opacity(isSelected ? 0 : 0.6), lineWidth: 1)
            )
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.posBg.ignoresSafeArea()

                VStack(spacing: 0) {

                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.peacock)
                        .padding(.vertical, 10)

                    // 可捲動的選項區域
                    ScrollView {
                        VStack(spacing: 14) {

                            // 溫度
                            VStack(alignment: .leading, spacing: 6) {
                                Text("溫度")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 10) {
                                    ForEach(Temperature.allCases, id: \.self) { t in
                                        Button {
                                            temperature = t
                                        } label: {
                                            pill(text: t.display, isSelected: temperature == t)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                            // 甜度
                            VStack(alignment: .leading, spacing: 6) {
                                Text("甜度（可不選）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                let opts: [Sweetness?] = [nil] + Sweetness.allCases

                                HStack(spacing: 10) {
                                    ForEach(opts, id: \.self) { opt in
                                        Button {
                                            sweetness = opt
                                        } label: {
                                            pill(
                                                text: opt?.display ?? "不選",
                                                isSelected: sweetness == opt
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                            // 其他選項（pill 格，2 欄）
                            VStack(alignment: .leading, spacing: 8) {
                                Text("其他選項")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 8
                                ) {
                                    if item.allowOat {
                                        Button { isOatMilk.toggle() } label: {
                                            pill(text: "燕麥奶（+20）", isSelected: isOatMilk)
                                                .frame(maxWidth: .infinity)
                                        }.buttonStyle(.plain)
                                    }
                                    Button { isRefill.toggle() } label: {
                                        pill(text: "續點（-20）", isSelected: isRefill)
                                            .frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                    Button { isEcoCup.toggle() } label: {
                                        pill(text: "環保杯（-5）", isSelected: isEcoCup)
                                            .frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                    Button { isTakeawayAfterMeal.toggle() } label: {
                                        pill(text: "餐後外帶", isSelected: isTakeawayAfterMeal)
                                            .frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                    Button { needsCutlery.toggle() } label: {
                                        pill(text: "要餐具", isSelected: needsCutlery)
                                            .frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                            // 自訂選項（2 欄 pill 格）
                            let activeToggles = appToggles.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
                            if !activeToggles.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("自訂選項")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    LazyVGrid(
                                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                                        spacing: 8
                                    ) {
                                        ForEach(activeToggles) { toggle in
                                            let label: String = {
                                                if toggle.priceEffect > 0 { return "\(toggle.label)（+\(toggle.priceEffect)）" }
                                                if toggle.priceEffect < 0 { return "\(toggle.label)（\(toggle.priceEffect)）" }
                                                return toggle.label
                                            }()
                                            let isSelected = selectedCustomToggleIds.contains(toggle.toggleId)
                                            Button {
                                                if isSelected {
                                                    selectedCustomToggleIds.remove(toggle.toggleId)
                                                } else {
                                                    selectedCustomToggleIds.insert(toggle.toggleId)
                                                }
                                            } label: {
                                                pill(text: label, isSelected: isSelected)
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                            }

                            // 數量
                            VStack(alignment: .leading, spacing: 4) {
                                Text("數量")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 16) {
                                    Button {
                                        if quantity > 1 { quantity -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title3)
                                            .frame(width: 40, height: 40)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.peacock, lineWidth: 1)
                                            )
                                            .foregroundColor(.peacock)
                                    }

                                    Text("\(quantity)")
                                        .font(.title3)
                                        .frame(minWidth: 40)

                                    Button {
                                        if quantity < 20 { quantity += 1 }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .frame(width: 40, height: 40)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.peacock))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                    }

                    // 確認按鈕永遠釘在底部
                    Button {
                        let chosenToggles = appToggles
                            .filter { selectedCustomToggleIds.contains($0.toggleId) }
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map { SelectedToggle(label: $0.label, priceEffect: $0.priceEffect) }

                        let line = CartLine(
                            item: item,
                            quantity: quantity,
                            temperature: temperature,
                            sweetness: sweetness,
                            isOatMilk: isOatMilk,
                            isRefill: isRefill,
                            isEcoCup: isEcoCup,
                            isTakeawayAfterMeal: isTakeawayAfterMeal,
                            needsCutlery: needsCutlery,
                            customToggles: chosenToggles
                        )
                        onConfirm(line)
                        dismiss()
                    } label: {
                        Text(confirmTitle)
                            .font(.headline)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.peacock)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: 420)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

