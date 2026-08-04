import Foundation

enum V2EXError: LocalizedError {
    case badStatus(Int)
    case needsToken
    case rateLimited(resetAt: Date?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回 \(code)"
        case .needsToken: return "这个功能需要在设置里填入 Personal Access Token"
        case .rateLimited(let reset):
            guard let reset else { return "请求过于频繁，请稍后再试" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "已达到 API 频率上限，\(formatter.string(from: reset)) 后恢复"
        case .decoding(let detail): return "解析失败：\(detail)"
        }
    }
}

/// API 2.0 wraps every payload in `{success, message, result}`.
private struct V2Envelope<Value: Decodable>: Decodable {
    let success: Bool?
    let message: String?
    let result: Value?
}

/// Talks to three surfaces:
/// * V2EX API 1.0 — public, no auth, powers everything read-only.
/// * V2EX API 2.0 — needs a Personal Access Token; notifications, own profile,
///   paginated node topics.
/// * sov2ex — the community full-text index, since V2EX exposes no search API.
actor V2EXClient {
    static let shared = V2EXClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Remaining quota reported by API 2.0, surfaced in settings.
    private(set) var rateLimitRemaining: Int?
    private(set) var rateLimitReset: Date?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "V2EX-SwiftUI/1.0 (iOS)",
            "Accept": "application/json",
        ]
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
    }

    // MARK: - API 1.0 (public)

    func latestTopics() async throws -> [V2Topic] {
        try await getV1("/api/topics/latest.json")
    }

    func hotTopics() async throws -> [V2Topic] {
        try await getV1("/api/topics/hot.json")
    }

    func topics(inNode name: String) async throws -> [V2Topic] {
        try await getV1("/api/topics/show.json", query: ["node_name": name])
    }

    func topics(byMember username: String) async throws -> [V2Topic] {
        try await getV1("/api/topics/show.json", query: ["username": username])
    }

    /// 话题详情：有 token 优先 API 2.0（维护中的接口，数据新鲜），
    /// 2.0 失败或无 token 回退 1.0。
    func topic(id: Int, token: String = "") async throws -> V2Topic {
        if !token.isEmpty, let v2 = try? await topicV2(id: id, token: token) {
            return v2
        }
        return try await topicV1(id: id)
    }

    private func topicV1(id: Int) async throws -> V2Topic {
        // v1 returns a single-element array here.
        let results: [V2Topic] = try await getV1("/api/topics/show.json", query: ["id": String(id)])
        guard let topic = results.first else { throw V2EXError.decoding("话题不存在或已删除") }
        return topic
    }

    func replies(topicID: Int) async throws -> [V2Reply] {
        try await getV1("/api/replies/show.json", query: ["topic_id": String(topicID)])
    }

    func allNodes() async throws -> [V2Node] {
        try await getV1("/api/nodes/all.json")
    }

    func node(name: String) async throws -> V2Node {
        try await getV1("/api/nodes/show.json", query: ["name": name])
    }

    func member(username: String) async throws -> V2Member {
        try await getV1("/api/members/show.json", query: ["username": username])
    }

    // MARK: - API 2.0 (token)

    /// Node topics with pagination — only API 2.0 offers `p`.
    func nodeTopicsPaged(name: String, page: Int, token: String) async throws -> [V2Topic] {
        try await getV2("/api/v2/nodes/\(name)/topics", query: ["p": String(page)], token: token)
    }

    /// Single topic via API 2.0 — v1's endpoints are unmaintained and return
    /// stale data for recent threads.
    private func topicV2(id: Int, token: String) async throws -> V2Topic {
        try await getV2("/api/v2/topics/\(id)", query: [:], token: token)
    }

    func topicRepliesPaged(id: Int, page: Int, token: String) async throws -> [V2Reply] {
        try await getV2("/api/v2/topics/\(id)/replies", query: ["p": String(page)], token: token)
    }

    func notifications(page: Int, token: String) async throws -> [V2Notification] {
        try await getV2("/api/v2/notifications", query: ["p": String(page)], token: token)
    }

    func deleteNotification(id: Int, token: String) async throws {
        var request = try makeRequest(path: "/api/v2/notifications/\(id)", query: [:])
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }

    func currentMember(token: String) async throws -> V2Member {
        try await getV2("/api/v2/member", query: [:], token: token)
    }

    struct TokenInfo: Codable {
        let token: String?
        let scope: String?
        let expiration: Int?
        let goodForDays: Int?
        let totalUsed: Int?
        let lastUsed: Int?
        let created: Int?

        enum CodingKeys: String, CodingKey {
            case token, scope, expiration, created
            case goodForDays = "good_for_days"
            case totalUsed = "total_used"
            case lastUsed = "last_used"
        }
    }

    func tokenInfo(token: String) async throws -> TokenInfo {
        try await getV2("/api/v2/token", query: [:], token: token)
    }

    // MARK: - Search (sov2ex)

    func search(query: String, from: Int = 0, size: Int = 20, sort: String = "sumup") async throws -> [SearchHit] {
        guard var components = URLComponents(string: "https://www.sov2ex.com/api/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "sort", value: sort),
        ]
        guard let url = components.url else { return [] }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        struct Envelope: Decodable {
            struct Hit: Decodable {
                struct Source: Decodable {
                    let id: Int
                    let title: String
                    let content: String
                    let node: Int
                    let member: String
                    let replies: Int
                    let created: String
                }
                struct Highlight: Decodable {
                    let title: [String]?
                    let content: [String]?
                }
                let _source: Source
                let highlight: Highlight?
            }
            let hits: [Hit]
        }

        let envelope = try decoder.decode(Envelope.self, from: data)
        return envelope.hits.map { hit in
            let source = hit._source
            let titleHTML = hit.highlight?.title?.first ?? source.title
            let contentHTML = hit.highlight?.content?.first ?? String(source.content.prefix(120))
            return SearchHit(
                id: source.id,
                title: source.title,
                content: source.content,
                node: String(source.node),
                member: source.member,
                replies: source.replies,
                created: source.created,
                titleSegments: Self.segments(from: titleHTML),
                contentSegments: Self.segments(from: contentHTML)
            )
        }
    }

    /// Splits sov2ex's `<em>`-marked HTML into plain/highlighted runs.
    nonisolated static func segments(from html: String) -> [HighlightSegment] {
        var segments: [HighlightSegment] = []
        var remainder = Substring(html)

        while let open = remainder.range(of: "<em>") {
            let before = String(remainder[remainder.startIndex..<open.lowerBound])
            if !before.isEmpty { segments.append(.init(text: HTMLText.decode(before), isMatch: false)) }
            remainder = remainder[open.upperBound...]

            guard let close = remainder.range(of: "</em>") else { break }
            let match = String(remainder[remainder.startIndex..<close.lowerBound])
            if !match.isEmpty { segments.append(.init(text: HTMLText.decode(match), isMatch: true)) }
            remainder = remainder[close.upperBound...]
        }
        if !remainder.isEmpty {
            segments.append(.init(text: HTMLText.decode(String(remainder)), isMatch: false))
        }
        return segments
    }

    // MARK: - Web scraping (view counts)

    /// V2EX's APIs don't expose view counts — the topic page is the only
    /// source. Parses `N views` (en) / `N 次点击` (zh) out of the HTML.
    /// Failure is silent: callers treat nil as "unknown".
    func topicViews(id: Int) async -> Int? {
        guard let url = URL(string: "https://www.v2ex.com/t/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        guard let range = html.range(
            of: #"([\d,]+)\s*(?:views|次点击)"#,
            options: .regularExpression
        ) else { return nil }
        return Int(String(html[range]).filter(\.isNumber))
    }

    // MARK: - Plumbing

    private func getV1<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try makeRequest(path: path, query: query)
        let data = try await perform(request)
        return try decode(T.self, from: data)
    }

    private func getV2<T: Decodable>(_ path: String, query: [String: String], token: String) async throws -> T {
        guard !token.isEmpty else { throw V2EXError.needsToken }
        var request = try makeRequest(path: path, query: query)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)

        let envelope = try decode(V2Envelope<T>.self, from: data)
        guard let result = envelope.result else {
            throw V2EXError.decoding(envelope.message ?? "接口没有返回内容")
        }
        return result
    }

    private func makeRequest(path: String, query: [String: String]) throws -> URLRequest {
        var components = URLComponents(string: "https://www.v2ex.com" + path)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw V2EXError.decoding("URL 构造失败") }
        return URLRequest(url: url)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }

        if let remaining = http.value(forHTTPHeaderField: "X-Rate-Limit-Remaining") {
            rateLimitRemaining = Int(remaining)
        }
        if let reset = http.value(forHTTPHeaderField: "X-Rate-Limit-Reset"), let stamp = TimeInterval(reset) {
            rateLimitReset = Date(timeIntervalSince1970: stamp)
        }

        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw V2EXError.needsToken
        case 429: throw V2EXError.rateLimited(resetAt: rateLimitReset)
        default: throw V2EXError.badStatus(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw V2EXError.decoding("\(error.localizedDescription) \(preview)")
        }
    }
}