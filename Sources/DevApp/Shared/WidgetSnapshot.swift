import Foundation

// Bu dosya hem DevApp'te hem de masaüstü widget eklentisinde derlenir.
// Yalnızca Foundation kullanır.

/// Bir sağlayıcının (Claude / Codex) kullanım özeti
struct ProviderUsage: Codable, Hashable {
    var name: String
    /// 5 saatlik pencerede kullanılan yüzde (0–100); bilinmiyorsa nil
    var sessionPercent: Double?
    var sessionResetsAt: Date?
    /// Haftalık pencerede kullanılan yüzde
    var weeklyPercent: Double?
    var weeklyResetsAt: Date?
    /// Bugün kullanılan toplam token (yerel kayıtlardan)
    var todayTokens: Int = 0
    /// Son 5 saatte kullanılan token (yerel kayıtlardan)
    var windowTokens: Int = 0
    /// Son etkinlik zamanı
    var lastActivity: Date?
    /// Kullanıcıya gösterilecek kısa not ("izin gerekli" vb.)
    var note: String?
    /// Son 12 saatin saatlik token kullanımı (eskiden yeniye)
    var hourly: [Int] = []

    init(name: String, sessionPercent: Double? = nil, sessionResetsAt: Date? = nil,
         weeklyPercent: Double? = nil, weeklyResetsAt: Date? = nil, todayTokens: Int = 0,
         windowTokens: Int = 0, lastActivity: Date? = nil, note: String? = nil, hourly: [Int] = []) {
        self.name = name
        self.sessionPercent = sessionPercent
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.todayTokens = todayTokens
        self.windowTokens = windowTokens
        self.lastActivity = lastActivity
        self.note = note
        self.hourly = hourly
    }

    // Eski sürümün yazdığı dosyalarda yeni alanlar olmayabilir
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sessionPercent = try c.decodeIfPresent(Double.self, forKey: .sessionPercent)
        sessionResetsAt = try c.decodeIfPresent(Date.self, forKey: .sessionResetsAt)
        weeklyPercent = try c.decodeIfPresent(Double.self, forKey: .weeklyPercent)
        weeklyResetsAt = try c.decodeIfPresent(Date.self, forKey: .weeklyResetsAt)
        todayTokens = try c.decodeIfPresent(Int.self, forKey: .todayTokens) ?? 0
        windowTokens = try c.decodeIfPresent(Int.self, forKey: .windowTokens) ?? 0
        lastActivity = try c.decodeIfPresent(Date.self, forKey: .lastActivity)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        hourly = try c.decodeIfPresent([Int].self, forKey: .hourly) ?? []
    }
}

struct ProjectSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var initials: String
    var colorHex: UInt32
    /// running | attention | crashed | idle
    var state: String
    var runningCommands: Int
    var agents: Int
    var ports: [Int]
    /// App Group kabında icons/<id>.png var mı
    var hasIcon: Bool?
}

struct WidgetSnapshot: Codable, Hashable {
    var updatedAt: Date
    var projects: [ProjectSnapshot]
    var attention: Int
    var claude: ProviderUsage?
    var codex: ProviderUsage?
    /// Uygulamanın arayüz dili ("tr" / "en"); widget aynı dilde görünsün diye
    var language: String? = nil

    static let empty = WidgetSnapshot(updatedAt: .distantPast, projects: [], attention: 0, claude: nil, codex: nil)
}

/// DevApp ile widget arasında paylaşılan dosya (App Group kabı içinde snapshot.json)
enum SharedStore {
    static let fileName = "snapshot.json"

    /// Info.plist'teki DevAppGroupID ("TAKIMID.devapp.shared"); Xcode projesiyle derlenince bulunur.
    static var groupID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DevAppGroupID") as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }

    static var containerURL: URL? {
        guard let groupID else { return nil }
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        // Sandbox'sız uygulamada yedek yol
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Group Containers/\(groupID)", isDirectory: true)
    }

    /// Yazar; hata varsa açıklamasını döner (nil = başarılı).
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> String? {
        guard groupID != nil else {
            return L("Bu derlemede App Group yok (swift run / build-app.sh). Widget için ./scripts/xcode.sh build ile kurulan DevApp'i açın.", "This build has no App Group (swift run / build-app.sh). For widgets, open the DevApp installed with ./scripts/xcode.sh build.")
        }
        guard let dir = containerURL else { return L("App Group klasörü bulunamadı", "App Group folder not found") }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(snapshot)
            try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            return nil
        } catch {
            return L("Yazılamadı: \(error.localizedDescription)", "Couldn’t write: \(error.localizedDescription)")
        }
    }

    /// Widget tarafında neden veri olmadığını anlatır.
    static func readProblem() -> String? {
        guard groupID != nil else { return L("Widget'ta App Group tanımı yok", "The widget has no App Group configured") }
        guard let dir = containerURL else { return L("App Group klasörüne erişilemiyor", "Can’t access the App Group folder") }
        let file = dir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            return L("DevApp henüz veri yazmadı — Uygulamalar'daki DevApp'i açın", "DevApp hasn’t written any data yet — open DevApp from Applications")
        }
        if read() == nil { return L("Veri dosyası okunamadı", "Couldn’t read the data file") }
        return nil
    }

    /// Proje logosunun widget için küçültülmüş kopyası
    /// Claude / Codex logosu (uygulama yazar): icons/agent-claude.png
    static func agentIconURL(_ name: String) -> URL? {
        containerURL?.appendingPathComponent("icons/agent-\(name).png")
    }

    static func iconURL(for projectID: UUID) -> URL? {
        containerURL?.appendingPathComponent("icons/\(projectID.uuidString).png")
    }

    static func read() -> WidgetSnapshot? {
        guard let dir = containerURL,
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

enum UsageFormat {
    /// 1_234_567 → "1,2 M"
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        // Türkçede ondalık ayırıcı virgül, İngilizcede nokta
        let sep = L(",", ".")
        if d >= 1_000_000_000 { return String(format: "%.1f B", d / 1_000_000_000).replacingOccurrences(of: ".", with: sep) }
        if d >= 1_000_000 { return String(format: "%.1f M", d / 1_000_000).replacingOccurrences(of: ".", with: sep) }
        if d >= 1_000 { return String(format: "%.0f K", d / 1_000) }
        return String(n)
    }

    /// Sıfırlanmaya kalan süre: "2s 14dk", "3g 4s"
    static func resetIn(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return L("yenilendi", "reset") }
        let days = s / 86_400, hours = (s % 86_400) / 3600, mins = (s % 3600) / 60
        if days > 0 { return L("\(days)g \(hours)s", "\(days)d \(hours)h") }
        if hours > 0 { return L("\(hours)s \(mins)dk", "\(hours)h \(mins)m") }
        return L("\(max(mins, 1))dk", "\(max(mins, 1))m")
    }

    static func percent(_ p: Double?) -> String {
        guard let p else { return "—" }
        let n = Int(p.rounded())
        return L("%\(n)", "\(n)%")
    }
}
