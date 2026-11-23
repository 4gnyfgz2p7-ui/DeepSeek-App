// SSE 解析
//
// DeepSeek 的流式响应同时带 `event:` 与 `data:`；data 里的 `type` 字段才是权威的
// 事件类型，`event:` 行仅用于兼容标准 SSE 客户端。这里的解析只依赖 data，
// 并忽略 `: keep-alive` 注释行。

import Foundation

struct SSEEvent {
    var event: String?
    var data: String
}

/// 逐行累积，遇到空行派发一个事件
struct SSEAccumulator {
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func push(line: String) -> SSEEvent? {
        if line.isEmpty {
            guard !dataLines.isEmpty else {
                eventName = nil
                return nil
            }
            let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
            return event
        }

        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        // 其他字段（id: / retry:）与注释行直接忽略
        return nil
    }
}

enum StreamParser {
    static func parse(_ data: String) -> [StreamEvent] {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)),
              let json = object as? [String: Any] else { return [] }

        switch json["type"] as? String ?? "" {
        case "message_start":
            let usage = (json["message"] as? [String: Any])?["usage"] as? [String: Any]
            return [.messageStart(usage.map(Usage.init(dict:)))]

        case "content_block_start":
            let index = json["index"] as? Int ?? 0
            guard let block = json["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String else { return [] }

            var events: [StreamEvent] = [.blockStart(index: index, kind: blockType)]

            if blockType == "server_tool_use", let trace = ToolTrace(block: block) {
                events.append(.toolUse(trace))
            }
            if blockType == "web_search_tool_result" {
                let id = block["tool_use_id"] as? String ?? ""
                let raw = block["content"] as? [[String: Any]] ?? []
                let hits = raw.compactMap(SearchHit.init(dict:))
                let error = raw.first { ($0["type"] as? String) == "web_search_tool_result_error" }?["error_code"] as? String
                events.append(.toolResult(id: id, hits: hits, errorCode: error))
            }
            if blockType == "web_fetch_tool_result" {
                let id = block["tool_use_id"] as? String ?? ""
                let content = block["content"] as? [String: Any] ?? [:]
                let error = (content["type"] as? String) == "web_fetch_tool_result_error"
                    ? content["error_code"] as? String : nil
                events.append(.toolResult(id: id, hits: [], errorCode: error))
            }
            return events

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return [] }
            switch deltaType {
            case "thinking_delta":
                return [.thinkingDelta(delta["thinking"] as? String ?? "")]
            case "text_delta":
                return [.textDelta(delta["text"] as? String ?? "")]
            case "signature_delta":
                return [.signatureDelta(delta["signature"] as? String ?? "")]
            case "citations_delta":
                if let dict = delta["citation"] as? [String: Any], let citation = Citation(dict: dict) {
                    return [.citation(citation)]
                }
                return []
            default:
                return []
            }

        case "content_block_stop":
            return [.blockStop(index: json["index"] as? Int ?? 0)]

        case "message_delta":
            let delta = json["delta"] as? [String: Any] ?? [:]
            let usage = json["usage"] as? [String: Any]
            return [.finished(
                stopReason: delta["stop_reason"] as? String,
                title: delta["title"] as? String,
                usage: usage.map(Usage.init(dict:))
            )]

        case "message_stop":
            return [.messageStop]

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "流式响应返回错误"
            return [.failure(message)]

        default:
            return []
        }
    }
}
