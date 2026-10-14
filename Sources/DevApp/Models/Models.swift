import SwiftUI

/// Bir terminal oturumunda ne çalıştığı.
enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case shell, claude, codex, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shell: return "Terminal"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .custom: return "Özel Komut"
        }
    }

    var symbol: String {
        switch self {
        case .shell: return "terminal"
        case .claude: return "sparkles"
        case .codex: return "curlybraces"
        case .custom: return "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .shell: return .gray
        case .claude: return .orange
        case .codex: return .teal
        case .custom: return .purple
        }
    }

    var isAgent: Bool { self == .claude || self == .codex }
}

enum SessionStatus: Equatable {
    case starting
    case busy
    case idle
    /// Uzun süre çalışan komut (dev server vb.) ayakta
    case running
    case exited(Int32?)

    var label: String {
        switch self {
        case .starting: return "Başlıyor"
        case .busy: return "Çalışıyor"
        case .idle: return "Boşta"
        case .running: return "Çalışıyor"
        case .exited(let code):
            if let code { return "Kapandı (\(code))" }
            return "Kapandı"
        }
    }

    var color: Color {
        switch self {
        case .starting: return .gray
        case .busy: return .green
        case .idle: return .secondary
        case .running: return .green
        case .exited(let code): return code == 0 ? .gray : .red
        }
    }

    var isRunning: Bool {
        if case .exited = self { return false }
        return true
    }
}

/// Projede tek tıkla çalıştırılabilen komut (dev server, build, test…).
struct RunCommand: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var command: String
    /// Proje köküne göre alt klasör (monorepo: "web", "api" …)
    var subdirectory: String?
    /// "Projeyi Başlat" ile birlikte açılsın mı
    var includeInStartAll: Bool = true
    /// Proje dosyalarından bulunan port (vite.config, .env, script, compose…)
    var detectedPort: Int?
    /// Kullanıcının belirlediği port; bulunanı ezer ve komuta PORT/--port olarak verilir
    var port: Int?

    /// Gösterilen / izlenen port
    var effectivePort: Int? { port ?? detectedPort }

    /// "web: dev" → "dev" (alt klasör adı önekini atar)
    var shortName: String {
        if let sub = subdirectory?.nonEmpty, name.hasPrefix(sub + ": ") {
            return String(name.dropFirst(sub.count + 2))
        }
        return name
    }

    func directory(in project: Project) -> String {
        guard let sub = subdirectory?.nonEmpty else { return project.path }
        return URL(fileURLWithPath: project.path).appendingPathComponent(sub).path
    }

    /// Kullanıcı farklı bir port verdiyse komutu o porta zorlar.
    var launchCommand: String {
        guard let port, port != detectedPort else { return command }
        let c = command.trimmed
        var flagged = c
        let words = c.split(separator: " ").map(String.init)
        if words.first == "npm", words.count >= 3, words[1] == "run" {
            flagged = c + " -- --port \(port)"
        } else if let first = words.first, ["pnpm", "yarn", "bun"].contains(first) {
            flagged = c + " --port \(port)"
        } else if c.contains("manage.py runserver") {
            flagged = c + " \(port)"
        } else if c.contains("rails server") || c.hasSuffix("rails s") {
            flagged = c + " -p \(port)"
        } else if c.hasPrefix("flutter run") {
            flagged = c + " --web-port \(port)"
        } else if c.hasPrefix("ng serve") || c.contains("expo start") {
            flagged = c + " --port \(port)"
        }
        return "PORT=\(port) " + flagged
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var commands: [RunCommand] = []
    /// Kullanıcının seçtiği renk (Theme.projectPalette sırası); nil = isimden otomatik
    var colorIndex: Int?

    init(id: UUID = UUID(), name: String, path: String, commands: [RunCommand] = [], colorIndex: Int? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.commands = commands
        self.colorIndex = colorIndex
    }

    // Eski state.json dosyalarında "commands" yok
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        commands = try c.decodeIfPresent([RunCommand].self, forKey: .commands) ?? []
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex)
    }

    var startAllCommands: [RunCommand] { commands.filter(\.includeInStartAll) }
}

/// Diske yazılan oturum tanımı (süreç değil, tarif).
struct SessionSpec: Codable, Identifiable {
    var id: UUID = UUID()
    var projectID: UUID
    var name: String
    var kind: SessionKind
    /// Yalnızca `.custom` için kullanılır; claude/codex komutu ayarlardan okunur.
    var command: String?
    var directory: String
    var worktreeBranch: String?
    /// Bu oturum bir proje komutunu çalıştırıyorsa onun id'si
    var commandID: UUID?
}

/// Ana alanda gösterilen ekran
enum Screen: Hashable {
    case dashboard
    case terminals
    case project(UUID)
}

enum DashboardFilter: String, CaseIterable, Identifiable {
    case all, running, attention, stopped
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tümü"
        case .running: return "Çalışanlar"
        case .attention: return "Dikkat bekleyen"
        case .stopped: return "Durmuş"
        }
    }
}

enum LayoutMode: String, Codable {
    case grid, focus
}

enum SidebarItem: Hashable {
    case all
    case project(UUID)
    case session(UUID)
    case command(UUID)
}

/// Proje komutlarını düzenleme sayfasını açma isteği.
struct CommandsEditRequest: Identifiable {
    let id = UUID()
    var projectID: UUID
}

struct PersistedState: Codable {
    var projects: [Project] = []
    var sessions: [SessionSpec] = []
    var layout: LayoutMode = .grid
    var gridColumns: Int = 0
}

/// "Yeni oturum" sayfasını açma isteği.
struct NewSessionRequest: Identifiable {
    let id = UUID()
    var projectID: UUID?
    var kind: SessionKind
}

/// Yeni oturum formunun içeriği.
struct NewSessionDraft {
    var projectID: UUID?
    var kind: SessionKind
    var name: String = ""
    var customCommand: String = ""
    var prompt: String = ""
    var count: Int = 1
    var useWorktree: Bool = false
    var branch: String = ""
}

extension String {
    /// Kabuk için tek tırnakla güvenli hale getirir.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nonEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }

    /// Ana dizini ~ ile kısaltır.
    var abbreviatingHome: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + String(dropFirst(home.count)) : self
    }
}
