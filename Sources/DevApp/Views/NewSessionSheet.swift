import SwiftUI

struct NewSessionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: NewSessionDraft
    @State private var isGitRepo = false
    @State private var working = false

    init(request: NewSessionRequest) {
        _draft = State(initialValue: NewSessionDraft(projectID: request.projectID, kind: request.kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yeni Oturum").font(.title2.bold())

            Form {
                Picker("Proje", selection: $draft.projectID) {
                    ForEach(store.projects) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }

                Picker("Tür", selection: $draft.kind) {
                    ForEach(SessionKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if draft.kind == .custom {
                    TextField("Komut", text: $draft.customCommand, prompt: Text("npm run dev"))
                }

                TextField("Ad", text: $draft.name, prompt: Text(draft.kind.label))

                if draft.kind.isAgent {
                    TextField("İlk görev", text: $draft.prompt,
                              prompt: Text("Opsiyonel — ör. login ekranındaki hatayı düzelt"),
                              axis: .vertical)
                        .lineLimit(2...6)
                }

                Stepper("Adet: \(draft.count)", value: $draft.count, in: 1...8)

                Toggle("Her oturum ayrı git worktree'de çalışsın", isOn: $draft.useWorktree)
                    .disabled(!isGitRepo)
                    .onChange(of: draft.useWorktree) { _, on in
                        if on, draft.branch.isEmpty { draft.branch = suggestedBranch }
                    }

                if draft.useWorktree {
                    TextField("Branch", text: $draft.branch)
                    Text("Konum: ~/.devapp/worktrees/<proje>/<branch>" + (draft.count > 1 ? " (branch-1, branch-2…)" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !isGitRepo {
                    Text("Proje bir git deposu değil; worktree kullanılamaz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if draft.count > 1, draft.kind.isAgent, !draft.useWorktree {
                    Label("Aynı klasörde birden fazla ajan birbirinin dosyalarını ezebilir. Worktree önerilir.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Başlatılıyor…" : "Başlat") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart || working)
            }
        }
        .padding(20)
        .frame(width: 540)
        .task(id: draft.projectID) { await checkRepository() }
    }

    private var canStart: Bool {
        guard draft.projectID != nil else { return false }
        if draft.kind == .custom, draft.customCommand.nonEmpty == nil { return false }
        if draft.useWorktree, draft.branch.nonEmpty == nil { return false }
        return true
    }

    private var suggestedBranch: String {
        let f = DateFormatter()
        f.dateFormat = "MMdd-HHmm"
        return "\(draft.kind.rawValue)/\(f.string(from: Date()))"
    }

    private func checkRepository() async {
        guard let pid = draft.projectID, let p = store.project(pid) else { isGitRepo = false; return }
        isGitRepo = await Git.isRepository(p.path)
        if !isGitRepo { draft.useWorktree = false }
    }

    private func start() {
        working = true
        let d = draft
        Task {
            await store.createSessions(d)
            dismiss()
        }
    }
}
