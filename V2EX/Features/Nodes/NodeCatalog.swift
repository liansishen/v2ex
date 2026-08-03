import SwiftUI

/// V2EX's `nodes/all.json` has no category field, so the 全部分类 groups in the
/// design come from the site's own tab membership, mirrored here.
enum NodeCatalog {
    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        let members: [String]

        /// Preview line under the category title.
        var subtitleSeed: [String] { Array(members.prefix(4)) }
    }

    static let categories: [Category] = [
        Category(id: "tech", title: "技术", icon: "chevron.left.forwardslash.chevron.right",
                 members: [
            "programmer", "python", "linux", "nodejs", "java", "php", "go", "rust",
            "javascript", "css", "cloud", "database", "docker", "kubernetes",
            "machinelearning", "openai", "network", "security", "vim", "git",
            "android", "idev", "flutter", "reactjs", "jobs",
        ]),
        Category(id: "creative", title: "创意", icon: "lightbulb.max",
                 members: [
            "create", "design", "ideas", "sandbox", "career", "startup",
            "sspai", "share", "writing", "productivity",
        ]),
        Category(id: "life", title: "生活", icon: "cup.and.saucer",
                 members: [
            "life", "coffee", "shanghai", "beijing", "shenzhen", "guangzhou",
            "hangzhou", "chengdu", "pets", "cat", "dog", "food", "health",
            "fitness", "travel", "car", "bicycle", "invest", "career",
        ]),
        Category(id: "play", title: "好玩", icon: "gamecontroller",
                 members: [
            "share", "games", "movie", "music", "tv", "anime", "books",
            "reading", "photograph", "nintendo", "steam", "playstation",
        ]),
        Category(id: "apple", title: "Apple", icon: "apple.logo",
                 members: [
            "apple", "macos", "iphone", "ipad", "macbookpro", "watchos",
            "visionpro", "appstore", "icloud", "airpods",
        ]),
        Category(id: "hardware", title: "硬件与自建", icon: "externaldrive",
                 members: [
            "nas", "hardware", "diy", "router", "keyboard", "monitor",
            "raspberrypi", "homelab", "vps", "domain", "idc",
        ]),
        Category(id: "jobs", title: "酷工作", icon: "briefcase",
                 members: [
            "jobs", "career", "outsourcing", "internship", "remotework",
        ]),
        Category(id: "deals", title: "交易", icon: "tag",
                 members: [
            "all4all", "exchange", "free", "dn", "tuan", "promotions",
        ]),
        Category(id: "qna", title: "问与答", icon: "questionmark.bubble",
                 members: [
            "qna", "howto", "search", "opensource",
        ]),
    ]

    /// Human-readable names for the nodes we reference before `all.json` lands.
    private static let seedTitles: [String: String] = [
        "programmer": "程序员", "create": "分享创造", "apple": "Apple", "coffee": "咖啡",
        "autistic": "自言自语", "life": "生活", "qna": "问与答", "jobs": "酷工作",
        "share": "分享发现", "nas": "NAS", "python": "Python", "linux": "Linux",
        "macos": "macOS", "iphone": "iPhone", "ipad": "iPad", "games": "游戏",
        "movie": "电影", "music": "音乐", "design": "设计", "career": "职场话题",
        "shanghai": "上海", "beijing": "北京", "hardware": "硬件", "cat": "猫",
        "invest": "投资", "ideas": "奇思妙想", "all4all": "二手交易", "health": "健康",
    ]

    /// Titles resolved from `all.json` at runtime; falls back to the seed table.
    private static var resolvedTitles: [String: String] = [:]

    static func register(nodes: [V2Node]) {
        for node in nodes { resolvedTitles[node.name] = node.title }
    }

    static func displayName(for name: String) -> String {
        resolvedTitles[name] ?? seedTitles[name] ?? name
    }

    static func subtitle(for category: Category) -> String {
        category.subtitleSeed.map(displayName(for:)).joined(separator: " · ")
    }
}