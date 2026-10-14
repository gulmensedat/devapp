import SwiftUI

/// Seçili terminallere aynı anda metin/komut gönderir.
struct BroadcastBar: View {
    @Environment(AppStore.self) private var store
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var store = store
        let targets = store.broadcastTargets

        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)

            Menu("\(targets.count) hedef") {
                Button("Hepsini Seç") { store.setBroadcastSelection { _ in true } }
                Button("Sadece Ajanlar") { store.setBroadcastSelection { $0.kind.isAgent } }
                Button("Sadece Terminaller") { store.setBroadcastSelection { $0.kind == .shell } }
                Button("Boştakiler") { store.setBroadcastSelection { $0.status == .idle } }
                Divider()
                Button("Seçimi Temizle") { store.setBroadcastSelection { _ in false } }
            }
            .fixedSize()
            .help("Hedefleri kutu başlıklarındaki onay kutularıyla da seçebilirsiniz")

            TextField("Seçili terminallere gönderilecek metin — Enter ile gönder", text: $store.broadcastText)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { store.sendBroadcast() }

            Button("Gönder") { store.sendBroadcast() }
                .disabled(targets.isEmpty || store.broadcastText.isEmpty)

            Button("⌃C") { store.sendToBroadcastTargets(raw: "\u{03}") }
                .disabled(targets.isEmpty)
                .help("Seçili terminallere Ctrl-C (işi durdur)")

            Button("Esc") { store.sendToBroadcastTargets(raw: "\u{1b}") }
                .disabled(targets.isEmpty)
                .help("Seçili terminallere Escape (Claude/Codex'te mevcut adımı keser)")

            Button { store.showBroadcast = false } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.bar)
        .onAppear { fieldFocused = true }
    }
}
