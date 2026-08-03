# V2EX

V2EX 社区的 iOS 客户端。SwiftUI 构建，面向 iOS 26 设计语言（Liquid Glass 原生组件），数据直连 V2EX 开放 API。

## 截图

<img src="docs/screenshots/V2EX_screenshots.png" alt="V2EX 界面总览" width="100%"/>

## 功能

- **首页**：关注流（合并关注节点）、最新、热门 + 置顶精选卡片
- **话题**：正文渲染（段落/代码/引用/列表/图片）、楼层回复、引用折叠、分页拉取长帖、阅读数显示
- **节点**：分类目录、节点搜索、关注节点、话题列表多排序（最新回复/最新创建/本周热议）
- **通知**：Access Token 驱动，回复/@/感谢/收藏分类筛选，未读标记
- **搜索**：sov2ex 全文索引（话题/回复/用户/节点），命中高亮
- **个人**：个人资料、收藏、离线阅读、我的话题、屏蔽关键词与用户
- **外观**：五套主题配色（翡翠绿/海洋蓝/绯红/琥珀橙/紫罗兰）、明暗模式、正文字号/行距可调
- **离线**：话题与回复整帖缓存，Wi-Fi 自动下载关注节点

## 技术要点

| 模块 | 说明 |
| --- | --- |
| API 1.0 | 公开接口：话题、回复、节点、成员、全部节点 |
| API 2.0 | Personal Access Token：通知、个人资料、长帖分页、删除通知 |
| sov2ex | 社区全文索引，V2EX 无官方搜索接口 |
| 视觉系统 | "Ink on paper"：中性纸色底 + 单一信号色（主题可换）+ 收敛字阶 |
| 渲染 | 自研轻量 HTML 解析（段落/行内/图片提取），替代 NSAttributedString 方案 |
| 存储 | Keychain（Token）、UserDefaults（设置）、磁盘缓存（离线包） |

一些工程决策：

- **图片渲染**：`AsyncImage` 必须显式 frame，否则按原图尺寸布局被裁剪；帖子图片由解析器从 `<p>` 内提取为独立 block
- **通知头像**：API 2.0 通知的 `member` 只带 `username`，用 v1 接口按用户补齐头像（内存缓存防刷新丢失）
- **阅读数**：API 不提供 views 字段，从话题页抓取解析（`N views` / `N 次点击`），失败静默隐藏
- **列表性能**：话题列表用 `LazyVStack` 惰性构建，避免分页累积后 AsyncImage 下载风暴

## 构建

```bash
# 生成工程（XcodeGen）
xcodegen generate

# 模拟器
xcodebuild -project V2EX.xcodeproj -scheme V2EX \
  -destination 'generic/platform=iOS Simulator' build

# 真机（需签名配置）
open V2EX.xcodeproj   # Signing & Capabilities 里选 Team 后 Cmd+R
```

## 发布 TestFlight

使用本机配置的 `ship` 工具（App Store Connect API key 存于 `~/.appstoreconnect/`；项目级配置 `.ship.yml` 不入库，需本地自行创建）：

```bash
ship status               # 配置检查
ship tf                   # bump → archive → export → upload → 分发
ship builds               # 构建处理状态
ship groups create <名> --external   # 外部组（公测）
ship groups link <名>     # 公测链接
```

手动导出兜底（当 ship 的自动签名不可用时）：

```bash
xcodebuild -exportArchive -archivePath <path.xcarchive> \
  -exportPath export -exportOptionsPlist <exportOptions.plist>
xcrun altool --upload-app -f export/V2EX.ipa \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID> --type ios
```

> API key、Issuer、Team 标识属于开发者账号凭据，不写入公开仓库。

## 项目结构

```
V2EX/
├── App/              # 入口、Tab 导航、路由
├── DesignSystem/     # 主题配色、组件、话题视图
├── Features/         # 首页/节点/通知/话题/搜索/个人/设置
├── Models/           # Codable 模型
├── Networking/       # V2EXClient、HTML 解析
├── Storage/          # 设置、Keychain、离线缓存
└── Assets.xcassets/  # App 图标
```

## 说明

- 通知、个人资料等需要 Personal Access Token，在 v2ex.com/settings/tokens 生成
- 发帖/回复受 API 2.0 限制（只读），草稿可保存后到网页发布
- API 频率上限 600 次/小时/IP
