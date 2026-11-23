// 正文渲染载体：内嵌 WKWebView + 与网页渲染器的桥
//
// 为什么不用原生渲染：官方 chat-demo 的渲染栈是 KaTeX + Prism + Mermaid，
// 这套组合在 SwiftUI 侧没有等价替代（MarkdownUI 不支持 LaTeX）。
// 这里直接把同一套渲染器打包进 App，公式、代码高亮、图表与网页端保持一致。
//
// 状态留在 JS 侧，Swift 只发增量：每来一个 token 都把整段历史过一遍桥会明显拖慢。

import SwiftUI
import WebKit

@MainActor
@Observable
final class TranscriptBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    var onCopy: ((String) -> Void)?
    var onRegenerate: (() -> Void)?

    private var isReady = false
    private var queued: [String] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        controller.add(self, name: "ds")
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsBackForwardNavigationGestures = false

        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            #if DEBUG
            print("[TranscriptBridge] 未找到 web/index.html，检查 Resources 是否以文件夹引用加入")
            #endif
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - 对外接口

    func reset(_ path: [ChatNode]) {
        let items: [[String: Any]] = path.map { node in
            var dict: [String: Any] = [
                "id": node.id.uuidString,
                "role": node.role.rawValue,
                "text": node.text,
                "streaming": false
            ]
            if !node.thinking.isEmpty { dict["thinking"] = node.thinking }
            if let seconds = node.thinkingSeconds { dict["seconds"] = seconds }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8) else { return }
        run("DS.reset(\(json))")
    }

    func beginStreaming(id: String) {
        let payload: [String: Any] = ["id": id, "role": "assistant", "text": "", "streaming": true]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        run("DS.addMessage(\(json))")
    }

    func setText(id: String, text: String) {
        run("DS.setText(\(quote(id)), \(quote(text)))")
    }

    func setThinking(id: String, text: String) {
        run("DS.setThinking(\(quote(id)), \(quote(text)))")
    }

    func markDone(id: String, seconds: Double) {
        run("DS.markDone(\(quote(id)), \(seconds))")
    }

    /// 本轮没有任何产出就结束时，清掉占位消息，避免一直显示三个点
    func removeStreamingMessage(id: String) {
        run("DS.removeMessage(\(quote(id)))")
    }

    // MARK: - 内部

    private func run(_ script: String) {
        guard isReady else {
            queued.append(script)
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// 安全地把 Swift 字符串变成 JS 字符串字面量
    private func quote(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8),
              array.count >= 2 else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        let pending = queued
        queued.removeAll()
        for script in pending {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "copy":
            if let text = body["text"] as? String, !text.isEmpty {
                onCopy?(text)
            }
        case "regenerate":
            onRegenerate?()
        default:
            break
        }
    }
}

struct TranscriptView: UIViewRepresentable {
    let bridge: TranscriptBridge

    func makeUIView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
