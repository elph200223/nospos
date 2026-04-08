//
//  LinePayCameraSheet.swift
//  NostalPos
//

import SwiftUI
import AVFoundation

// MARK: - 主視圖（掃描畫面）

struct LinePayCameraSheet: View {
    let onScanned: (String) -> Void
    let onCancel: () -> Void

    // ✅ 常駐相機：全 App 共用
    @ObservedObject private var cam = LinePayCameraManager.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 相機畫面（會把掃描區對準中間框）
            CameraPreview(session: cam.session) { scanRect, previewLayer in
                cam.updateRectOfInterest(scanRect: scanRect, previewLayer: previewLayer)
            }
            .ignoresSafeArea()

            // 上層 UI / 中間框
            VStack {
                VStack(spacing: 8) {
                    Text("LINE Pay 條碼掃描")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("請將客人的 QR Code 放到中間亮框內")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Text("若是條碼掃不到，請客人切換成 QR Code。")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)

                Spacer()

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(16)

                Spacer()

                if !cam.statusText.isEmpty {
                    Text(cam.statusText)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.bottom, 12)
                } else if !cam.isReady {
                    Text("相機啟動中…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 12)
                }

                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("取消掃描，返回結帳")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .foregroundColor(.red)
                        .cornerRadius(18)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
        .onAppear {
            // ✅ 每次打開掃碼畫面：重置掃碼狀態（但不重建 session）
            cam.onCodeScanned = { code in
                Task { @MainActor in
                    cam.statusText = "已讀取條碼，請稍候…"
                }

                print("🔍 掃到內容：\(code)")
                onScanned(code)

                // ✅ 掃到就關 sheet，但不關相機（讓下次瞬開）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    dismiss()
                }
            }

            cam.resetForNewScan()
        }
    }
}

// MARK: - CameraPreview：承載 AVCaptureVideoPreviewLayer，並回報中間掃描區

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onScanRectChanged: (CGRect, AVCaptureVideoPreviewLayer) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanRectChanged: onScanRectChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let layer = context.coordinator.previewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let layer = context.coordinator.previewLayer
        layer.frame = uiView.bounds

        // 固定成橫向（你 POS 幾乎一定是橫放 iPad）
        if let connection = layer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }

        // 計算「畫面中央 260x260」
        let size: CGFloat = 260
        let width = min(size, uiView.bounds.width * 0.9)
        let height = min(size, uiView.bounds.height * 0.9)
        let scanRect = CGRect(
            x: (uiView.bounds.width - width) / 2,
            y: (uiView.bounds.height - height) / 2,
            width: width,
            height: height
        )

        onScanRectChanged(scanRect, layer)
    }

    // MARK: - Coordinator
    class Coordinator {
        let previewLayer = AVCaptureVideoPreviewLayer()
        let onScanRectChanged: (CGRect, AVCaptureVideoPreviewLayer) -> Void

        init(onScanRectChanged: @escaping (CGRect, AVCaptureVideoPreviewLayer) -> Void) {
            self.onScanRectChanged = onScanRectChanged
        }
    }
}

