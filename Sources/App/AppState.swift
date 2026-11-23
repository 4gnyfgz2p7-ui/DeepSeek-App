import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let store = ConversationStore()
    let settings = AppSettings()

    var apiKey: String = ""
    var session: ChatSession?
    var showSidebar = false
    var showSettings = false

    /// 整个 App 共用一块 WKWebView：切换会话时重置内容，避免每条消息一个 webview 把内存撑爆
    let transcript = TranscriptBridge()

    init() {
        apiKey = Keychain.read() ?? ""
        if let latest = store.conversations.first {
            session = makeSession(for: latest)
        }
    }

    func makeSession(for conversation: Conversation) -> ChatSession {
        ChatSession(
            conversation: conversation,
            store: store,
            settings: settings,
            keyProvider: { [weak self] in self?.apiKey ?? "" }
        )
    }

    func open(_ conversation: Conversation) {
        session = makeSession(for: conversation)
        showSidebar = false
    }

    func newConversation() {
        open(store.create())
    }

    func delete(_ conversation: Conversation) {
        let wasCurrent = session?.conversation.id == conversation.id
        store.delete(conversation.id)
        guard wasCurrent else { return }
        if let next = store.conversations.first {
            open(next)
        } else {
            newConversation()
        }
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        if trimmed.isEmpty {
            Keychain.delete()
        } else {
            Keychain.save(trimmed)
        }
    }
}
