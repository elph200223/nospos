//
//  LinePayService.swift
//  NostalPos
//
//  LINE Pay Offline API v2: /v2/payments/oneTimeKeys/pay
//

import Foundation
import Network

// MARK: - Offline API 回傳結構

struct LinePayOfflineResult: Codable {
    let returnCode: String
    let returnMessage: String
    let info: Info?

    struct Info: Codable {
        let transactionId: Int64?
        let orderId: String?
        let transactionDate: String?
        let payInfo: [PayInfo]?
        let balance: Int?
    }

    struct PayInfo: Codable {
        let method: String?
        let amount: Int?
    }
}

// MARK: - LinePayService

final class LinePayService {

    static let shared = LinePayService()

    private init() {
        // ✅ 啟動網路監控：無網路時「立刻失敗」，不要傻等
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkOK = (path.status == .satisfied)
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Config

    private let offlineURL = URL(string: "https://api-pay.line.me/v2/payments/oneTimeKeys/pay")!

    // 這兩個你已經有
    private let channelId     = "1657619438"
    private let channelSecret = "20f91ca064fe145af7f2542b9bc5d15b"

    // 這兩個要跟 LINE Pay 要（Merchant Device 設定）
    private let deviceProfileId = "1PS1_92130254.POS"
    private let deviceType      = "Pos"

    // 付款請求需要足夠的等待時間，避免 LINE Pay 伺服器稍慢就誤判失敗
    private let requestTimeout: TimeInterval = 15    // 單次最多等 15 秒
    private let resourceTimeout: TimeInterval = 20   // 整體最多等 20 秒
    private let retryDelay: TimeInterval = 0.15      // 抖動時重試前的小延遲

    // MARK: - Network monitor

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "linepay.net.monitor")
    private var isNetworkOK: Bool = true

    // MARK: - URLSession (ephemeral + 不傻等連線)

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false                   // ✅ 不要等網路變好
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.timeoutIntervalForResource = resourceTimeout
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    // MARK: - Public

    func payOffline(
        amount: Int,
        orderId: String,
        productName: String,
        oneTimeKey: String,
        completion: @escaping (Result<LinePayOfflineResult, Error>) -> Void
    ) {
        // ✅ 無網路就立刻失敗，不要讓現場乾等
        if !isNetworkOK {
            let err = NSError(
                domain: "LinePayService",
                code: -1009,
                userInfo: [NSLocalizedDescriptionKey: "目前網路不穩或無連線，請重試或改付款方式"]
            )
            completion(.failure(err))
            return
        }

        var request = URLRequest(url: offlineURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 必填 Header
        request.setValue(channelId,         forHTTPHeaderField: "X-LINE-ChannelId")
        request.setValue(channelSecret,     forHTTPHeaderField: "X-LINE-ChannelSecret")
        request.setValue(deviceProfileId,   forHTTPHeaderField: "X-LINE-MerchantDeviceProfileId")
        request.setValue(deviceType,        forHTTPHeaderField: "X-LINE-MerchantDeviceType")

        // ✅ 再保險一次：每個 request 也設 timeout（避免吃到奇怪預設）
        request.timeoutInterval = requestTimeout

        let body: [String: Any] = [
            "amount": amount,
            "currency": "TWD",
            "orderId": orderId,
            "productName": productName,
            "oneTimeKey": oneTimeKey,
            "capture": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        // ✅ 只針對「常見網路抖動」重試一次
        runPayRequest(request, retried: false, completion: completion)
    }

    // MARK: - Private

    private func runPayRequest(
        _ request: URLRequest,
        retried: Bool,
        completion: @escaping (Result<LinePayOfflineResult, Error>) -> Void
    ) {
        self.session.dataTask(with: request) { data, response, error in

            // --- 網路錯誤：判斷是否需要重試一次 ---
            if let urlError = error as? URLError {
                let retryable: Set<URLError.Code> = [
                    .timedOut,
                    .cannotConnectToHost,
                    .networkConnectionLost,
                    .notConnectedToInternet,
                    .dnsLookupFailed,
                    .cannotFindHost
                ]

                if retryable.contains(urlError.code), !retried {
                    // 小延遲後重試一次（很多 Wi-Fi 抖動會直接救回）
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + self.retryDelay) {
                        self.runPayRequest(request, retried: true, completion: completion)
                    }
                    return
                }

                // 重試後仍 timeout：金流結果不明（LINE Pay 可能已扣款），用特殊錯誤碼通知呼叫端
                if urlError.code == .timedOut && retried {
                    let err = NSError(
                        domain: "LinePayService",
                        code: -1001,
                        userInfo: [NSLocalizedDescriptionKey: "付款結果不明：請確認客人 LINE Pay 是否已扣款，若已扣款請手動確認後再完成結帳。"]
                    )
                    completion(.failure(err))
                    return
                }
            }

            // --- 其他錯誤：直接回傳 ---
            if let error = error {
                print("❌ LinePayService：URLSession Error →", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                let err = NSError(
                    domain: "LinePayService",
                    code: -999,
                    userInfo: [NSLocalizedDescriptionKey: "Empty data"]
                )
                completion(.failure(err))
                return
            }

            // 需要 debug 再開，避免 log 太吵
            if let text = String(data: data, encoding: .utf8) {
                print("\n==============================")
                print("🔥 LINE Pay Offline 回傳原文：")
                print(text)
                print("==============================\n")
            }

            do {
                let result = try JSONDecoder().decode(LinePayOfflineResult.self, from: data)
                completion(.success(result))
            } catch {
                print("❌ JSON Decode 失敗：", error.localizedDescription)
                let err = NSError(
                    domain: "LinePayService",
                    code: -998,
                    userInfo: [NSLocalizedDescriptionKey: "JSON decode failed"]
                )
                completion(.failure(err))
            }

        }.resume()
    }
}

