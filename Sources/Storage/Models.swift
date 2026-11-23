// 数据模型
//
// 关键设计：会话用「扁平节点数组 + 父指针」表示，不使用树形嵌套。
// 这样回退到任意历史节点时，被抛弃的分支仍完整保留在 nodes 里（方案要求本地保留可查看），
// 活动路径由 activeLeafID 沿 parentID 回溯得到，渲染与序列化都不会退化。

import Foundation

enum Role: String, Codable {
    case user
    case assistant
}

struct Citation: Codable, Hashable, Identifiable {
    var url: String
    var title: String?
    var id: String { url }

    init?(dict: [String: Any]) {
        guard let url = dict["url"] as? String, !url.isEmpty else { return nil }
        self.url = url
        self.title = dict["title"] as? String
    }
}

struct SearchHit: Codable, Hashable, Identifiable {
    var url: String?
    var title: String?
    var siteName: String?
    var siteIcon: String?
    var snippet: String?
    var id: String { (url ?? "") + "|" + (title ?? "") }

    init?(dict: [String: Any]) {
        let url = dict["url"] as? String
        let title = dict["title"] as? String
        guard url != nil || title != nil else { return nil }
        self.url = url
        self.title = title
        self.siteName = dict["site_name"] as? String
        self.siteIcon = dict["site_icon"] as? String
        self.snippet = dict["snippet"] as? String
    }
}

/// 服务端工具的一次调用轨迹，用于思考框内「搜索到 N 个网页」「已浏览 N 个页面」等条目
struct ToolTrace: Codable, Hashable, Identifiable {
    var id: String
    var action: String   // search / open_page / find_in_page / read_link
    var kind: String     // search / deep_search / read_link / image_search / deep_image_search
    var label: String
    var detail: String?
    var results: [SearchHit] = []
    var errorCode: String?

    init?(block: [String: Any]) {
        guard let id = block["id"] as? String else { return nil }
        let input = block["input"] as? [String: Any] ?? [:]
        let action = input["action"] as? String ?? "search"
        self.id = id
        self.action = action
        self.kind = block["kind"] as? String ?? "search"

        switch action {
        case "search":
            let queries = input["queries"] as? [String] ?? []
            self.label = queries.isEmpty ? "联网搜索" : "搜索 \(queries.count) 条查询"
            self.detail = queries.joined(separator: " · ")
        case "open_page":
            self.label = "打开网页"
            self.detail = input["url"] as? String
        case "find_in_page":
            self.label = "页内查找"
            self.detail = input["pattern"] as? String
        case "read_link":
            self.label = "阅读链接"
            self.detail = input["url"] as? String
        default:
            self.label = "工具调用"
            self.detail = nil
        }
    }
}

struct Usage: Codable, Hashable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    var contextTotal: Int { inputTokens + outputTokens }
    var cacheHitRate: Double {
        let prompt = inputTokens
        guard prompt > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(prompt)
    }
}

extension Usage {
    init(dict: [String: Any]) {
        inputTokens = dict["input_tokens"] as? Int ?? 0
        outputTokens = dict["output_tokens"] as? Int ?? 0
        cacheReadTokens = dict["cache_read_input_tokens"] as? Int ?? 0
        cacheCreationTokens = dict["cache_creation_input_tokens"] as? Int ?? 0
    }
}

struct Attachment: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileName: String
    var mediaType: String
    var relativePath: String
}

struct ChatNode: Codable, Identifiable, Hashable {
    var id = UUID()
    var parentID: UUID?
    var role: Role
    var text: String = ""
    var thinking: String = ""
    var citations: [Citation] = []
    var traces: [ToolTrace] = []
    /// 仅 user 节点：该轮 latest_reminder 原文。重发时原样复用，保证服务端前缀缓存可命中。
    var reminder: String?
    var attachments: [Attachment] = []
    var usage: Usage?
    var stopReason: String?
    var thinkingSeconds: Double?
    var createdAt = Date()
}

struct Conversation: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = "新对话"
    var nodes: [ChatNode] = []
    var activeLeafID: UUID?
    var createdAt = Date()
    var updatedAt = Date()

    /// 从叶节点沿 parentID 回溯，得到当前活动路径（时间正序）
    func path(to leaf: UUID?) -> [ChatNode] {
        guard let leaf, let start = nodes.first(where: { $0.id == leaf }) else { return [] }
        var index: [UUID: ChatNode] = [:]
        index.reserveCapacity(nodes.count)
        for node in nodes { index[node.id] = node }

        var chain: [ChatNode] = []
        var cursor: ChatNode? = start
        while let node = cursor {
            chain.append(node)
            cursor = node.parentID.flatMap { index[$0] }
        }
        return chain.reversed()
    }

    var activePath: [ChatNode] { path(to: activeLeafID) }

    /// 活动路径上的全部消息 token 估算，用于上下文占用显示（无 API 计数接口时为估算值）
    var estimatedContextTokens: Int {
        activePath.reduce(0) { partial, node in
            partial + TokenEstimator.estimate(node.text) + TokenEstimator.estimate(node.thinking)
        }
    }
}
