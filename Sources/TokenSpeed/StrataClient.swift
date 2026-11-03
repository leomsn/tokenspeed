import Foundation

final class StrataClient {
    private let session: URLSession
    private let baseURL: URL
    private let apiKey: String?

    init(baseURL: URL, apiKey: String?) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3.0
        cfg.timeoutIntervalForResource = 3.0
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func fetchMetrics() async throws -> MetricsSnapshot {
        let (data, resp) = try await session.data(for: makeRequest(path: "metrics"))
        try Self.verify(resp: resp, data: data, expectsKey: apiKey != nil)
        do {
            return try JSONDecoder().decode(MetricsSnapshot.self, from: data)
        } catch let e as DecodingError {
            throw StrataError.decoding(Self.describe(e))
        }
    }

    private static func describe(_ e: DecodingError) -> String {
        let ctx: DecodingError.Context
        let info: String
        switch e {
        case .keyNotFound(let k, let c):     ctx = c; info = LF("缺 %1$@", k.stringValue)
        case .typeMismatch(let t, let c):    ctx = c; info = LF("类型 %1$@", String(describing: t))
        case .valueNotFound(let t, let c):   ctx = c; info = LF("值缺失 %1$@", String(describing: t))
        case .dataCorrupted(let c):          ctx = c; info = L("损坏")
        @unknown default:                     return "\(e)"
        }
        let path = ctx.codingPath.map { $0.stringValue }.joined(separator: ".")
        return "\(info) @ \(path.isEmpty ? "<root>" : path)"
    }

    func fetchHealth() async throws -> HealthStatus {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await session.data(for: req)
        try Self.verify(resp: resp, data: data, expectsKey: false)
        struct H: Decodable {
            let model: String?
            let max_context: Int?
            let api_key: Bool?
            let loaded: Bool?
        }
        let h = try JSONDecoder().decode(H.self, from: data)
        return .ok(
            model: h.model ?? "?",
            maxContext: h.max_context ?? 0,
            keyRequired: h.api_key ?? false,
            loaded: h.loaded ?? false
        )
    }

    private static func verify(resp: URLResponse, data: Data, expectsKey: Bool) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw StrataError.badResponse("not HTTP")
        }
        switch http.statusCode {
        case 200...299: return
        case 401, 403:
            throw StrataError.auth(http.statusCode)
        default:
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw StrataError.http(code: http.statusCode, body: body)
        }
    }
}

enum StrataError: LocalizedError, Equatable {
    case badResponse(String)
    case auth(Int)
    case http(code: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let s): return LF("响应异常: %1$@", s)
        case .auth(let c):        return LF("鉴权失败 (%1$d) — 检查 API key", c)
        case .http(let c, let b): return "HTTP \(c) \(b)"
        case .decoding(let s):    return LF("解析失败: %1$@", s)
        }
    }
}
