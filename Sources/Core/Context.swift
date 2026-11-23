// 本地 token 估算
//
// DeepSeek 未提供 token 计数接口，方案明确要求占用数为估算值。
// 这里按中日韩字符约 0.75 token/字、其他字符约 4 字符/token 做近似，
// 仅用于「发送前」的上下文档位判断；每轮返回的 usage.input_tokens 才是权威值。

import Foundation

enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3000...0x303F, 0x4E00...0x9FFF, 0xFF00...0xFFEF, 0x3400...0x4DBF:
                cjk += 1
            default:
                other += 1
            }
        }
        return Int(Double(cjk) * 0.75) + other / 4
    }
}

enum ContextTier: Int, CaseIterable, Identifiable, Codable {
    case k128 = 128
    case k300 = 300
    case k600 = 600
    case k800 = 800
    case m1 = 1000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .m1: return "1M"
        default: return "\(rawValue)K"
        }
    }

    var tokens: Int { rawValue * 1000 }

    /// 提前预留输出空间：即使选 1M 档，也在触顶前压缩，绝不等 400 错误
    var compressionThreshold: Int {
        max(4096, tokens - 12_000)
    }
}
