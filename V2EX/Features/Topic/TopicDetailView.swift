import SwiftUI

struct TopicDetailView: View {
    let topicID: Int

    @StateObject private var model = TopicDetailViewModel()
    @EnvironmentObject private var token: TokenStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var readState: ReadStateStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let topic = model.topic {
                            topicCard(topic)
                            replyHeader(topic)
                            replyList
                        } else if model.isLoading {
                            LoadingCard().padding(.top, 8)
                        } else if let message = model.errorMessage {
                            EmptyStateCard(icon: "exclamationmark.triangle", title: "打不开这个话题",
                                           message: message, actionTitle: "在 V2EX 打开") {
                                openURL(URL(string: "https://www.v2ex.com/t/\(topicID)")!)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.replies.count) { _, count in
                    guard settings.rememberReadingPosition, count > 0,
                          let floor = readState.position(for: topicID), floor > 1 else { return }
                    // Restore where the reader left off.
                    if let target = model.replies.first(where: { $0.floor == floor }) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }

            replyComposer
        }
        .navigationBarTitleDisplayMode(.inline)
        // The floating reply composer owns the bottom of this screen.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .task {
            readState.markRead(topicID)
            await model.load(id: topicID, token: token.token, offline: offline)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let node = model.topic?.node {
                NavigationLink(value: Route.node(node.name)) {
                    Text(node.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button {
                    if let topic = model.topic { favorites.toggle(topic) }
                } label: {
                    Image(systemName: favorites.contains(topicID) ? "star.fill" : "star")
                        .foregroundStyle(favorites.contains(topicID) ? Theme.amber : Theme.body)
                }
                Menu {
                    Button {
                        toggleOffline()
                    } label: {
                        Label(
                            offline.isOffline(topicID) ? "移除离线内容" : "保存以离线阅读",
                            systemImage: offline.isOffline(topicID) ? "trash" : "arrow.down.circle"
                        )
                    }
                    if let topic = model.topic {
                        ShareLink(item: topic.webURL) { Label("分享", systemImage: "square.and.arrow.up") }
                        Button {
                            openURL(topic.webURL)
                        } label: {
                            Label("在 V2EX 打开", systemImage: "safari")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.body)
                }
            }
        }
    }

    private func toggleOffline() {
        if offline.isOffline(topicID) {
            offline.remove(id: topicID)
        } else if let (topic, replies) = model.offlinePayload {
            offline.save(topic: topic, replies: replies)
        }
    }

    // MARK: Topic card

    private func topicCard(_ topic: V2Topic) -> some View {
        CardSection(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(topic.title)
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.5)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    NavigationLink(value: Route.member(topic.authorName)) {
                        HStack(spacing: 9) {
                            IdentitySquare(text: topic.authorName, size: 30, imageURL: topic.member?.avatarURL)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(topic.authorName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(RelativeTime.string(from: topic.activityDate))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                                if let views = model.topicViews {
                                    Text("\(views.formatted()) 次阅读")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)
                    if offline.isOffline(topicID) { OfflineBadge() }
                }

                Rectangle().fill(Theme.separator).frame(height: Theme.Metric.hairline)

                let blocks = model.contentBlocks
                if blocks.isEmpty {
                    Text("（本帖没有正文）")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                } else {
                    ContentBlocksView(blocks: blocks)
                }
            }
        }
    }

    // MARK: Replies

    private func replyHeader(_ topic: V2Topic) -> some View {
        HStack {
            Text("\(topic.replies) 条回复")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            HStack(spacing: 6) {
                ForEach(TopicDetailViewModel.ReplyFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy) { model.filter = filter }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(model.filter == filter ? Theme.accent : Theme.muted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                model.filter == filter
                                    ? AnyShapeStyle(Theme.accentSoft)
                                    : AnyShapeStyle(Theme.inset)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.Metric.screenPadding + 6)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var replyList: some View {
        let items = model.visibleReplies
        if items.isEmpty {
            if model.isLoading {
                LoadingCard()
            } else {
                EmptyStateCard(icon: "bubble.left", title: "还没有回复")
            }
        } else {
            CardSection {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ReplyRow(item: item)
                        .id(item.id)
                        .onAppear {
                            guard settings.rememberReadingPosition else { return }
                            readState.rememberPosition(item.floor, for: topicID)
                        }
                    if index < items.count - 1 {
                        RowSeparator(leadingInset: 59)
                    }
                }
            }
        }
    }

    // MARK: Composer

    /// Floating Liquid Glass composer. The field and the send button live in one
    /// GlassEffectContainer so their glass blends instead of stacking.
    private var replyComposer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Text("写下你的回复…")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .padding(.trailing, 12)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .onTapGesture {
                        // API 2.0 has no reply endpoint — hand off to the web composer.
                        openURL(URL(string: "https://www.v2ex.com/t/\(topicID)#reply")!)
                    }

                Button {
                    openURL(URL(string: "https://www.v2ex.com/t/\(topicID)#reply")!)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
            }
        }
        .padding(.horizontal, Theme.Metric.screenPadding)
        .padding(.bottom, 8)
    }
}

// MARK: - Reply row

struct ReplyRow: View {
    let item: ThreadedReply
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            NavigationLink(value: Route.member(item.reply.authorName)) {
                IdentitySquare(
                    text: item.reply.authorName,
                    size: 32,
                    imageURL: item.reply.member?.avatarURL
                )
            }
            .buttonStyle(.plain)
            .fixedSize()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.reply.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if item.isAuthor {
                        Text("楼主")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Text(RelativeTime.string(from: item.reply.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Text("#\(item.floor)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }

                if let quoted = item.quoted {
                    quoteBlock(quoted)
                }

                // Block renderer, not inline: replies can carry images, and
                // the inline path collapses `<img>` to a "[图片]" link.
                ContentBlocksView(
                    blocks: HTMLText.blocks(from: TopicDetailViewModel.bodyWithoutQuotePrefix(item)),
                    fontSize: settings.bodyFontSize - 1,
                    lineSpacing: settings.bodyLineSpacing * 0.75
                )
            }
            // Without this the VStack gets an unbounded width proposal and the
            // reply body runs past the card's right edge.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Must come after the padding: widening first and padding second makes
        // the row 32pt wider than the card, which clips the last glyph.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The design's fold-quote: accent rule, author + floor, one-line excerpt.
    private func quoteBlock(_ quoted: ThreadedReply.QuotedReply) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent.opacity(0.35))
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(quoted.floor.map { "\(quoted.username) #\($0)" } ?? quoted.username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if !quoted.excerpt.isEmpty {
                    Text(quoted.excerpt)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}