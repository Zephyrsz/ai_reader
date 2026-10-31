import SwiftUI
import ReaderCore

public struct ReadingAppearanceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fontSize: Double
    @State private var lineSpacing: Double
    @State private var appearance: ReaderAppearance
    @State private var followSpeech = true
    @State private var isLoaded = false

    public init() {
        _fontSize = State(initialValue: 20)
        _lineSpacing = State(initialValue: 10)
        _appearance = State(initialValue: .system)
        _followSpeech = State(initialValue: true)
    }

    public var body: some View {
        Form {
            Section("字号") {
                HStack {
                    Text("阅读字号").foregroundStyle(AppTheme.text)
                    Spacer()
                    Text("\(Int(fontSize)) pt").foregroundStyle(AppTheme.secondaryText).monospacedDigit()
                }
                Slider(value: $fontSize, in: 17...30, step: 1) {
                    Text("字号")
                } minimumValueLabel: { Text("17") } maximumValueLabel: { Text("30") }
                    .tint(AppTheme.accent)
                    .accessibilityValue("\(Int(fontSize)) 点")
                    .accessibilityIdentifier("appearance.fontSize")
            }
            Section("行距") {
                HStack {
                    Text("段落行距").foregroundStyle(AppTheme.text)
                    Spacer()
                    Text("\(Int(lineSpacing)) pt").foregroundStyle(AppTheme.secondaryText).monospacedDigit()
                }
                Slider(value: $lineSpacing, in: 4...24, step: 1) {
                    Text("行距")
                } minimumValueLabel: { Text("4") } maximumValueLabel: { Text("24") }
                    .tint(AppTheme.accent)
                    .accessibilityValue("\(Int(lineSpacing)) 点")
                    .accessibilityIdentifier("appearance.lineSpacing")
            }
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(ReaderAppearance.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance.theme")
            }
            Section("阅读行为") {
                Toggle("跟随朗读位置", isOn: $followSpeech)
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("appearance.followSpeech")
                Text("开启后，文本视图会滚动到正在朗读的段落。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Section {
                Text("正文示例")
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(AppTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .accessibilityIdentifier("settings.appearance")
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("阅读显示")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("appearance.done")
            }
        }
        .task { loadPreferences() }
        .onChange(of: fontSize) { _, _ in savePreferences() }
        .onChange(of: lineSpacing) { _, _ in savePreferences() }
        .onChange(of: appearance) { _, _ in savePreferences() }
        .onChange(of: followSpeech) { _, _ in savePreferences() }
    }

    private func loadPreferences() {
        let preferences = store.preferences
        fontSize = min(30, max(17, preferences.fontSize))
        lineSpacing = min(24, max(4, preferences.lineSpacing))
        appearance = preferences.appearance
        followSpeech = preferences.followSpeech
        isLoaded = true
    }

    private func savePreferences() {
        guard isLoaded else { return }
        var preferences = store.preferences
        preferences.fontSize = fontSize
        preferences.lineSpacing = lineSpacing
        preferences.appearance = appearance
        preferences.followSpeech = followSpeech
        Task { await store.savePreferences(preferences) }
    }
}
