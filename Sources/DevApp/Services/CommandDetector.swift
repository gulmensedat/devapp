import Foundation

/// Proje klasörüne bakıp çalıştırılabilir komutları tahmin eder.
/// package.json, Makefile, docker compose, Procfile, Flutter, Django, Rails, Cargo, Go, Swift.
enum CommandDetector {

    static func detect(in projectPath: String) -> [RunCommand] {
        let root = URL(fileURLWithPath: projectPath)
        var result = detect(folder: root, subdirectory: nil)

        // Monorepo: bir alt seviyedeki klasörler (web/, api/) ve apps/*, packages/* gibi kaplar
        let skip: Set<String> = ["node_modules", "Pods", "build", "dist", "DerivedData", "vendor", "target", "venv", ".venv"]
        if let items = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir, !skip.contains(item.lastPathComponent),
                      !["xcodeproj", "xcworkspace", "app"].contains(item.pathExtension) else { continue }
                result += detect(folder: item, subdirectory: item.lastPathComponent)

                // Monorepo kapları: apps/web, packages/api, services/auth … (bir seviye daha)
                let containers: Set<String> = ["apps", "packages", "services", "projects", "sites", "workers"]
                guard containers.contains(item.lastPathComponent.lowercased()),
                      let children = try? FileManager.default.contentsOfDirectory(
                        at: item, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard childIsDir, !skip.contains(child.lastPathComponent) else { continue }
                    result += detect(folder: child, subdirectory: "\(item.lastPathComponent)/\(child.lastPathComponent)")
                }
            }
        }

        // Aynı komutu iki kez ekleme
        var seen = Set<String>()
        return result.filter { seen.insert("\($0.subdirectory ?? "")|\($0.command)").inserted }
    }

    private static func detect(folder: URL, subdirectory: String?) -> [RunCommand] {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        func read(_ name: String) -> String? { try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }
        func label(_ name: String) -> String { subdirectory.map { "\($0): \(name)" } ?? name }
        func cmd(_ name: String, _ command: String, start: Bool, port: Int? = nil) -> RunCommand {
            RunCommand(name: label(name), command: command, subdirectory: subdirectory,
                       includeInStartAll: start, detectedPort: port)
        }
        let envPort = PortDetector.envPort(in: folder)

        var list: [RunCommand] = []

        // Node / Bun / Deno
        if let data = fm.contents(atPath: folder.appendingPathComponent("package.json").path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any], !scripts.isEmpty {
            let pm: (String) -> String
            if exists("pnpm-lock.yaml") { pm = { "pnpm \($0)" } }
            else if exists("yarn.lock") { pm = { "yarn \($0)" } }
            else if exists("bun.lockb") || exists("bun.lock") { pm = { "bun run \($0)" } }
            else { pm = { "npm run \($0)" } }

            let priority = ["dev", "start", "serve", "watch", "build", "test", "lint", "typecheck", "preview"]
            let longRunning: Set<String> = ["dev", "start", "serve", "watch"]
            let names = scripts.keys.sorted { a, b in
                let ia = priority.firstIndex(of: a) ?? Int.max
                let ib = priority.firstIndex(of: b) ?? Int.max
                return ia != ib ? ia < ib : a < b
            }
            // "pre"/"post" kancalarını atla; yalnızca ilk uzun süreli script (dev > start > …) "Başlat"a dahil
            var picked = false
            func isHook(_ n: String) -> Bool {
                (n.hasPrefix("pre") && scripts[String(n.dropFirst(3))] != nil)
                    || (n.hasPrefix("post") && scripts[String(n.dropFirst(4))] != nil)
            }
            for name in names where !isHook(name) {
                let start = !picked && longRunning.contains(name)
                if start { picked = true }
                let body = scripts[name] as? String ?? ""
                let port = PortDetector.port(inScript: body, folder: folder, envPort: envPort)
                list.append(cmd(name, pm(name), start: start, port: port))
                if list.count >= 10 { break }
            }
        }

        // docker compose
        if ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].contains(where: exists) {
            let composeFile = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].first(where: exists)
            let composePort = composeFile.flatMap(read).flatMap(PortDetector.composePort)
            list.append(cmd("compose up", "docker compose up", start: true, port: composePort))
            list.append(cmd("compose down", "docker compose down", start: false))
        }

        // Procfile (Heroku / foreman)
        if let procfile = read("Procfile") ?? read("Procfile.dev") {
            for line in procfile.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, !line.hasPrefix("#") else { continue }
                let body = String(parts[1]).trimmed
                list.append(cmd(String(parts[0]).trimmed, body, start: true,
                                port: PortDetector.explicitPort(in: body) ?? envPort))
            }
        }

        // Makefile hedefleri
        if let makefile = read("Makefile") ?? read("makefile") {
            let regex = try? NSRegularExpression(pattern: #"^([A-Za-z0-9][A-Za-z0-9_\-]*)\s*:(?!=)"#, options: .anchorsMatchLines)
            let ns = makefile as NSString
            var targets: [String] = []
            regex?.enumerateMatches(in: makefile, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                if let m, targets.count < 10 {
                    let t = ns.substring(with: m.range(at: 1))
                    if !targets.contains(t) { targets.append(t) }
                }
            }
            let longRunning: Set<String> = ["dev", "run", "serve", "start", "watch", "up"]
            for t in targets {
                let start = longRunning.contains(t)
                list.append(cmd("make \(t)", "make \(t)", start: start, port: start ? envPort : nil))
            }
        }

        // Flutter
        if exists("pubspec.yaml") {
            if read("pubspec.yaml")?.contains("flutter:") == true {
                list.append(cmd("flutter run", "flutter run", start: true, port: nil))
                list.append(cmd("flutter test", "flutter test", start: false))
            } else {
                list.append(cmd("dart run", "dart run", start: true))
            }
        }

        // Python
        if exists("manage.py") {
            list.append(cmd("runserver", "python manage.py runserver", start: true, port: envPort ?? 8000))
        } else if exists("main.py"), exists("requirements.txt") || exists("pyproject.toml") {
            list.append(cmd("python main.py", "python main.py", start: false))
        }

        // Ruby on Rails
        if exists("Gemfile"), exists("bin/rails") {
            list.append(cmd("rails server", exists("bin/dev") ? "bin/dev" : "bin/rails server", start: true,
                            port: envPort ?? 3000))
        }

        // Rust
        if exists("Cargo.toml") {
            list.append(cmd("cargo run", "cargo run", start: false))
            list.append(cmd("cargo test", "cargo test", start: false))
        }

        // Go
        if exists("go.mod") {
            list.append(cmd("go run", "go run .", start: false))
            list.append(cmd("go test", "go test ./...", start: false))
        }

        // Swift Package
        if exists("Package.swift") {
            list.append(cmd("swift build", "swift build", start: false))
            list.append(cmd("swift test", "swift test", start: false))
        }

        return list
    }
}

/// Proje dosyalarından port tahmini.
enum PortDetector {

    /// "--port 3001", "-p 3001", "PORT=3001", ":3001" gibi açık yazımlar
    static func explicitPort(in text: String) -> Int? {
        let patterns = [
            #"--port[= ](\d{2,5})"#,
            #"(?:^|\s)-p[= ]?(\d{2,5})\b"#,
            #"\bPORT=(\d{2,5})"#,
            #"--web-port[= ](\d{2,5})"#,
            #"runserver(?:\s+[\d.]+:|\s+)(\d{2,5})"#,
        ]
        for p in patterns {
            if let v = firstNumber(p, in: text) { return v }
        }
        return nil
    }

    /// .env, .env.local, .env.development içindeki PORT=
    static func envPort(in folder: URL) -> Int? {
        for name in [".env.local", ".env.development.local", ".env.development", ".env"] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            if let v = firstNumber(#"(?m)^\s*(?:export\s+)?PORT\s*=\s*["']?(\d{2,5})"#, in: text) { return v }
        }
        return nil
    }

    /// package.json script gövdesine bakarak port
    static func port(inScript body: String, folder: URL, envPort: Int?) -> Int? {
        if let v = explicitPort(in: body) { return v }
        let b = body.lowercased()
        // Yalnızca sunucu başlatan script'ler için tahmin yap
        let tools: [(String, Int)] = [
            ("vite build", 0), ("next build", 0), ("astro build", 0), ("nuxt build", 0),
            ("storybook", 6006), ("ng serve", 4200), ("expo start", 8081),
            ("astro", 4321), ("nuxt", 3000), ("next", 3000), ("react-scripts start", 3000),
            ("remix", 5173), ("svelte-kit", 5173), ("vite", 5173), ("webpack serve", 8080),
            ("nodemon", 0), ("node ", 0), ("tsx ", 0), ("ts-node", 0),
        ]
        for (tool, def) in tools where b.contains(tool) {
            if def == 0 {
                // build komutu ya da port'u koddan okuyan Node sunucusu: sadece .env'e güven
                return tool.hasSuffix("build") ? nil : envPort
            }
            if ["vite", "remix", "svelte-kit"].contains(tool), let v = viteConfigPort(in: folder) { return v }
            return envPort ?? def
        }
        return nil
    }

    static func viteConfigPort(in folder: URL) -> Int? {
        for name in ["vite.config.ts", "vite.config.js", "vite.config.mjs", "vite.config.mts"] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            if let v = firstNumber(#"\bport\s*:\s*(\d{2,5})"#, in: text) { return v }
        }
        return nil
    }

    /// docker compose: ilk "8080:80" eşlemesindeki host portu
    static func composePort(_ text: String) -> Int? {
        firstNumber(#"(?m)^\s*-\s*["']?(?:[\d.]+:)?(\d{2,5}):\d{2,5}"#, in: text)
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound,
              let v = Int(ns.substring(with: m.range(at: 1))), (1...65535).contains(v) else { return nil }
        return v
    }
}
