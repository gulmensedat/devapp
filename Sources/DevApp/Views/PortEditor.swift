import SwiftUI

/// Port rozeti: tıklayınca port düzenleyici açılır (tarayıcıda açma da oradan).
/// Aynı portu başka bir komut da kullanıyorsa turuncu uyarı gösterir.
struct PortChip: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand
    var compact = false
    @State private var showEditor = false

    var body: some View {
        if let port = command.effectivePort {
            let open = store.listeningPorts.contains(port)
            let conflict = store.portConflict(for: command)
            Button { showEditor = true } label: {
                HStack(spacing: 3) {
                    if conflict {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    }
                    Text(verbatim: ":\(port)")
                        .font(Theme.mono(11, weight: .medium))
                }
                .foregroundStyle(conflict ? Theme.orange : (open ? Theme.green : Color(hex: 0x8B8E96)))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(conflict ? Theme.orangeBg : (open ? Theme.greenBg : Color(hex: 0x1E1F24))))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(conflict ? L("Bu port başka bir komutla çakışıyor — değiştirmek için tıklayın", "This port conflicts with another command — click to change it")
                           : (open ? L("localhost:\(port) açık — tarayıcıda aç ya da portu değiştir", "localhost:\(port) is open — open it in the browser or change the port") : L("Portu değiştir", "Change port")))
            .popover(isPresented: $showEditor, arrowEdge: .bottom) {
                PortEditor(project: project, command: command) { showEditor = false }
                    .environment(store)
            }
        }
    }
}

/// Bir komutun portunu değiştirme paneli
struct PortEditor: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand
    let onDone: () -> Void
    @State private var text: String = ""

    private var value: Int? {
        Int(text.filter(\.isNumber)).flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    var body: some View {
        let current = command.effectivePort
        let running = store.isCommandRunning(command.id)
        let others = value.map { store.portUsers($0, excluding: command.id) } ?? []

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Port")
                    .font(.system(size: 15, weight: .semibold))
                Text(verbatim: command.name + (command.subdirectory.map { "  ·  \($0)/" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let current, store.listeningPorts.contains(current) {
                Button {
                    let s = store.commandSession(command.id)
                    store.openURL(s.flatMap { store.liveURL(for: $0) } ?? "http://localhost:\(current)")
                    onDone()
                } label: {
                    Label { Text(verbatim: L("localhost:\(current) aç", "Open localhost:\(current)")) } icon: { Image(systemName: "safari") }
                }
            }

            HStack(spacing: 8) {
                TextField(L("örn. 8779", "e.g. 8779"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(13))
                    .frame(width: 100)
                    .onSubmit { save() }
                Button(L("Boş port bul", "Find a free port")) {
                    text = String(store.suggestFreePort(after: value ?? current ?? 3000, excluding: command.id))
                }
            }

            if !others.isEmpty {
                Label {
                    Text(verbatim: L("Çakışıyor: ", "Conflicts with: ") + others.map { "\($0.0.name) › \($0.1.name)" }.joined(separator: ", "))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            } else if let v = value, v != current, PortMonitor.isListening(v) {
                Label(L("Bu port şu an başka bir süreç tarafından kullanılıyor", "This port is currently used by another process"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }

            if let detected = command.detectedPort, command.port != nil {
                Button {
                    store.setPort(nil, for: command.id)
                    onDone()
                } label: {
                    Text(verbatim: L("Projedeki porta dön (:\(detected))", "Back to the project’s port (:\(detected))"))
                }
                .buttonStyle(.link)
            }

            Text(note(running: running))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L("Vazgeç", "Cancel")) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(running ? L("Kaydet ve Yeniden Başlat", "Save and Restart") : L("Kaydet", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value == nil || value == current)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { text = command.effectivePort.map { String($0) } ?? "" }
    }

    private func note(running: Bool) -> String {
        let c = command.command.lowercased()
        if c.hasPrefix("docker compose") || c.hasPrefix("docker-compose") {
            return L("Docker compose portu compose dosyasından alır; buradaki değer yalnızca izleme ve tarayıcıda açma içindir.", "Docker Compose takes the port from the compose file; this value is only used for monitoring and opening in the browser.")
        }
        var s = L("Komut PORT=… ortam değişkeniyle (Vite, Next, Django, Rails, Flutter, Angular, Expo için ayrıca --port ile) başlatılır.", "The command starts with the PORT=… environment variable (plus --port for Vite, Next, Django, Rails, Flutter, Angular and Expo).")
        if running { s += L(" Kaydedince komut yeni portla yeniden başlar.", " Saving restarts the command on the new port.") }
        return s
    }

    private func save() {
        guard let v = value else { return }
        store.setPort(v, for: command.id)
        onDone()
    }
}
