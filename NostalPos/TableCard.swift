//
//  TableCard.swift
//  NostalPos
//

import SwiftUI

struct TableCard: View {
    let name: String
    let isSelected: Bool
    let hasOrder: Bool

    // ✅ 新增：是否為未結帳（PENDING）
    let isPending: Bool

    @ObservedObject var timer: TableTimer

    let canUndoClear: Bool

    /// 🔍（已結帳 / 非 pending）→ 看訂單明細
    let onLeftTap: () -> Void

    /// 💲（pending）→ 進結帳流程（先點後結）
    let onTapCheckout: () -> Void

    let onRightTap: () -> Void
    let onTap: () -> Void
    let onUndoClear: () -> Void

    private var elapsed: Int { Int(timer.elapsed) }

    // 🕒 預計離桌時間格式器
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var expectedFinishText: String {
        guard let start = timer.startTime else { return "--:--" }
        let finish = start.addingTimeInterval(TimeInterval(timer.limitMinutes * 60))
        return TableCard.timeFormatter.string(from: finish)
    }

    // 右上狀態點顏色
    private var statusColor: Color {
        if !timer.isActive { return hasOrder ? .green : Color.gray.opacity(0.35) }

        if elapsed >= timer.limitMinutes * 60 { return .red }
        if elapsed >= 90 * 60 { return .orange }
        return .green
    }

    // 卡片底色
    private var fillColor: Color {
        if !timer.isActive { return hasOrder ? Color.green.opacity(0.18) : .white }

        if elapsed >= timer.limitMinutes * 60 { return Color.red.opacity(0.28) }
        if elapsed >= 90 * 60 { return Color.orange.opacity(0.22) }
        return Color.green.opacity(0.22)
    }

    // 時間字體顏色
    private var timeTextColor: Color {
        if !timer.isActive { return .secondary }

        if elapsed >= timer.limitMinutes * 60 { return .red }
        if elapsed >= 90 * 60 { return .orange }
        return .green
    }

    // init
    init(
        name: String,
        isSelected: Bool,
        hasOrder: Bool,
        isPending: Bool,                 // ✅ 新增
        timer: TableTimer,
        onLeftTap: @escaping () -> Void,
        onTapCheckout: @escaping () -> Void = {},   // ✅ 新增：給 $ 用（預設空，避免舊呼叫端立刻報錯）
        onRightTap: @escaping () -> Void,
        onTap: @escaping () -> Void,
        canUndoClear: Bool = false,
        onUndoClear: @escaping () -> Void = {}
    ) {
        self.name = name
        self.isSelected = isSelected
        self.hasOrder = hasOrder
        self.isPending = isPending
        self.timer = timer
        self.onLeftTap = onLeftTap
        self.onTapCheckout = onTapCheckout
        self.onRightTap = onRightTap
        self.onTap = onTap
        self.canUndoClear = canUndoClear
        self.onUndoClear = onUndoClear
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.peacock : Color.gray.opacity(0.35),
                                lineWidth: isSelected ? 2 : 1)
                )

            VStack(alignment: .leading, spacing: 6) {

                // 上排：桌名 + 小點
                HStack {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.peacock)

                    Spacer()

                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }

                // ⭐⭐⭐ 中排：預計離桌時間（大字＋可愛風）
                Text(expectedFinishText)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundColor(timeTextColor)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // 下排按鈕
                HStack {

                    if canUndoClear {
                        // ⭐ 黃色純線條垃圾桶（無外圈）
                        Button(action: onUndoClear) {
                            ZStack {
                                // 透明占位（讓整個按鈕有 30x30 大小）
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 30, height: 30)

                                // 垃圾桶 icon 放中間
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                        }
                        .buttonStyle(.plain)

                    } else if hasOrder {
                        Button {
                            if isPending {
                                // 💲 先點後結：仍然走「看明細」
                                // （下一步你要改成直接結帳，就是在這裡）
                                onLeftTap()
                            } else {
                                // 🔍 已結帳：看訂單明細
                                onLeftTap()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                    .frame(width: 30, height: 30)

                                if isPending {
                                    Image(systemName: "dollarsign")
                                        .foregroundColor(.peacock)
                                        .font(.system(size: 16, weight: .heavy))
                                } else {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .foregroundColor(.peacock)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                    } else {
                        Color.clear
                            .frame(width: 30, height: 30)
                    }

                    Spacer()

                    Button(action: onRightTap) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                .frame(width: 30, height: 30)
                            Image(systemName: "timer")
                                .foregroundColor(timer.isActive ? .peacock : .gray.opacity(0.5))
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .frame(width: 86, height: 96)
        .padding(2)
    }
}

