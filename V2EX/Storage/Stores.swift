import Foundation
import Security
import SwiftUI

// MARK: - Token (Keychain)

/// Personal Access Token for API 2.0. Kept in the keychain, not UserDefaults.
@MainActor
final class TokenStore: ObservableObject {
    @Published private(set) var token: String = ""

    private let service = "com.vibe.v2ex.pat"
    private let account = "default"

    var hasToken: Bool { !token.isEmpty }

    init() {
        token = read() ?? ""
    }

    func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        token = trimmed
        delete()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        token = ""
        delete()
    }

    private func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Followed nodes

@MainActor
final class FollowedNodesStore: ObservableObject {
    @Published private(set) var names: [String] = []

    private let key = "followedNodes"
    /// Seeded so a fresh install has a meaningful 关注 tab, matching the design.
    private let defaults = ["programmer", "create", "apple", "coffee", "autistic"]

    init() {
        if let stored = UserDefaults.standard.stringArray(forKey: key) {
            names = stored
        } else {
            names = defaults
            persist()
        }
    }

    func isFollowing(_ name: String) -> Bool { names.contains(name) }

    func toggle(_ name: String) {
        if let index = names.firstIndex(of: name) {
            names.remove(at: index)
        } else {
            names.append(name)
        }
        persist()
    }

    func remove(_ name: String) {
        names.removeAll { $0 == name }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        names.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(names, forKey: key)
    }
}

// MARK: - Read state

/// Topic IDs already opened, so 已读的话题变灰 can work.
@MainActor
final class ReadStateStore: ObservableObject {
    @Published private(set) var readIDs: Set<Int> = []
    /// Reply index to restore when 记住阅读进度 is on.
    @Published private(set) var positions: [Int: Int] = [:]

    private let readKey = "readTopicIDs"
    private let positionKey = "readingPositions"

    init() {
        readIDs = Set(UserDefaults.standard.array(forKey: readKey) as? [Int] ?? [])
        let stored = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Int] ?? [:]
        positions = stored.reduce(into: [:]) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        }
    }

    func isRead(_ id: Int) -> Bool { readIDs.contains(id) }

    func markRead(_ id: Int) {
        guard !readIDs.contains(id) else { return }
        readIDs.insert(id)
        // Cap the history so the default store stays small.
        if readIDs.count > 2_000 { readIDs = Set(readIDs.suffix(1_500)) }
        UserDefaults.standard.set(Array(readIDs), forKey: readKey)
    }

    func rememberPosition(_ floor: Int, for topicID: Int) {
        positions[topicID] = floor
        let encoded = positions.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }
        UserDefaults.standard.set(encoded, forKey: positionKey)
    }

    func position(for topicID: Int) -> Int? { positions[topicID] }
}

// MARK: - Favourites

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var topics: [V2Topic] = []

    private let file = DiskStore.url(for: "favorites.json")

    init() {
        topics = DiskStore.load([V2Topic].self, from: file) ?? []
    }

    func contains(_ id: Int) -> Bool { topics.contains { $0.id == id } }

    func toggle(_ topic: V2Topic) {
        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
            topics.remove(at: index)
        } else {
            topics.insert(topic, at: 0)
        }
        DiskStore.save(topics, to: file)
    }
}

// MARK: - Offline

/// "稍后读 / 离线" — topic body plus replies written to disk so a saved topic
/// opens with no network at all.
@MainActor
final class OfflineStore: ObservableObject {
    struct SavedTopic: Codable, Identifiable {
        let topic: V2Topic
        let replies: [V2Reply]
        let savedAt: Date
        var id: Int { topic.id }
    }

    @Published private(set) var bundles: [SavedTopic] = []
    @Published private(set) var byteSize: Int = 0

    private let directory = DiskStore.directory(named: "Offline")

    init() {
        reload()
    }

    func isOffline(_ id: Int) -> Bool { bundles.contains { $0.id == id } }

    func bundle(for id: Int) -> SavedTopic? { bundles.first { $0.id == id } }

    func save(topic: V2Topic, replies: [V2Reply]) {
        let saved = SavedTopic(topic: topic, replies: replies, savedAt: Date())
        DiskStore.save(saved, to: directory.appendingPathComponent("\(topic.id).json"))
        reload()
    }

    func remove(id: Int) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
        reload()
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        reload()
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    private func reload() {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []

        var loaded: [SavedTopic] = []
        var total = 0
        for file in files where file.pathExtension == "json" {
            if let saved = DiskStore.load(SavedTopic.self, from: file) { loaded.append(saved) }
            let values = try? file.resourceValues(forKeys: [.fileSizeKey])
            total += values?.fileSize ?? 0
        }
        bundles = loaded.sorted { $0.savedAt > $1.savedAt }
        byteSize = total
    }
}

// MARK: - Recent searches

@MainActor
final class RecentSearchStore: ObservableObject {
    @Published private(set) var queries: [String] = []
    private let key = "recentSearches"

    init() {
        queries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        queries.insert(trimmed, at: 0)
        queries = Array(queries.prefix(12))
        UserDefaults.standard.set(queries, forKey: key)
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        UserDefaults.standard.set(queries, forKey: key)
    }

    func clear() {
        queries = []
        UserDefaults.standard.set(queries, forKey: key)
    }
}

// MARK: - Block list

/// 屏蔽的关键词与用户 — applied to every topic list before it reaches a view.
@MainActor
final class BlockStore: ObservableObject {
    @Published private(set) var keywords: [String] = []
    @Published private(set) var usernames: [String] = []

    private let keywordKey = "blockedKeywords"
    private let userKey = "blockedUsernames"

    init() {
        keywords = UserDefaults.standard.stringArray(forKey: keywordKey) ?? []
        usernames = UserDefaults.standard.stringArray(forKey: userKey) ?? []
    }

    var count: Int { keywords.count + usernames.count }

    func addKeyword(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !keywords.contains(trimmed) else { return }
        keywords.append(trimmed)
        UserDefaults.standard.set(keywords, forKey: keywordKey)
    }

    func addUsername(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !usernames.contains(trimmed) else { return }
        usernames.append(trimmed)
        UserDefaults.standard.set(usernames, forKey: userKey)
    }

    func removeKeyword(_ value: String) {
        keywords.removeAll { $0 == value }
        UserDefaults.standard.set(keywords, forKey: keywordKey)
    }

    func removeUsername(_ value: String) {
        usernames.removeAll { $0 == value }
        UserDefaults.standard.set(usernames, forKey: userKey)
    }

    func filter(_ topics: [V2Topic]) -> [V2Topic] {
        guard count > 0 else { return topics }
        return topics.filter { topic in
            if usernames.contains(where: { $0.caseInsensitiveCompare(topic.authorName) == .orderedSame }) {
                return false
            }
            let haystack = topic.title + " " + (topic.content ?? "")
            return !keywords.contains { haystack.localizedCaseInsensitiveContains($0) }
        }
    }
}

// MARK: - Compose draft

@MainActor
final class DraftStore: ObservableObject {
    struct Draft: Codable {
        var nodeName: String
        var nodeTitle: String
        var title: String
        var body: String
        var savedAt: Date
    }

    @Published var draft: Draft
    private let file = DiskStore.url(for: "draft.json")

    init() {
        draft = DiskStore.load(Draft.self, from: file)
            ?? Draft(nodeName: "create", nodeTitle: "分享创造", title: "", body: "", savedAt: Date())
    }

    func save() {
        draft.savedAt = Date()
        DiskStore.save(draft, to: file)
    }

    var savedAtText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: draft.savedAt)
    }

    var isEmpty: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Disk helpers

enum DiskStore {
    static func directory(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for file: String) -> URL {
        directory(named: "V2EXData").appendingPathComponent(file)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
