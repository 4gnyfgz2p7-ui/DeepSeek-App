import SwiftUI

struct Composer: View {
    @Binding var text: String
    var session: ChatSession
    @Bindable var settings: AppSettings
    var focused: FocusState<Bool>.Binding
    var onSend: () -> Void

    @State private var hint: String?

    var body: some View {
        VStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceRaised))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            inputCard

            HStack(spacing: 8) {
                ToggleChip(title: "深度思考", systemName: "brain", isOn: $settings.deepThinking)
                ToggleChip(title: "智能搜索", systemName: "globe", isOn: $settings.webSearch)
                Spacer(minLength: 4)
                ContextBadge(usage: session.contextUsage, tier: settings.contextTier)
            }
            .padding(.horizontal, 4)

            Text("回答由 AI 生成，仅供参考")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var inputCard: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("发消息或按住说话", text: $text, axis: .vertical)
                .focused(focused)
                .lineLimit(1...6)
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .padding(.leading, 16)
                .padding(.vertical, 13)

            trailing
                .padding(.trailing, 8)
                .padding(.bottom, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var trailing: some View {
        if session.isStreaming {
            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.text))
            }
            .buttonStyle(.plain)
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                show(hint: "按住说话将在语音阶段接入")
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private func show(hint message: String) {
        withAnimation { hint = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { hint = nil }
        }
    }
}

struct ContextBadge: View {
    var usage: Usage?
    var tier: ContextTier

    var body: some View {
        let used = usage?.contextTotal ?? 0
        Text("\(Self.format(used)) / \(tier.label)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.tertiaryText)
    }

    static func format(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}
