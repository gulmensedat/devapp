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

            Menu(L("\(targets.count) hedef", "\(targets.count) targets")) {
                Button(L("Hepsini Seç", "Select All")) { store.setBroadcastSelection { _ in true } }
                Button(L("Sadece Ajanlar", "Agents Only")) { store.setBroadcastSelection { $0.kind.isAgent } }
                Button(L("Sadece Terminaller", "Terminals Only")) { store.setBroadcastSelection { $0.kind == .shell } }
                Button(L("Boştakiler", "Idle Ones")) { store.setBroadcastSelection { $0.status == .idle } }
                Divider()
                Button(L("Seçimi Temizle", "Clear Selection")) { store.setBroadcastSelection { _ in false } }
            }
            .fixedSize()
            .help(L("Hedefleri kutu başlıklarındaki onay kutularıyla da seçebilirsiniz", "You can also pick targets with the checkboxes in tile headers"))

            TextField(L("Seçili terminallere gönderilecek metin — Enter ile gönder", "Text for the selected terminals — press Enter to send"), text: $store.broadcastText)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { store.sendBroadcast() }

            Button(L("Gönder", "Send")) { store.sendBroadcast() }
                .disabled(targets.isEmpty || store.broadcastText.isEmpty)

            Button("⌃C") { store.sendToBroadcastTargets(raw: "\u{03}") }
                .disabled(targets.isEmpty)
                .help(L("Seçili terminallere Ctrl-C (işi durdur)", "Send Ctrl-C to selected terminals (stop the job)"))

            Button("Esc") { store.sendToBroadcastTargets(raw: "\u{1b}") }
                .disabled(targets.isEmpty)
                .help(L("Seçili terminallere Escape (Claude/Codex'te mevcut adımı keser)", "Send Escape to selected terminals (interrupts the current Claude/Codex step)"))

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
