import SwiftUI

/// Bir projenin tek tıkla çalıştırılabilen komutlarını düzenler.
struct ProjectCommandsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    @State private var commands: [RunCommand] = []
    @State private var loaded = false
    @State private var detectMessage: String?

    private var project: Project? { store.project(projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L("Komutlar — ", "Commands — ") + (project?.name ?? "")).font(.title2.bold())
                    Text(L("İşaretli olanlar \"Projeyi Başlat\" ile birlikte açılır. Port boşsa projeden bulunan kullanılır (gri yazı).", "Checked commands start together with \"Start Project\". If the port is empty, the detected one is used (grey text)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { detect() } label: {
                    Label(L("Otomatik Bul", "Auto-Detect"), systemImage: "wand.and.stars")
                }
                .help(L("package.json, Makefile, docker compose, Procfile vb. dosyalardan komutları bul", "Find commands in package.json, Makefile, docker compose, Procfile and more"))
            }

            if let detectMessage {
                Text(detectMessage).font(.caption).foregroundStyle(.secondary)
            }

            if commands.isEmpty {
                VStack(spacing: 8) {
                    Text(L("Henüz komut yok", "No commands yet")).foregroundStyle(.secondary)
                    Text(L("\"Otomatik Bul\"u deneyin ya da elle ekleyin (ör. npm run dev).", "Try \"Auto-Detect\" or add one by hand (e.g. npm run dev)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack(spacing: 8) {
                    Text(L("Başlat", "Start")).frame(width: 44)
                    Text(L("Ad", "Name")).frame(width: 150, alignment: .leading)
                    Text(L("Komut", "Command")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("Alt klasör", "Subfolder")).frame(width: 110, alignment: .leading)
                    Text("Port").frame(width: 70, alignment: .leading)
                    Spacer().frame(width: 60)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($commands) { $cmd in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $cmd.includeInStartAll)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .frame(width: 44)
                                TextField(L("Ad", "Name"), text: $cmd.name)
                                    .frame(width: 150)
                                TextField(L("Komut", "Command"), text: $cmd.command)
                                    .font(.body.monospaced())
                                TextField("—", text: Binding(
                                    get: { $cmd.wrappedValue.subdirectory ?? "" },
                                    set: { $cmd.wrappedValue.subdirectory = $0.nonEmpty }
                                ))
                                .frame(width: 110)
                                TextField(cmd.detectedPort.map(String.init) ?? "—", text: Binding(
                                    get: { $cmd.wrappedValue.port.map(String.init) ?? "" },
                                    set: { text in
                                        let digits = text.filter(\.isNumber)
                                        let value = Int(digits).flatMap { (1...65535).contains($0) ? $0 : nil }
                                        // Bulunan portla aynıysa ayrıca zorlamaya gerek yok
                                        $cmd.wrappedValue.port = value == $cmd.wrappedValue.detectedPort ? nil : value
                                    }
                                ))
                                .frame(width: 70)
                                .help(cmd.detectedPort.map { L("Bulunan port: \($0). Farklı bir port yazarsanız komut o portla başlatılır.", "Detected port: \($0). Enter a different port to start the command on it.") }
                                      ?? L("Port yazarsanız komut PORT=… (ve uygunsa --port) ile başlatılır.", "If you enter a port, the command starts with PORT=… (and --port where supported)."))
                                Button { move(cmd.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .buttonStyle(.borderless)
                                    .disabled(commands.first?.id == cmd.id)
                                Button { commands.removeAll { $0.id == cmd.id } } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
            }

            HStack {
                Button {
                    commands.append(RunCommand(name: L("yeni komut", "new command"), command: "", includeInStartAll: false))
                } label: {
                    Label(L("Komut Ekle", "Add Command"), systemImage: "plus")
                }
                Spacer()
                Button(L("Vazgeç", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Kaydet", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 860)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            commands = project?.commands ?? []
        }
    }

    private func detect() {
        guard let project else { return }
        let found = CommandDetector.detect(in: project.path)
        for i in commands.indices {
            if let m = found.first(where: { $0.command == commands[i].command && $0.subdirectory == commands[i].subdirectory }) {
                commands[i].detectedPort = m.detectedPort
            }
        }
        let existing = Set(commands.map { "\($0.subdirectory ?? "")|\($0.command)" })
        let new = found.filter { !existing.contains("\($0.subdirectory ?? "")|\($0.command)") }
        commands.append(contentsOf: new)
        detectMessage = new.isEmpty ? L("Yeni komut bulunamadı.", "No new commands found.") : L("\(new.count) komut eklendi.", "Added \(new.count) commands.")
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard commands.indices.contains(j) else { return }
        commands.swapAt(i, j)
    }

    private func save() {
        let cleaned = commands.filter { $0.command.nonEmpty != nil }.map { c -> RunCommand in
            var c = c
            c.name = c.name.nonEmpty ?? c.command
            c.command = c.command.trimmed
            return c
        }
        store.updateCommands(cleaned, for: projectID)
        dismiss()
    }
}
