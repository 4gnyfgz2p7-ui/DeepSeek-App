import SwiftUI
import Foundation

struct SidebarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("会话")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    app.newConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(app.store.conversations) { conversation in
                        row(conversation)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)

            Button {
                app.showSettings = true
                app.showSidebar = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("设置")
                    Spacer()
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
    }

    private func row(_ conversation: Conversation) -> some View {
        let isCurrent = app.session?.conversation.id == conversation.id

        return Button {
            app.open(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Self.relative(conversation.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                app.delete(conversation)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
