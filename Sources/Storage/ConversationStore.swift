// 本地持久化：每个会话一个 JSON 文件
//
// 选择文件而非 SwiftData 的理由：会话是「可导出、可完整保留废弃分支、可版本演进」的
// 单个文档，JSON 文件让导入导出（ZIP）与排障都直接可控，也避免模型迁移风险。
// 本地为权威副本，中转只作暂存。

import Foundation

@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private let directory: URL

    init(directoryName: String = "conversations") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "DSClient", directoryHint: .isDirectory)
        directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    var storageDirectory: URL { directory }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var loaded: [Conversation] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let conversation = try? decoder.decode(Conversation.self, from: data) else { continue }
            loaded.append(conversation)
        }
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create() -> Conversation {
        let conversation = Conversation(title: "新对话", nodes: [], activeLeafID: nil, createdAt: Date(), updatedAt: Date())
        conversations.insert(conversation, at: 0)
        save(conversation)
        return conversation
    }

    func save(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(conversation) else { return }
        try? data.write(to: fileURL(for: conversation.id), options: .atomic)
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
