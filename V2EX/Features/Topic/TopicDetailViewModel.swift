import Foundation

@MainActor
final class TopicDetailViewModel: ObservableObject {
    enum ReplyFilter: String, CaseIterable, Identifiable {
        case byFloor, authorOnly
        var id: String { rawValue }

        var title: String {
            switch self {
            case .byFloor: return "按楼层"
            case .authorOnly: return "只看楼主"
            }
        }
    }

    @Published private(set) var topic: V2Topic?
    @Published private(set) var replies: [ThreadedReply] = []
    @Published private(set) var appends: [TopicAppend] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var repliesErrorMessage: String?
    @Published private(set) var loadedFromOffline = false
    @Published private(set) var topicViews: Int?
    @Published var filter: ReplyFilter = .byFloor

    private var rawReplies: [V2Reply] = []

    var visibleReplies: [ThreadedReply] {
        switch filter {
        case .byFloor: return replies
        case .authorOnly: return replies.filter(\.isAuthor)
        }
    }

    var contentBlocks: [ContentBlock] {
        guard let topic else { return [] }
        if let rendered = topic.contentRendered, !rendered.isEmpty {
            return HTMLText.blocks(from: rendered)
        }
        guard let content = topic.content, !content.isEmpty else { return [] }
        return content
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { .paragraph(AttributedString($0)) }
    }

    /// Raw payload for the offline snapshot.
    var offlinePayload: (V2Topic, [V2Reply])? {
        guard let topic else { return nil }
        return (topic, rawReplies)
    }

    func load(id: Int, token: String, cookie: String, offline: OfflineStore) async {
        isLoading = true
        errorMessage = nil
        repliesErrorMessage = nil
        appends = []
        defer { isLoading = false }

        // A saved topic renders immediately, then refreshes if the network is up.
        if let saved = offline.bundle(for: id) {
            topic = saved.topic
            rawReplies = saved.replies
            replies = Self.thread(saved.replies, authorName: saved.topic.authorName)
            loadedFromOffline = true
        }

        do {
            let fetched = try await V2EXClient.shared.topic(id: id, token: token)
            topic = fetched
            loadedFromOffline = false
        } catch {
            if topic == nil {
                errorMessage = (error as? V2EXError)?.errorDescription ?? error.localizedDescription
            }
            return
        }

        // Replies are a separate request — a failure here must not masquerade
        // as "no replies" on a thread that clearly has some.
        do {
            let fetchedReplies: [V2Reply]
            if !token.isEmpty {
                // API 2.0 is the maintained surface — v1's replies endpoint
                // returns stale/empty data for recent threads, so don't gate
                // it behind the 100-reply long-thread heuristic.
                // 热门帖分页并行拉取（各页独立），再按 id 恢复时间顺序。
                let total = topic?.replies ?? 0
                // v2 replies 每页固定 20 条（实测 p=1 返回 20 条），不是 100 条。
                // 按 100 算页数会把 >20 回复的帖子的最新评论丢在未请求的页里。
                // 20 页 × 20 条 = 400 条封顶，覆盖绝大多数帖子。
                let pageCount = min(20, max(1, Int(ceil(Double(total) / 20.0))))
                var collected: [V2Reply] = []
                try await withThrowingTaskGroup(of: [V2Reply].self) { group in
                    for page in 1...pageCount {
                        group.addTask {
                            try await V2EXClient.shared.topicRepliesPaged(id: id, page: page, token: token)
                        }
                    }
                    for try await batch in group {
                        collected.append(contentsOf: batch)
                    }
                }
                fetchedReplies = collected.sorted { $0.id < $1.id }
            } else {
                fetchedReplies = try await V2EXClient.shared.replies(topicID: id)
            }

            rawReplies = fetchedReplies
            replies = Self.thread(fetchedReplies, authorName: topic?.authorName ?? "")
        } catch {
            repliesErrorMessage = (error as? V2EXError)?.errorDescription ?? error.localizedDescription
        }

        // 浏览数与附言都来自同一个话题页 —— 一次网页抓取解析两者，
        // 避免热门帖串行发两个网页请求拖慢首屏。
        if topicViews == nil || (!cookie.isEmpty && appends.isEmpty) {
            if let extras = try? await V2EXClient.shared.topicPageExtras(id: id, cookie: cookie) {
                if topicViews == nil { topicViews = extras.views }
                if !extras.appends.isEmpty { appends = extras.appends }
            }
        }
    }

    // MARK: Quote threading

    /// V2EX has no reply-to field: a quote is expressed in the body as
    /// `@someone` (optionally `#12`). Resolve those mentions against the
    /// already-numbered replies so the design's fold-quote block can be drawn.
    static func thread(_ replies: [V2Reply], authorName: String) -> [ThreadedReply] {
        var floorsByAuthor: [String: [Int]] = [:]
        var repliesByFloor: [Int: V2Reply] = [:]

        var result: [ThreadedReply] = []
        result.reserveCapacity(replies.count)

        for (index, reply) in replies.enumerated() {
            let floor = index + 1
            repliesByFloor[floor] = reply

            let quoted = resolveQuote(
                in: reply,
                floorsByAuthor: floorsByAuthor,
                repliesByFloor: repliesByFloor
            )

            result.append(ThreadedReply(
                reply: reply,
                floor: floor,
                quoted: quoted,
                isAuthor: !authorName.isEmpty && reply.authorName == authorName
            ))

            floorsByAuthor[reply.authorName, default: []].append(floor)
        }
        return result
    }

    private static func resolveQuote(
        in reply: V2Reply,
        floorsByAuthor: [String: [Int]],
        repliesByFloor: [Int: V2Reply]
    ) -> ThreadedReply.QuotedReply? {
        let text = reply.content
        guard let atIndex = text.firstIndex(of: "@") else { return nil }

        // Only treat a mention as a quote when it opens the reply.
        let prefix = text[text.startIndex..<atIndex]
        guard prefix.allSatisfy({ $0.isWhitespace || $0 == ">" }) else { return nil }

        var cursor = text.index(after: atIndex)
        var username = ""
        while cursor < text.endIndex {
            let character = text[cursor]
            guard character.isLetter || character.isNumber || character == "_" || character == "-" else { break }
            username.append(character)
            cursor = text.index(after: cursor)
        }
        guard username.count >= 2 else { return nil }

        // Optional explicit floor: "@user #12".
        var explicitFloor: Int?
        var probe = cursor
        while probe < text.endIndex, text[probe] == " " { probe = text.index(after: probe) }
        if probe < text.endIndex, text[probe] == "#" {
            var digits = ""
            var digitCursor = text.index(after: probe)
            while digitCursor < text.endIndex, text[digitCursor].isNumber {
                digits.append(text[digitCursor])
                digitCursor = text.index(after: digitCursor)
            }
            explicitFloor = Int(digits)
        }

        // Fall back to the mentioned user's most recent floor above this one.
        let floor = explicitFloor ?? floorsByAuthor[username]?.last
        guard let floor, let quoted = repliesByFloor[floor] else {
            return ThreadedReply.QuotedReply(username: username, floor: explicitFloor, excerpt: "")
        }

        let excerpt = HTMLText.plain(quoted.contentRendered ?? quoted.content)
        return ThreadedReply.QuotedReply(
            username: username,
            floor: floor,
            excerpt: excerpt.count > 40 ? String(excerpt.prefix(40)) + "…" : excerpt
        )
    }

    /// Body with the leading `@user #n` stripped — it's shown in the quote block.
    static func bodyWithoutQuotePrefix(_ reply: ThreadedReply) -> String {
        let source = reply.reply.contentRendered ?? reply.reply.content
        guard reply.quoted != nil else { return source }

        let plain = HTMLText.plain(source)
        guard plain.hasPrefix("@") else { return source }

        // Drop everything up to the first whitespace run after the mention.
        var remainder = Substring(plain).dropFirst()
        remainder = remainder.drop { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        remainder = remainder.drop { $0.isWhitespace }
        if remainder.first == "#" {
            remainder = remainder.dropFirst().drop { $0.isNumber }
            remainder = remainder.drop { $0.isWhitespace }
        }
        return remainder.isEmpty ? source : String(remainder)
    }
}