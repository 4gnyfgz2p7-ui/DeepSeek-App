import SwiftUI
import UIKit

struct ChatScreen: View {
    @Environment(AppState.self) private var app
    var session: ChatSession

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var bridge: TranscriptBridge { app.transcript }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: session.conversation.title,
                isEmpty: session.isEmpty,
                onMenu: { app.showSidebar = true },
                onNew: { app.newConversation() }
            )

            if session.isEmpty {
                EmptyState()
            } else {
                TranscriptView(bridge: bridge)
                    .background(Theme.background)
            }

            if let error = session.lastError {
                ErrorBar(message: error) {
                    session.lastError = nil
                    session.regenerate()
                }
            }

            Composer(
                text: $draft,
                session: session,
                settings: app.settings,
                focused: $focused,
                onSend: send
            )
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            bridge.onCopy = { text in UIPasteboard.general.string = text }
            bridge.onRegenerate = { session.regenerate() }
            bridge.reset(session.path)
        }
        .onChange(of: session.conversation.id) { _, _ in
            bridge.reset(session.path)
        }
        .onChange(of: session.path.count) { _, _ in
            // 用户消息落库、回答落库都会走到这里：整段重建一次即可，
            // 流式期间的临时消息随之被正式节点替换
            bridge.reset(session.path)
        }
        .onChange(of: session.streamingID) { _, id in
            guard let id else { return }
            bridge.beginStreaming(id: id.uuidString)
        }
        .onChange(of: session.streamText) { _, text in
            guard let id = session.streamingID else { return }
            bridge.setText(id: id.uuidString, text: text)
        }
        .onChange(of: session.streamThinking) { _, text in
            guard let id = session.streamingID else { return }
            bridge.setThinking(id: id.uuidString, text: text)
        }
        .onChange(of: session.isStreaming) { _, streaming in
            guard !streaming, let id = session.lastStreamingID else { return }
            bridge.removeStreamingMessage(id: id.uuidString)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        session.send(text)
    }
}

struct TopBar: View {
    var title: String
    var isEmpty: Bool
    var onMenu: () -> Void
    var onNew: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "line.3.horizontal", action: onMenu)

            Spacer(minLength: 4)

            if !isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            CircleIconButton(systemName: "plus", action: onNew)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fish.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.accent)
            Text("你好，让我们开始聊天吧")
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBar: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button("重试", action: onRetry)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.danger.opacity(0.08))
    }
}
