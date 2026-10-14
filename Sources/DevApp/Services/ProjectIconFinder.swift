import Foundation
import AppKit

/// Proje klasöründe projeyi temsil eden logo / uygulama ikonunu bulur:
/// Xcode AppIcon.appiconset, .icns, Android/Flutter launcher ikonu, web favicon / apple-touch-icon / logo.
enum ProjectIconFinder {
    private static let skipDirs: Set<String> = [
        "node_modules", "Pods", "build", "DerivedData", ".build", "dist", "vendor", "target",
        "Carthage", ".next", ".nuxt", "out", "coverage", "tmp", ".git", ".dart_tool", "venv", ".venv",
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "icns", "ico", "svg", "webp"]

    /// En uygun ikonun yolu; bulunamazsa nil
    static func find(in root: String) -> String? {
        let rootURL = URL(fileURLWithPath: root)
        guard let walker = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var candidates: [(path: String, score: Int, size: Int)] = []
        var visited = 0

        for case let url as URL in walker {
            visited += 1
            if visited > 25_000 { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if skipDirs.contains(url.lastPathComponent) || walker.level > 6 { walker.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            let size = values?.fileSize ?? 0
            guard size > 200, size < 5_000_000 else { continue }
            // Puanlama kök klasöre göre göreli yolla yapılır (kullanıcının klasör adları etkilemesin)
            let relative = String(url.path.dropFirst(rootURL.path.count)).lowercased()
            let score = Self.score(relative: relative, name: url.deletingPathExtension().lastPathComponent.lowercased(),
                                   ext: ext, depth: walker.level)
            if score > 0 { candidates.append((url.path, score, size)) }
        }

        candidates.sort { $0.score != $1.score ? $0.score > $1.score : $0.size > $1.size }
        // Gerçekten açılabilen ilk resim
        for c in candidates.prefix(12) where NSImage(contentsOfFile: c.path) != nil {
            return c.path
        }
        return nil
    }

    private static func score(relative path: String, name: String, ext: String, depth: Int) -> Int {
        // Test, örnek ve üçüncü parti klasörlerini düşük tut
        let penalty = (path.contains("/test") || path.contains("/example") || path.contains("/fixture")
                       || path.contains("/docs/") || path.contains("/screenshots")) ? 40 : 0
        let shallow = max(0, 6 - depth) * 2   // köke yakın olan biraz önde

        var base = 0
        if path.contains("appicon.appiconset") && ext == "png" { base = 100 }
        else if ext == "icns" { base = 95 }
        else if path.contains("mipmap-xxxhdpi") && name.hasPrefix("ic_launcher") && !name.contains("foreground") { base = 85 }
        else if path.contains("mipmap-xxhdpi") && name.hasPrefix("ic_launcher") && !name.contains("foreground") { base = 80 }
        else if ["apple-touch-icon", "apple-icon", "logo512", "icon-512", "android-chrome-512x512"].contains(name) { base = 78 }
        else if ["logo", "app-icon", "appicon", "icon", "logo192", "brand", "mark"].contains(name) && ext != "ico" { base = 70 }
        else if name.hasPrefix("logo") && (path.contains("/public/") || path.contains("/assets/") || path.contains("/static/") || depth <= 1) { base = 62 }
        else if name == "favicon" && ext != "ico" { base = 58 }
        else if name == "favicon" { base = 50 }
        else { return 0 }
        return base + shallow - penalty
    }

    /// Widget için küçük PNG üretir
    static func pngData(from image: NSImage, size: CGFloat = 64) -> Data? {
        let target = NSSize(width: size, height: size)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
