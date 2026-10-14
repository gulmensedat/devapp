import Foundation

enum SettingsKey {
    static let claudeCommand = "claudeCommand"
    static let codexCommand = "codexCommand"
    static let shellPath = "shellPath"
    static let fontSize = "fontSize"
    static let optionAsMeta = "optionAsMeta"
    static let restoreSessions = "restoreSessions"
    static let resumeAgents = "resumeAgents"
    static let claudePlanUsage = "claudePlanUsage"
}

/// UserDefaults üzerinden okunan ayarlar (SettingsView @AppStorage ile aynı anahtarları yazar).
enum AppSettings {
    private static var d: UserDefaults { .standard }

    static var claudeCommand: String {
        d.string(forKey: SettingsKey.claudeCommand)?.nonEmpty ?? "claude"
    }

    static var codexCommand: String {
        d.string(forKey: SettingsKey.codexCommand)?.nonEmpty ?? "codex"
    }

    static var defaultShell: String {
        ProcessInfo.processInfo.environment["SHELL"]?.nonEmpty ?? "/bin/zsh"
    }

    static var shellPath: String {
        d.string(forKey: SettingsKey.shellPath)?.nonEmpty ?? defaultShell
    }

    static var fontSize: Double {
        let v = d.double(forKey: SettingsKey.fontSize)
        return v > 0 ? v : 13
    }

    /// Türkçe klavyede Option ile @ # gibi karakterler yazıldığı için varsayılan kapalı.
    static var optionAsMeta: Bool {
        d.bool(forKey: SettingsKey.optionAsMeta)
    }

    static var restoreSessions: Bool {
        d.object(forKey: SettingsKey.restoreSessions) as? Bool ?? true
    }

    static var resumeAgents: Bool {
        d.bool(forKey: SettingsKey.resumeAgents)
    }

    /// Claude plan limitini (5 saat / haftalık %) Claude Code oturum anahtarıyla oku
    static var claudePlanUsage: Bool {
        d.bool(forKey: SettingsKey.claudePlanUsage)
    }

    static func baseCommand(for kind: SessionKind) -> String? {
        switch kind {
        case .shell, .custom: return nil
        case .claude: return claudeCommand
        case .codex: return codexCommand
        }
    }

    static func resumeCommand(for kind: SessionKind) -> String? {
        switch kind {
        case .claude: return claudeCommand + " --continue"
        case .codex: return codexCommand + " resume --last"
        default: return nil
        }
    }
}
