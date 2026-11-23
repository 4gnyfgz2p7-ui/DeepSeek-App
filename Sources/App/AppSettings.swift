import Foundation
import Observation

enum ThinkingEffort: String, CaseIterable, Identifiable, Codable {
    case low
    case high
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "低"
        case .high: return "高"
        case .max: return "最高"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    var deepThinking: Bool {
        didSet { defaults.set(deepThinking, forKey: Keys.deepThinking) }
    }
    var webSearch: Bool {
        didSet { defaults.set(webSearch, forKey: Keys.webSearch) }
    }
    var effort: ThinkingEffort {
        didSet { defaults.set(effort.rawValue, forKey: Keys.effort) }
    }
    var contextTier: ContextTier {
        didSet { defaults.set(contextTier.rawValue, forKey: Keys.contextTier) }
    }
    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Keys.baseURL) }
    }
    var relayToken: String {
        didSet { defaults.set(relayToken, forKey: Keys.relayToken) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let model = "settings.model"
        static let deepThinking = "settings.deepThinking"
        static let webSearch = "settings.webSearch"
        static let effort = "settings.effort"
        static let contextTier = "settings.contextTier"
        static let baseURL = "settings.baseURL"
        static let relayToken = "settings.relayToken"
    }

    init() {
        let defaults = UserDefaults.standard
        model = defaults.string(forKey: Keys.model) ?? "deepseek-flash"
        deepThinking = defaults.object(forKey: Keys.deepThinking) as? Bool ?? true
        webSearch = defaults.object(forKey: Keys.webSearch) as? Bool ?? true
        effort = ThinkingEffort(rawValue: defaults.string(forKey: Keys.effort) ?? "") ?? .high
        contextTier = ContextTier(rawValue: defaults.integer(forKey: Keys.contextTier)) ?? .k300
        baseURLString = defaults.string(forKey: Keys.baseURL) ?? "https://api.deepseek.com"
        relayToken = defaults.string(forKey: Keys.relayToken) ?? ""
    }

    /// 中转未配置时直连官方域名。正式版应统一走中转，以支持断网取回。
    var resolvedBaseURL: URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), !trimmed.isEmpty { return url }
        return URL(string: "https://api.deepseek.com")!
    }

    var isUsingRelay: Bool {
        !baseURLString.contains("api.deepseek.com")
    }
}
