import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack {
            Form {
                Section("接口") {
                    SecureField("DeepSeek API Key", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Base URL", text: $settings.baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("中转令牌（可选）", text: $settings.relayToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("思考与搜索") {
                    Toggle("深度思考", isOn: $settings.deepThinking)
                    Picker("思考强度", selection: $settings.effort) {
                        ForEach(ThinkingEffort.allCases) { effort in
                            Text(effort.label).tag(effort)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("智能搜索", isOn: $settings.webSearch)
                }

                Section("上下文") {
                    Picker("档位", selection: $settings.contextTier) {
                        ForEach(ContextTier.allCases) { tier in
                            Text(tier.label).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("API Key 仅保存在本机钥匙串。会话记录保存于本机 Application Support，不上传。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        app.saveAPIKey(keyDraft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { keyDraft = app.apiKey }
        .preferredColorScheme(.dark)
    }
}
