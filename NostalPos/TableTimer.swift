//
//  TableTimer.swift
//  NostalPos
//

import Foundation
import SwiftUI

/// 每桌獨立計時器：從「開始點單」起算經過多久時間
///
/// - `elapsed`：已經過的秒數（TableCard 用這個去判斷綠 / 橘 / 紅）
/// - `startTime`：開始時間（TableCard 用 `startTime + 120 分鐘` 算「預計離桌時間」）
/// - `limitMinutes`：限制時間（預設 120 分鐘）
///
/// UI 行為：
/// - 卡片只顯示「兩小時後的時間」（expectedFinishText）
/// - 剩 30 分鐘：橘色（elapsed >= 90 分鐘）
/// - 超過 2 小時：紅色（elapsed >= 120 分鐘）
final class TableTimer: ObservableObject, Identifiable {
    let id = UUID()

    /// 開始計時的時間點；還沒開始時為 nil
    @Published var startTime: Date?

    /// 是否正在計時（控制 Timer 要不要跑）
    @Published var isActive: Bool = false

    /// 已經過了多少秒（從 startTime 開始算）
    @Published var elapsed: TimeInterval = 0

    /// 限制時間（分鐘）
    let limitMinutes: Int = 120

    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    // MARK: - 對外控制 -----------------------------

    /// 如果還沒開始，就從現在開始計時；已開始則繼續跑
    func start() {
        guard !isActive else { return }

        if startTime == nil {
            startTime = Date()
            elapsed = 0
        }

        isActive = true
        startInternalTimer()
    }

    /// 重新從「現在」開始計時（歸零再跑）
    func restart() {
        startTime = Date()
        elapsed = 0
        isActive = true
        startInternalTimer()
    }

    /// 暫停（保留已經累積的 elapsed，不歸零）
    func pause() {
        isActive = false
        timer?.invalidate()
        timer = nil
    }

    /// 停止（等同 pause，保留給舊程式碼使用）
    func stop() {
        pause()
    }

    /// 完全重置計時器：清桌時用
    ///
    /// - 停止 Timer
    /// - 將 elapsed 歸零
    /// - 將 startTime 設為 nil（卡片顯示 "--:--"）
    func reset() {
        isActive = false
        timer?.invalidate()
        timer = nil
        elapsed = 0
        startTime = nil
    }

    /// 從備份還原（如果你有把 elapsed / isActive 存起來的話）
    func restore(elapsed: TimeInterval, isActive: Bool) {
        // 1. 還原 elapsed（至少為 0）
        self.elapsed = max(0, elapsed)
        self.isActive = isActive

        // 2. 根據 elapsed 反推 startTime
        //    讓 Date() - startTime ≈ elapsed
        self.startTime = Date().addingTimeInterval(-self.elapsed)

        timer?.invalidate()
        if isActive {
            startInternalTimer()
        }
    }

    // MARK: - 內部計時邏輯 -------------------------

    private func startInternalTimer() {
        timer?.invalidate()

        guard let start = startTime else { return }

        // 先更新一次（避免要等一秒才跳）
        elapsed = max(0, Date().timeIntervalSince(start))

        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                     repeats: true) { [weak self] _ in
            guard let self = self,
                  self.isActive,
                  let start = self.startTime else { return }

            let newElapsed = max(0, Date().timeIntervalSince(start))

            DispatchQueue.main.async {
                self.elapsed = newElapsed
            }
        }
    }
}

