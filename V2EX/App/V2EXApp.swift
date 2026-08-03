import SwiftUI

@main
struct V2EXApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var token = TokenStore()
    @StateObject private var followed = FollowedNodesStore()
    @StateObject private var readState = ReadStateStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var offline = OfflineStore()
    @StateObject private var recentSearches = RecentSearchStore()
    @StateObject private var blocks = BlockStore()
    @StateObject private var drafts = DraftStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(token)
                .environmentObject(followed)
                .environmentObject(readState)
                .environmentObject(favorites)
                .environmentObject(offline)
                .environmentObject(recentSearches)
                .environmentObject(blocks)
                .environmentObject(drafts)
                .preferredColorScheme(settings.theme.colorScheme)
                .tint(Theme.accent)
        }
    }
}
