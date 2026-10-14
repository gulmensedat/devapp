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
                    Text("Komutlar — \(project?.name ?? "")").font(.title2.bold())
                    Text("İşaretli olanlar \"Projeyi Başlat\" ile birlikte açılır. Port boşsa projeden bulunan kullanılır (gri yazı).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { detect() } label: {
                    Label("Otomatik Bul", systemImage: "wand.and.stars")
                }
                .help("package.json, Makefile, docker compose, Procfile vb. dosyalardan komutları bul")
            }

            if let detectMessage {
                Text(detectMessage).font(.caption).foregroundStyle(.secondary)
            }

            if commands.isEmpty {
                VStack(spacing: 8) {
                    Text("Henüz komut yok").foregroundStyle(.secondary)
                    Text("\"Otomatik Bul\"u deneyin ya da elle ekleyin (ör. npm run dev).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack(spacing: 8) {
                    Text("Başlat").frame(width: 44)
                    Text("Ad").frame(width: 150, alignment: .leading)
                    Text("Komut").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Alt klasör").frame(width: 110, alignment: .leading)
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
                                TextField("Ad", text: $cmd.name)
                                    .frame(width: 150)
                                TextField("Komut", text: $cmd.command)
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
                                .help(cmd.detectedPort.map { "Bulunan port: \($0). Farklı bir port yazarsanız komut o portla başlatılır." }
                                      ?? "Port yazarsanız komut PORT=… (ve uygunsa --port) ile başlatılır.")
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
                    commands.append(RunCommand(name: "yeni komut", command: "", includeInStartAll: false))
                } label: {
                    Label("Komut Ekle", systemImage: "plus")
                }
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") { save() }
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
        detectMessage = new.isEmpty ? "Yeni komut bulunamadı." : "\(new.count) komut eklendi."
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
