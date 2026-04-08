import SwiftUI

enum ItemOptionMode {
    case add(item: MenuItem)
    case edit(line: CartLine)
}

struct ItemOptionsSheet: View {
    let mode: ItemOptionMode
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

    init(mode: ItemOptionMode, onConfirm: @escaping (CartLine) -> Void) {
        self.mode = mode
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

                VStack(spacing: 16) {

                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.peacock)
                        .padding(.top, 6)

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

                        // 燕麥奶
                        if item.allowOat {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("燕麥奶（+20）", isOn: $isOatMilk)
                                    .font(.subheadline)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        }

                        // 折扣
                        VStack(alignment: .leading, spacing: 4) {
                            Text("折扣")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Toggle("續點（-20）", isOn: $isRefill)
                            Toggle("環保杯（-5）", isOn: $isEcoCup)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("其他需求")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Toggle("餐後外帶", isOn: $isTakeawayAfterMeal)
                            Toggle("要餐具", isOn: $needsCutlery)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

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

                    Button {
                        let line = CartLine(
                            item: item,
                            quantity: quantity,
                            temperature: temperature,
                            sweetness: sweetness,
                            isOatMilk: isOatMilk,
                            isRefill: isRefill,
                            isEcoCup: isEcoCup,
                            isTakeawayAfterMeal: isTakeawayAfterMeal,
                            needsCutlery: needsCutlery
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
                    .padding(.bottom, 12)
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

