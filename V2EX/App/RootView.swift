import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case home, nodes, notifications, profile
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .nodes: return "节点"
        case .notifications: return "通知"
        case .profile: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .nodes: return "square.grid.2x2"
        case .notifications: return "bell"
        case .profile: return "person"
        }
    }

}

/// Destinations pushed onto any tab's navigation stack.
enum Route: Hashable {
    case topic(Int)
    case node(String)
    case member(String)
    case favorites
    case offline
    case myPosts
    case blocked
    case settings
    case appearance
    case tokenSetup
}

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var paths: [AppTab: NavigationPath] = [:]
    @State private var showCompose = false
    @State private var showSearch = false

    /// Debug launch helper — lets automation open a topic directly:
    /// `simctl launch booted com.vibe.v2ex -openTopic 1231572`
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-openTopic"),
           flag + 1 < arguments.count,
           let id = Int(arguments[flag + 1]) {
            var path = NavigationPath()
            path.append(Route.topic(id))
            _paths = State(initialValue: [.home: path])
        }
    }

    @EnvironmentObject private var token: TokenStore
    @StateObject private var notifications = NotificationsViewModel()

    var body: some View {
        // The native iOS 26 tab bar *is* the design's floating glass pill —
        // including the scroll-away minimise behaviour.
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    NavigationStack(path: binding(for: tab)) {
                        screen(for: tab)
                            .navigationDestination(for: Route.self) { route in
                                destination(route)
                            }
                    }
                }
                .badge(tab == .notifications ? notifications.unreadCount : 0)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: $showCompose) { ComposeView() }
        .fullScreenCover(isPresented: $showSearch) { SearchView() }
        .environmentObject(notifications)
        .task(id: token.token) {
            await notifications.refresh(token: token.token)
        }
    }

    /// Re-selecting the active tab pops it back to root, like the system bar.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection { paths[newValue] = NavigationPath() }
                selection = newValue
            }
        )
    }

    private func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] ?? NavigationPath() },
            set: { paths[tab] = $0 }
        )
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(onCompose: { showCompose = true }, onSearch: { showSearch = true })
        case .nodes:
            NodesView()
        case .notifications:
            NotificationsView()
        case .profile:
            ProfileView()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .topic(let id): TopicDetailView(topicID: id)
        case .node(let name): NodeDetailView(nodeName: name)
        case .member(let name): MemberView(username: name)
        case .favorites: FavoritesView()
        case .offline: OfflineListView()
        case .myPosts: MyPostsView()
        case .blocked: BlockedView()
        case .settings: SettingsView()
        case .appearance: AppearanceSettingsView()
        case .tokenSetup: TokenSetupView()
        }
    }
}
