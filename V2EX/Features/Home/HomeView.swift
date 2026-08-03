import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    enum Feed: Hashable {
        case following
        case latest
        case hot
        case node(name: String, title: String)

        var title: String {
            switch self {
            case .following: return "关注"
            case .latest: return "最新"
            case .hot: return "热门"
            case .node(_, let title): return title
            }
        }
    }

    @Published var feed: Feed = .following
    @Published private(set) var topics: [V2Topic] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var cache: [Feed: [V2Topic]] = [:]

    /// 关注 merges the newest topics of every followed node into one stream.
    func load(feed: Feed, followedNodes: [String], force: Bool = false) async {
        self.feed = feed

        if !force, let cached = cache[feed], !cached.isEmpty {
            topics = cached
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result: [V2Topic]
            switch feed {
            case .latest:
                result = try await V2EXClient.shared.latestTopics()
            case .hot:
                result = try await V2EXClient.shared.hotTopics()
            case .node(let name, _):
                result = try await V2EXClient.shared.topics(inNode: name)
            case .following:
                result = try await followingFeed(nodes: followedNodes)
            }
            cache[feed] = result
            topics = result
        } catch {
            errorMessage = (error as? V2EXError)?.errorDescription ?? error.localizedDescription
            topics = cache[feed] ?? []
        }
    }

    private func followingFeed(nodes: [String]) async throws -> [V2Topic] {
        guard !nodes.isEmpty else { return try await V2EXClient.shared.latestTopics() }

        var merged: [V2Topic] = []
        // Sequential rather than parallel: v1 has a shared 600/hour IP budget and
        // hammering it from a cold launch is the fastest way to get throttled.
        for name in nodes.prefix(6) {
            if let batch = try? await V2EXClient.shared.topics(inNode: name) {
                merged.append(contentsOf: batch)
            }
        }
        if merged.isEmpty { return try await V2EXClient.shared.latestTopics() }

        var seen = Set<Int>()
        return merged
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.lastTouched ?? 0) > ($1.lastTouched ?? 0) }
    }
}

struct HomeView: View {
    var onCompose: () -> Void
    var onSearch: () -> Void

    @StateObject private var model = HomeViewModel()
    @EnvironmentObject private var followed: FollowedNodesStore
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var readState: ReadStateStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var settings: AppSettings

    private var feeds: [HomeViewModel.Feed] {
        [.following, .latest, .hot] + followed.names.prefix(8).map {
            .node(name: $0, title: NodeCatalog.displayName(for: $0))
        }
    }

    private var visibleTopics: [V2Topic] { blocks.filter(model.topics) }

    var body: some View {
        content
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            // Fixed header: title, actions and the feed rail never move.
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .task {
                await model.load(feed: .following, followedNodes: followed.names)
            }
    }

    private var header: some View {
        ScreenHeader(title: "V2EX") {
            GlassCircleButton(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }
            GlassCircleButton(filled: true, action: onCompose) {
                Image(systemName: "plus")
            }
        } accessory: {
            ChipRail(items: feeds) { feed in
                FilterChip(title: feed.title, isSelected: model.feed == feed) {
                    Task { await model.load(feed: feed, followedNodes: followed.names) }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let message = model.errorMessage, visibleTopics.isEmpty {
                    EmptyStateCard(icon: "wifi.exclamationmark", title: "没能加载", message: message,
                                   actionTitle: "重试") {
                        Task { await model.load(feed: model.feed, followedNodes: followed.names, force: true) }
                    }
                } else if model.isLoading && visibleTopics.isEmpty {
                    LoadingCard()
                } else if visibleTopics.isEmpty {
                    EmptyStateCard(icon: "tray", title: "这里还没有话题")
                } else {
                    // Lead card, then the rest as a grouped list — as in the design.
                    if let featured = visibleTopics.first {
                        NavigationLink(value: Route.topic(featured.id)) {
                            CardSection(padding: 16) {
                                FeaturedTopicCard(
                                    topic: featured,
                                    badge: model.feed == .hot ? "今日最热" : "最新活跃"
                                )
                            }
                        }
                        .buttonStyle(.row)
                    }

                    TopicListCard(items: Array(visibleTopics.dropFirst())) { topic in
                        NavigationLink(value: Route.topic(topic.id)) {
                            TopicRow(
                                topic: topic,
                                isOffline: offline.isOffline(topic.id),
                                isRead: readState.isRead(topic.id),
                                dimRead: settings.dimReadTopics
                            )
                        }
                        .buttonStyle(.row)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .refreshable {
            await model.load(feed: model.feed, followedNodes: followed.names, force: true)
        }
    }
}
