import SwiftUI
import ReaderCore

public struct SpeedSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let documentID: UUID?
    @State private var rate: Double
    @State private var isSaving = false

    public init(documentID: UUID? = nil) {
        self.documentID = documentID
        _rate = State(initialValue: 1)
    }

    private let presets = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("语速").font(.title2.weight(.semibold))
                    Spacer()
                    Button("完成") {
                        if documentID == nil { saveDefaultRate() }
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("关闭语速面板")
                    .accessibilityIdentifier("speed.done")
                }
                .padding(.horizontal, 20)

                Text(String(format: "%.2f×", rate))
                    .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.text)
                    .contentTransition(.numericText())
                    .accessibilityLabel("当前语速 \(String(format: "%.2f", rate)) 倍")

                HStack(spacing: 24) {
                    rateButton(systemName: "minus", label: "降低语速", identifier: "speed.decrease") { setRate(rate - 0.05) }
                    Slider(value: Binding(get: { rate }, set: { setRate($0) }), in: 0.5...2.0, step: 0.05)
                        .tint(AppTheme.accent)
                        .accessibilityLabel("语速")
                        .accessibilityIdentifier("speed.slider")
                    rateButton(systemName: "plus", label: "提高语速", identifier: "speed.increase") { setRate(rate + 0.05) }
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(presets, id: \.self) { preset in
                        Button { setRate(preset) } label: {
                            Text(String(format: "%.2f×", preset))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(abs(rate - preset) < 0.001 ? AppTheme.accent : AppTheme.secondaryText)
                        .accessibilityIdentifier("speed.preset.\(String(format: "%g", preset))")
                    }
                }
                .padding(.horizontal, 20)

                if documentID != nil {
                    Button("恢复使用默认语速") { restoreDefaultRate() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("speed.restoreDefault")
                    Button { saveDefaultRate() } label: {
                        Label(isSaving ? "保存中…" : "设为默认语速", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(isSaving)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("speed.setDefault")
                }

                Text(documentID == nil ? "调整会保存为默认语速。" : "当前文档使用独立覆盖值；设为默认不会修改其他文档。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Text("调整后从当前句重新生成语音。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("settings.speed")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { loadRate() }
    }

    private func rateButton(systemName: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.accent)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func loadRate() {
        rate = documentID.flatMap { store.document($0)?.playbackRate } ?? store.preferences.defaultRate
        rate = min(2, max(0.5, rate))
    }

    private func setRate(_ value: Double) {
        let clamped = min(2, max(0.5, (value / 0.05).rounded() * 0.05))
        rate = clamped
        Task {
            if let documentID {
                _ = await store.perform { try await $0.setDocumentRate(id: documentID, rate: clamped) }
            } else {
                var preferences = store.preferences
                preferences.defaultRate = clamped
                await store.savePreferences(preferences)
            }
        }
    }

    private func saveDefaultRate() {
        var preferences = store.preferences
        preferences.defaultRate = rate
        Task { isSaving = true; await store.savePreferences(preferences); isSaving = false }
    }

    private func restoreDefaultRate() {
        guard let documentID else { return }
        rate = store.preferences.defaultRate
        Task { _ = await store.perform { try await $0.setDocumentRate(id: documentID, rate: nil) } }
    }
}
