//  CameraPermissionManager.swift
//  NostalPos

import AVFoundation

final class CameraPermissionManager {
    static let shared = CameraPermissionManager()
    private init() {}

    func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            // 已經有權限
            completion(true)

        case .notDetermined:
            // 第一次：向系統要權限，這裡會跳出那個「是否允許」的視窗
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }

        case .denied, .restricted:
            // 使用者之前按過「不允許」或系統限制
            completion(false)

        @unknown default:
            completion(false)
        }
    }
}

