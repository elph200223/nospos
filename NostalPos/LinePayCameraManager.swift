//
//  LinePayCameraManager.swift
//  NostalPos
//
//  常駐相機：全 App 共用同一個 AVCaptureSession，避免每次掃碼冷啟動
//  掃描策略：不再依賴 rectOfInterest 限死掃描區，改成全 frame 掃描後，
//  只接受「落在畫面掃描框內」的 QR，避免 ROI 轉換偏移導致畫面正常卻掃不到。
//

import Foundation
import AVFoundation
import UIKit

final class LinePayCameraManager: NSObject, ObservableObject {
    static let shared = LinePayCameraManager()

    // 對外提供 session 給 PreviewLayer
    let session = AVCaptureSession()

    private let metadataQueue = DispatchQueue(
        label: "linepay.camera.metadata.queue",
        qos: .userInitiated
    )

    // 狀態
    @MainActor @Published var statusText: String = ""
    @MainActor @Published var isReady: Bool = false

    // 掃碼回呼
    var onCodeScanned: ((String) -> Void)?

    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "linepay.camera.session.queue", qos: .userInitiated)

    // MARK: - 掃描狀態保護
    private let scanStateLock = NSLock()
    private var didScanOnce = false

    private var isConfigured = false
    private var isStarting = false
    private var observersInstalled = false

    // MARK: - 掃描框命中判定
    private let overlayLock = NSLock()
    private weak var previewLayerRef: AVCaptureVideoPreviewLayer?
    private var scanRectInLayer: CGRect = .zero

    private override init() {
        super.init()
        installObserversIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func warmUp() {
        ensureRunning()
    }

    func ensureRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.isStarting { return }
            self.isStarting = true

            let auth = AVCaptureDevice.authorizationStatus(for: .video)
            switch auth {
            case .authorized:
                self.configureIfNeededAndStart()

            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.sessionQueue.async {
                        if granted {
                            self.configureIfNeededAndStart()
                        } else {
                            Task { @MainActor in
                                self.statusText = "未授權使用相機\n請到「設定 > 隱私權 > 相機」開啟權限"
                                self.isReady = false
                            }
                            self.isStarting = false
                        }
                    }
                }

            default:
                Task { @MainActor in
                    self.statusText = "未授權使用相機\n請到「設定 > 隱私權 > 相機」開啟權限"
                    self.isReady = false
                }
                self.isStarting = false
            }
        }
    }

    func stopIfRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            Task { @MainActor in
                self.isReady = false
            }
        }
    }

    func resetForNewScan() {
        setDidScanOnce(false)

        Task { @MainActor in
            self.statusText = ""
        }

        ensureRunning()
    }

    /// UI 每次 layout 後把掃描框與 previewLayer 回傳進來。
    /// 這版不再把它轉成 rectOfInterest，而是用來做「畫面框內命中判定」。
    func updateRectOfInterest(scanRect: CGRect, previewLayer: AVCaptureVideoPreviewLayer) {
        overlayLock.lock()
        previewLayerRef = previewLayer
        scanRectInLayer = scanRect.integral
        overlayLock.unlock()
    }

    // MARK: - Private

    private func configureIfNeededAndStart() {
        if !isConfigured {
            configureSession()
        }

        guard isConfigured else {
            isStarting = false
            return
        }

        restartSessionIfNeeded()

        Task { @MainActor in
            self.statusText = ""
            self.isReady = self.session.isRunning
        }

        isStarting = false
    }

    private func configureSession() {
        guard !isConfigured else { return }

        guard let device = AVCaptureDevice.default(for: .video) else {
            Task { @MainActor in
                self.statusText = "找不到相機裝置"
                self.isReady = false
            }
            isStarting = false
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            session.beginConfiguration()
            session.sessionPreset = .high

            if session.canAddInput(input) {
                session.addInput(input)
            }

            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
            }

            configureMetadataOutput()

            session.commitConfiguration()
            isConfigured = true

        } catch {
            Task { @MainActor in
                self.statusText = "初始化相機失敗：\(error.localizedDescription)"
                self.isReady = false
            }
            isStarting = false
        }
    }

    private func configureMetadataOutput() {
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
        metadataOutput.metadataObjectTypes = [.qr]

        if let conn = metadataOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .landscapeRight
        }

        // 不用 ROI 限死；由後續命中判定決定是否接受。
        metadataOutput.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func restartSessionIfNeeded() {
        configureMetadataOutput()

        if !session.isRunning {
            session.startRunning()
        }
    }

    private func hardResetSessionAndRestart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.setDidScanOnce(false)

            if self.session.isRunning {
                self.session.stopRunning()
            }

            if self.isConfigured {
                self.session.beginConfiguration()

                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }

                if self.session.canAddOutput(self.metadataOutput) {
                    self.session.addOutput(self.metadataOutput)
                }

                self.configureMetadataOutput()
                self.session.commitConfiguration()
            }

            self.restartSessionIfNeeded()

            Task { @MainActor in
                self.isReady = self.session.isRunning
                if self.session.isRunning {
                    if self.statusText == "相機已中斷，正在恢復…" ||
                        self.statusText == "掃描恢復中…" {
                        self.statusText = ""
                    }
                } else {
                    self.statusText = "掃描恢復失敗，請重新開啟掃描"
                }
            }
        }
    }

    private func setDidScanOnce(_ newValue: Bool) {
        scanStateLock.lock()
        didScanOnce = newValue
        scanStateLock.unlock()
    }

    private func tryMarkScanned() -> Bool {
        scanStateLock.lock()
        defer { scanStateLock.unlock() }

        if didScanOnce {
            return false
        }

        didScanOnce = true
        return true
    }

    private func shouldAcceptScannedObject(_ obj: AVMetadataMachineReadableCodeObject) -> Bool {
        overlayLock.lock()
        let previewLayer = previewLayerRef
        let scanRect = scanRectInLayer
        overlayLock.unlock()

        guard let previewLayer else {
            // 若 UI 尚未回報框位置，保守接受，避免完全掃不到。
            return true
        }

        guard !scanRect.isEmpty, !scanRect.isNull, scanRect.width > 1, scanRect.height > 1 else {
            return true
        }

        guard let transformed = previewLayer.transformedMetadataObject(for: obj) as? AVMetadataMachineReadableCodeObject else {
            return false
        }

        let candidateBounds = transformed.bounds
        if candidateBounds.isEmpty || candidateBounds.isNull {
            return false
        }

        let candidateCenter = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
        return scanRect.contains(candidateCenter)
    }

    // MARK: - Observers

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )

        center.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )

        center.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )

        center.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc
    private func handleSessionWasInterrupted(_ notification: Notification) {
        Task { @MainActor in
            self.isReady = false
            self.statusText = "相機已中斷，正在恢復…"
        }
    }

    @objc
    private func handleSessionInterruptionEnded(_ notification: Notification) {
        Task { @MainActor in
            self.statusText = "掃描恢復中…"
        }
        hardResetSessionAndRestart()
    }

    @objc
    private func handleSessionRuntimeError(_ notification: Notification) {
        Task { @MainActor in
            self.isReady = false
            self.statusText = "掃描恢復中…"
        }
        hardResetSessionAndRestart()
    }

    @objc
    private func handleAppDidBecomeActive() {
        hardResetSessionAndRestart()
    }

    @objc
    private func handleAppWillResignActive() {
        stopIfRunning()
    }
}

// MARK: - Delegate

extension LinePayCameraManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue,
              !value.isEmpty
        else {
            return
        }

        guard shouldAcceptScannedObject(obj) else { return }
        guard tryMarkScanned() else { return }

        Task { @MainActor in
            self.statusText = "已讀取條碼…"
        }

        onCodeScanned?(value)
    }
}
