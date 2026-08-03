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
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
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

    func load(id: Int, token: String, offline: OfflineStore) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // A saved topic renders immediately, then refreshes if the network is up.
        if let saved = offline.bundle(for: id) {
            topic = saved.topic
            rawReplies = saved.replies
            replies = Self.thread(saved.replies, authorName: saved.topic.authorName)
            loadedFromOffline = true
        }

        do {
            let fetched = try await V2EXClient.shared.topic(id: id)
            topic = fetched
            loadedFromOffline = false

            let fetchedReplies: [V2Reply]
            if !token.isEmpty, fetched.replies > 100 {
                // Long threads need API 2.0's pagination — v1 caps out.
                var collected: [V2Reply] = []
                var page = 1
                while collected.count < fetched.replies, page <= 12 {
                    let batch = try await V2EXClient.shared.topicRepliesPaged(
                        id: id, page: page, token: token
                    )
                    if batch.isEmpty { break }
                    collected.append(contentsOf: batch)
                    page += 1
                }
                fetchedReplies = collected
            } else {
                fetchedReplies = try await V2EXClient.shared.replies(topicID: id)
            }

            rawReplies = fetchedReplies
            replies = Self.thread(fetchedReplies, authorName: fetched.authorName)
            // View counts aren't in any API — scrape the topic page once.
            if topicViews == nil {
                topicViews = await V2EXClient.shared.topicViews(id: id)
            }
        } catch {
            if topic == nil {
                errorMessage = (error as? V2EXError)?.errorDescription ?? error.localizedDescription
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