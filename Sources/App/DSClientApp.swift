import SwiftUI

@main
struct DSClientApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        ZStack(alignment: .leading) {
            Group {
                if let session = app.session {
                    ChatScreen(session: session)
                } else {
                    Color(Theme.background)
                }
            }

            if app.showSidebar {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { app.showSidebar = false }

                SidebarView()
                    .frame(width: 312)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.snappy(duration: 0.22), value: app.showSidebar)
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .onAppear {
            // 首次启动没有密钥时直接进入设置，避免落在首页后发送才发现缺 Key
            if app.apiKey.isEmpty {
                app.showSettings = true
            }
        }
    }
}
