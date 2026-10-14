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
}

struct WidgetSnapshot: Codable, Hashable {
    var updatedAt: Date
    var projects: [ProjectSnapshot]
    var attention: Int
    var claude: ProviderUsage?
    var codex: ProviderUsage?

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
            return "Bu derlemede App Group yok (swift run / build-app.sh). Widget için ./scripts/xcode.sh build ile kurulan DevApp'i açın."
        }
        guard let dir = containerURL else { return "App Group klasörü bulunamadı" }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(snapshot)
            try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            return nil
        } catch {
            return "Yazılamadı: \(error.localizedDescription)"
        }
    }

    /// Widget tarafında neden veri olmadığını anlatır.
    static func readProblem() -> String? {
        guard groupID != nil else { return "Widget'ta App Group tanımı yok" }
        guard let dir = containerURL else { return "App Group klasörüne erişilemiyor" }
        let file = dir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            return "DevApp henüz veri yazmadı — Uygulamalar'daki DevApp'i açın"
        }
        if read() == nil { return "Veri dosyası okunamadı" }
        return nil
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
        if d >= 1_000_000_000 { return String(format: "%.1f B", d / 1_000_000_000).replacingOccurrences(of: ".", with: ",") }
        if d >= 1_000_000 { return String(format: "%.1f M", d / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if d >= 1_000 { return String(format: "%.0f K", d / 1_000) }
        return String(n)
    }

    /// Sıfırlanmaya kalan süre: "2s 14dk", "3g 4s"
    static func resetIn(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return "yenilendi" }
        let days = s / 86_400, hours = (s % 86_400) / 3600, mins = (s % 3600) / 60
        if days > 0 { return "\(days)g \(hours)s" }
        if hours > 0 { return "\(hours)s \(mins)dk" }
        return "\(max(mins, 1))dk"
    }

    static func percent(_ p: Double?) -> String {
        guard let p else { return "—" }
        return "%\(Int(p.rounded()))"
    }
}
