import Foundation
import Observation

@MainActor
@Observable
final class ChatSession {
    private(set) var conversation: Conversation

    var isStreaming = false
    var streamText = ""
    var streamThinking = ""
    var streamTraces: [ToolTrace] = []
    var streamCitations: [Citation] = []
    var lastUsage: Usage?
    var lastError: String?
    /// 本轮流式回答的临时 id：正文还没落库时，渲染器靠它增量更新
    var streamingID: UUID?
    /// 上一轮的临时 id：兜住「没有任何产出就结束」的情况，用来清掉占位
    var lastStreamingID: UUID?

    private let store: ConversationStore
    private let settings: AppSettings
    private let keyProvider: () -> String
    private var task: Task<Void, Never>?
    private var thinkingStartedAt: Date?
    private var pendingStopReason: String?

    init(
        conversation: Conversation,
        store: ConversationStore,
        settings: AppSettings,
        keyProvider: @escaping () -> String
    ) {
        self.conversation = conversation
        self.store = store
        self.settings = settings
        self.keyProvider = keyProvider
        self.lastUsage = conversation.activePath.last(where: { $0.role == .assistant })?.usage
    }

    var path: [ChatNode] { conversation.activePath }
    var isEmpty: Bool { conversation.activePath.isEmpty && !isStreaming }

    var contextUsage: Usage? {
        lastUsage ?? conversation.activePath.last(where: { $0.role == .assistant })?.usage
    }

    // MARK: - 发送

    func send(_ raw: String, location: String? = nil) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard !keyProvider().isEmpty else {
            lastError = "尚未填写 API Key，请到设置中填入"
            return
        }

        var node = ChatNode(parentID: conversation.activeLeafID, role: .user, text: text)
        node.reminder = RequestBuilder.reminder(location: location)
        conversation.nodes.append(node)
        conversation.activeLeafID = node.id
        conversation.updatedAt = Date()
        store.save(conversation)

        runTurn(leaf: node.id)
    }

    /// 重新生成：把活动叶回退到最后一个用户节点后重发，旧回答作为分支保留在 nodes 中
    func regenerate() {
        guard !isStreaming else { return }
        guard let lastUser = conversation.activePath.last(where: { $0.role == .user }) else { return }
        conversation.activeLeafID = lastUser.id
        conversation.updatedAt = Date()
        store.save(conversation)
        runTurn(leaf: lastUser.id)
    }

    func stop() {
        task?.cancel()
    }

    // MARK: - 流式处理

    private func runTurn(leaf: UUID) {
        let config = RequestConfig(
            model: settings.model,
            deepThinking: settings.deepThinking,
            effort: settings.effort.rawValue,
            webSearch: settings.webSearch
        )
        let body = RequestBuilder.body(path: conversation.path(to: leaf), config: config)
        let client = ChatStreamClient(
            baseURL: settings.resolvedBaseURL,
            apiKey: keyProvider(),
            relayToken: settings.relayToken
        )

        streamText = ""
        streamThinking = ""
        streamTraces = []
        streamCitations = []
        thinkingStartedAt = nil
        pendingStopReason = nil
        lastError = nil
        isStreaming = true
        let turnID = UUID()
        streamingID = turnID
        lastStreamingID = turnID

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in client.stream(body: body) {
                    if Task.isCancelled { break }
                    self.apply(event)
                }
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.finalize(leaf: leaf)
        }
    }

    private func apply(_ event: StreamEvent) {
        switch event {
        case .messageStart(let usage):
            if let usage { lastUsage = usage }

        case .thinkingDelta(let chunk):
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            streamThinking += chunk

        case .textDelta(let chunk):
            streamText += chunk

        case .toolUse(let trace):
            streamTraces.append(trace)

        case .toolResult(let id, let hits, let errorCode):
            guard let index = streamTraces.firstIndex(where: { $0.id == id }) else { return }
            streamTraces[index].results = hits
            streamTraces[index].errorCode = errorCode

        case .citation(let citation):
            if !streamCitations.contains(where: { $0.url == citation.url }) {
                streamCitations.append(citation)
            }

        case .finished(let stopReason, let title, let usage):
            if let usage { lastUsage = usage }
            if let title, !title.isEmpty {
                conversation.title = title
                conversation.updatedAt = Date()
            }
            pendingStopReason = stopReason

        case .failure(let message):
            lastError = message

        case .blockStart, .blockStop, .signatureDelta, .messageStop:
            break
        }
    }

    private func finalize(leaf: UUID) {
        isStreaming = false

        let stopReason = pendingStopReason ?? (lastError == nil ? nil : "error")
        let hasContent = !streamText.isEmpty || !streamThinking.isEmpty || !streamTraces.isEmpty

        if hasContent {
            var node = ChatNode(parentID: leaf, role: .assistant, text: streamText)
            node.thinking = streamThinking
            node.traces = streamTraces
            node.citations = streamCitations
            node.usage = lastUsage
            node.stopReason = stopReason
            if let started = thinkingStartedAt {
                node.thinkingSeconds = Date().timeIntervalSince(started)
            }
            conversation.nodes.append(node)
            conversation.activeLeafID = node.id
            conversation.updatedAt = Date()
            store.save(conversation)
        } else if let error = lastError {
            // 完全没有内容时不留空节点，仅保留错误提示供重试
            conversation.updatedAt = Date()
            lastError = error
        }

        streamText = ""
        streamThinking = ""
        streamTraces = []
        streamCitations = []
        thinkingStartedAt = nil
        pendingStopReason = nil
        streamingID = nil
        task = nil
    }
}
