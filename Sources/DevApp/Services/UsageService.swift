import Foundation

/// Claude Code ve Codex kullanımını hesaplar.
///
/// - Claude: `~/.claude/projects/**/*.jsonl` kayıtlarından bugünkü ve son 5 saatteki token
///   (`message.usage`, `message.id` ile tekilleştirilir). İsteğe bağlı olarak plan limiti yüzdesi
///   Claude Code'un oturum anahtarıyla `api.anthropic.com/api/oauth/usage` üzerinden okunur
///   (Ayarlar'dan açılır; Anahtar Zinciri izni ister).
/// - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl(.zst)` içindeki `token_count`
///   olayları; 5 saatlik ve haftalık limit yüzdeleri `rate_limits` alanından gelir.
actor UsageService {
    static let shared = UsageService()

    private struct ClaudeEntry {
        let id: String
        let time: Date
        let tokens: Int
    }

    private struct CachedFile {
        let mtime: Date
        let size: Int
        let entries: [ClaudeEntry]
    }

    private var claudeCache: [String: CachedFile] = [:]
    private var planCache: (fetched: Date, usage: (Double?, Date?, Double?, Date?), note: String?)?

    // MARK: Genel

    func snapshot(includeClaudePlan: Bool) async -> (claude: ProviderUsage, codex: ProviderUsage) {
        let now = Date()
        var claude = claudeLocal(now: now)
        if includeClaudePlan {
            let plan = await claudePlan(now: now)
            claude.sessionPercent = plan.usage.0
            claude.sessionResetsAt = plan.usage.1
            claude.weeklyPercent = plan.usage.2
            claude.weeklyResetsAt = plan.usage.3
            if let note = plan.note { claude.note = note }
        }
        let codex = codexUsage(now: now)
        return (claude, codex)
    }

    // MARK: Claude — yerel kayıtlar

    private var claudeRoots: [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            roots += env.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        }
        roots += [home.appendingPathComponent(".claude"), home.appendingPathComponent(".config/claude")]
        return roots.map { $0.appendingPathComponent("projects") }.filter { fm.fileExists(atPath: $0.path) }
    }

    private func claudeLocal(now: Date) -> ProviderUsage {
        var usage = ProviderUsage(name: "Claude")
        let roots = claudeRoots
        guard !roots.isEmpty else {
            usage.note = "Claude Code kaydı bulunamadı"
            return usage
        }
        let dayStart = Calendar.current.startOfDay(for: now)
        let windowStart = now.addingTimeInterval(-5 * 3600)
        let since = min(dayStart, windowStart)

        var seen = Set<String>()
        var today = 0, window = 0
        var last: Date?
        var livePaths = Set<String>()

        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let mtime = values?.contentModificationDate, mtime >= since else { continue }
                let size = values?.fileSize ?? 0
                livePaths.insert(url.path)

                let entries: [ClaudeEntry]
                if let cached = claudeCache[url.path], cached.mtime == mtime, cached.size == size {
                    entries = cached.entries
                } else {
                    entries = parseClaudeFile(url, since: since)
                    claudeCache[url.path] = CachedFile(mtime: mtime, size: size, entries: entries)
                }
                for e in entries where seen.insert(e.id).inserted {
                    if e.time >= dayStart { today += e.tokens }
                    if e.time >= windowStart { window += e.tokens }
                    if last == nil || e.time > last! { last = e.time }
                }
            }
        }
        // Eski dosyaları önbellekten at
        claudeCache = claudeCache.filter { livePaths.contains($0.key) }

        usage.todayTokens = today
        usage.windowTokens = window
        usage.lastActivity = last
        return usage
    }

    private func parseClaudeFile(_ url: URL, since: Date) -> [ClaudeEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let marker = Data("\"usage\"".utf8)
        var result: [ClaudeEntry] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let time = Self.parseDate(ts), time >= since else { continue }
            let tokens = Self.int(usage["input_tokens"]) + Self.int(usage["output_tokens"])
                + Self.int(usage["cache_creation_input_tokens"])
            guard tokens > 0 else { continue }
            let id = (message["id"] as? String ?? UUID().uuidString) + ":" + (obj["requestId"] as? String ?? "")
            result.append(ClaudeEntry(id: id, time: time, tokens: tokens))
        }
        return result
    }

    // MARK: Claude — plan limiti (isteğe bağlı)

    private func claudePlan(now: Date) async -> (usage: (Double?, Date?, Double?, Date?), note: String?) {
        if let c = planCache, now.timeIntervalSince(c.fetched) < 300 { return (c.usage, c.note) }

        guard let token = Self.claudeAccessToken() else {
            let r: (usage: (Double?, Date?, Double?, Date?), note: String?) =
                ((nil, nil, nil, nil), "Claude oturum anahtarı okunamadı")
            planCache = (now, r.usage, r.note)
            return r
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        var result: (usage: (Double?, Date?, Double?, Date?), note: String?) = ((nil, nil, nil, nil), nil)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                result.note = "Claude oturumu yenilenmeli (Claude Code'u bir kez açın)"
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result.usage = Self.parsePlan(obj)
            } else {
                result.note = "Plan kullanımı okunamadı"
            }
        } catch {
            result.note = "Plan kullanımı alınamadı (ağ)"
        }
        planCache = (now, result.usage, result.note)
        return result
    }

    private static func parsePlan(_ obj: [String: Any]) -> (Double?, Date?, Double?, Date?) {
        func read(_ key: String) -> (Double?, Date?) {
            guard let d = obj[key] as? [String: Any] else { return (nil, nil) }
            let p = double(d["utilization"]) ?? double(d["percent"])
            let r = (d["resets_at"] as? String).flatMap(parseDate)
            return (p, r)
        }
        var (sp, sr) = read("five_hour")
        var (wp, wr) = read("seven_day")
        // Yeni biçim: "limits": [{ "kind": "...", "percent": .., "resets_at": ".." }]
        if let limits = obj["limits"] as? [[String: Any]] {
            for l in limits {
                let kind = (l["kind"] as? String ?? "").lowercased()
                let p = double(l["percent"]) ?? double(l["utilization"])
                let r = (l["resets_at"] as? String).flatMap(parseDate)
                if sp == nil, kind.contains("five") || kind.contains("session") || kind.contains("5h") { sp = p; sr = r }
                else if wp == nil, kind.contains("seven") || kind.contains("week") { wp = p; wr = r }
            }
        }
        return (sp, sr, wp, wr)
    }

    /// Claude Code'un macOS Anahtar Zinciri kaydı ya da ~/.claude/.credentials.json
    private static func claudeAccessToken() -> String? {
        func token(from data: Data) -> String? {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
            return oauth["accessToken"] as? String
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus == 0, let t = token(from: data) { return t }
        }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file) { return token(from: data) }
        return nil
    }

    // MARK: Codex

    private var codexSessionsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env).appendingPathComponent("sessions")
        }
        return home.appendingPathComponent(".codex/sessions")
    }

    private func codexUsage(now: Date) -> ProviderUsage {
        var usage = ProviderUsage(name: "Codex")
        let fm = FileManager.default
        let root = codexSessionsRoot
        guard fm.fileExists(atPath: root.path) else {
            usage.note = "Codex kaydı bulunamadı"
            return usage
        }
        let dayStart = Calendar.current.startOfDay(for: now)
        let windowStart = now.addingTimeInterval(-5 * 3600)
        let since = min(dayStart, windowStart)

        // Son 7 günün klasörleri (limit bilgisi için en son olayı bulmak gerekebilir)
        var files: [(URL, Date)] = []
        let cal = Calendar(identifier: .gregorian)
        for back in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in items where url.lastPathComponent.hasPrefix("rollout-") {
                let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files.append((url, m))
            }
        }
        files.sort { $0.1 > $1.1 }

        var today = 0, window = 0
        var last: Date?
        var latestLimits: (time: Date, limits: [String: Any])?

        for (url, mtime) in files {
            let needTokens = mtime >= since
            if !needTokens && latestLimits != nil { break }
            guard let data = Self.readMaybeCompressed(url) else { continue }
            let marker = Data("token_count".utf8)
            var previous: Int?
            for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      (payload["type"] as? String) == "token_count" else { continue }
                let time = (obj["timestamp"] as? String).flatMap(Self.parseDate) ?? mtime

                if let limits = payload["rate_limits"] as? [String: Any],
                   latestLimits == nil || time > latestLimits!.time {
                    latestLimits = (time, limits)
                }

                guard needTokens else { continue }
                // Birikimli sayaç → bir önceki olaydan farkı al
                let info = payload["info"] as? [String: Any]
                let total = Self.codexTotal(info?["total_token_usage"] as? [String: Any] ?? payload)
                var delta: Int
                if let lastUsage = info?["last_token_usage"] as? [String: Any] {
                    delta = Self.codexTotal(lastUsage)
                } else if let previous {
                    delta = max(0, total - previous)
                } else {
                    delta = total
                }
                previous = total
                if delta < 0 { delta = 0 }
                if time >= dayStart { today += delta }
                if time >= windowStart { window += delta }
                if delta > 0, last == nil || time > last! { last = time }
            }
        }

        usage.todayTokens = today
        usage.windowTokens = window
        usage.lastActivity = last

        if let latest = latestLimits {
            let time = latest.time
            let limits = latest.limits
            for key in ["primary", "secondary"] {
                guard let l = limits[key] as? [String: Any] else { continue }
                var percent = Self.double(l["used_percent"])
                let minutes = Self.double(l["window_minutes"]) ?? (key == "primary" ? 300 : 10_080)
                var reset: Date?
                if let at = Self.double(l["resets_at"]) {
                    reset = Date(timeIntervalSince1970: at)
                } else if let at = l["resets_at"] as? String {
                    reset = Self.parseDate(at)
                } else if let secs = Self.double(l["resets_in_seconds"]) {
                    reset = time.addingTimeInterval(secs)
                }
                // Pencere dolduysa kullanım sıfırlanmıştır
                if let r = reset, r < now { percent = 0; reset = nil }
                if minutes <= 600 {
                    usage.sessionPercent = percent
                    usage.sessionResetsAt = reset
                } else {
                    usage.weeklyPercent = percent
                    usage.weeklyResetsAt = reset
                }
            }
        } else if files.isEmpty {
            usage.note = "Son 7 günde Codex oturumu yok"
        }
        return usage
    }

    private static func codexTotal(_ d: [String: Any]) -> Int {
        if let t = d["total_tokens"] { return int(t) }
        return int(d["input_tokens"]) + int(d["output_tokens"]) + int(d["reasoning_output_tokens"])
    }

    /// .jsonl ya da .jsonl.zst (zstd varsa açılır)
    private static func readMaybeCompressed(_ url: URL) -> Data? {
        guard url.pathExtension == "zst" else { return try? Data(contentsOf: url, options: .mappedIfSafe) }
        let candidates = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        guard let zstd = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: zstd)
        p.arguments = ["-dc", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    // MARK: Yardımcılar

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? iso.date(from: s)
    }

    static func int(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}
