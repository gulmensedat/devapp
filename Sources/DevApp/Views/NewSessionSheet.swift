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
            Text(L("Yeni Oturum", "New Session")).font(.title2.bold())

            Form {
                Picker(L("Proje", "Project"), selection: $draft.projectID) {
                    ForEach(store.projects) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }

                Picker(L("Tür", "Type"), selection: $draft.kind) {
                    ForEach(SessionKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if draft.kind == .custom {
                    TextField(L("Komut", "Command"), text: $draft.customCommand, prompt: Text("npm run dev"))
                }

                TextField(L("Ad", "Name"), text: $draft.name, prompt: Text(draft.kind.label))

                if draft.kind.isAgent {
                    TextField(L("İlk görev", "First task"), text: $draft.prompt,
                              prompt: Text(L("Opsiyonel — ör. login ekranındaki hatayı düzelt", "Optional — e.g. fix the bug on the login screen")),
                              axis: .vertical)
                        .lineLimit(2...6)
                }

                Stepper(L("Adet: \(draft.count)", "Count: \(draft.count)"), value: $draft.count, in: 1...8)

                Toggle(L("Her oturum ayrı git worktree'de çalışsın", "Run each session in its own git worktree"), isOn: $draft.useWorktree)
                    .disabled(!isGitRepo)
                    .onChange(of: draft.useWorktree) { _, on in
                        if on, draft.branch.isEmpty { draft.branch = suggestedBranch }
                    }

                if draft.useWorktree {
                    TextField("Branch", text: $draft.branch)
                    Text(L("Konum: ~/.devapp/worktrees/<proje>/<branch>", "Location: ~/.devapp/worktrees/<project>/<branch>") + (draft.count > 1 ? " (branch-1, branch-2…)" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !isGitRepo {
                    Text(L("Proje bir git deposu değil; worktree kullanılamaz.", "This project isn’t a git repository; worktrees aren’t available."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if draft.count > 1, draft.kind.isAgent, !draft.useWorktree {
                    Label(L("Aynı klasörde birden fazla ajan birbirinin dosyalarını ezebilir. Worktree önerilir.", "Several agents in one folder can overwrite each other’s files. Worktrees are recommended."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("Vazgeç", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(working ? L("Başlatılıyor…", "Starting…") : L("Başlat", "Start")) { start() }
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
