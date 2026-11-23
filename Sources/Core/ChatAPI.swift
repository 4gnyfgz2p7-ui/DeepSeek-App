// DeepSeek Messages API 客户端
//
// 协议选择：/anthropic/v1/messages（Anthropic 兼容格式）。
// 理由：只有它把 thinking 块、server_tool_use、web_search_tool_result、
// citations_delta、以及 message_delta 里回传的会话标题全部结构化下发，
// 正好对应 App 的思考框、搜索条目与来源角标。
//
// 中转接入方式：baseURL 指向中转地址时，请求体与直连完全一致，
// 额外带 x-relay-token；中转只负责代调上游、按消息 id 落盘与取回。

import Foundation

enum ChatError: LocalizedError {
    case transport(String)
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .transport(let message):
            return message
        case .http(let code, let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "请求失败（HTTP \(code)）" + (trimmed.isEmpty ? "" : "：\(String(trimmed.prefix(300)))")
        case .badResponse:
            return "响应格式异常"
        }
    }
}

enum StreamEvent {
    case messageStart(Usage?)
    case blockStart(index: Int, kind: String)
    case thinkingDelta(String)
    case textDelta(String)
    case signatureDelta(String)
    case toolUse(ToolTrace)
    case toolResult(id: String, hits: [SearchHit], errorCode: String?)
    case citation(Citation)
    case blockStop(index: Int)
    case finished(stopReason: String?, title: String?, usage: Usage?)
    case messageStop
    case failure(String)
}

struct ChatStreamClient {
    var baseURL: URL
    var apiKey: String
    var relayToken: String?

    func url() -> URL {
        baseURL.appending(path: "anthropic/v1/messages")
    }

    func stream(body: Data) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url(), timeoutInterval: 180)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    if let relayToken, !relayToken.isEmpty {
                        request.setValue(relayToken, forHTTPHeaderField: "x-relay-token")
                    }
                    request.httpBody = body

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatError.badResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        let detail = try await Self.readPrefix(bytes, limit: 4096)
                        throw ChatError.http(http.statusCode, detail)
                    }

                    var accumulator = SSEAccumulator()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = accumulator.push(line: line) else { continue }
                        for parsed in StreamParser.parse(event.data) {
                            continuation.yield(parsed)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func readPrefix(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 请求体构造

/// 纯值配置，避免网络层直接读取 @MainActor 的 AppSettings
struct RequestConfig {
    var model: String
    var deepThinking: Bool
    var effort: String
    var webSearch: Bool
}

enum RequestBuilder {
    /// 每轮必带的用户元信息：<date>,<weekday>,<location>,<platform>,<language>
    /// location 允许为空；不传则模型无法感知日期与所在地。
    static func reminder(location: String? = nil, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)

        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)

        return "\(day),\(weekday),\(location ?? ""),App,中文"
    }

    static func body(
        path: [ChatNode],
        config: RequestConfig,
        maxTokens: Int = 8192
    ) -> Data {
        var messages: [[String: Any]] = []

        for node in path {
            switch node.role {
            case .user:
                if let reminder = node.reminder, !reminder.isEmpty {
                    messages.append(["role": "latest_reminder", "content": reminder])
                }
                messages.append(["role": "user", "content": node.text])
            case .assistant:
                // 历史轮次的思考、搜索结果与打开过的网页不进入上下文（官方口径），
                // 只回传正文，既符合拼接规则，也让前缀保持稳定以命中硬盘缓存。
                if !node.text.isEmpty {
                    messages.append(["role": "assistant", "content": node.text])
                }
            }
        }

        var payload: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": messages,
            "safety_check": ["level": "high"],
            "title": ["enabled": true]
        ]

        if config.deepThinking {
            payload["thinking"] = ["type": "enabled"]
            payload["output_config"] = ["effort": config.effort]
        } else {
            payload["thinking"] = ["type": "disabled"]
        }

        if config.webSearch {
            // 思考开关 + 该工具 = 深度思考搜索；关闭思考 = 普通联网搜索。均由模型判断是否真的搜。
            payload["tools"] = [
                ["type": "deepseek_web_search", "name": "deepseek_web_search"],
                ["type": "deepseek_read_url", "name": "deepseek_read_url"]
            ]
        }

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}
