# AGENTS.md — DevApp

Native macOS (SwiftUI, macOS 14+) çoklu ajan / terminal yöneticisi. Swift Package, tek executable target.

## Komutlar

- Derle: `swift build`
- Çalıştır: `swift run` ya da Xcode'da `Package.swift` → ⌘R
- Paketle: `./scripts/build-app.sh release`

## Kurallar

- Arayüz metinleri Türkçe.
- Swift 5 dil modu; UI ve store `@MainActor`. SwiftTerm delegate çağrıları ana kuyrukta gelir,
  `MainActor.assumeIsolated` ile köprülenir.
- Terminal NSView'leri `TerminalSession` sahipliğindedir. Asla SwiftUI içinde yeni `LocalProcessTerminalView`
  oluşturma; `TerminalHost` ile mevcut olanı yerleştir. Aynı oturumu aynı anda iki yerde gösterme.
- SwiftTerm sürümü `Package.swift` içinde sabitlenmiştir (1.20.0). Yükseltirken
  `LocalProcessTerminalViewDelegate` imzalarını kontrol et.
- Kalıcı durum: `AppStore.save()` → `~/Library/Application Support/DevApp/state.json`.
- Yeni ayar eklerken `SettingsKey` + `AppSettings` + `SettingsView` üçünü birlikte güncelle.
- Port, PID gibi sayıları `Text(verbatim:)` ile yaz: `Text("\(port)")` Türkçe yerel ayarda binlik ayraç ekler (3322 → "3.322").
- Widget: `Sources/DevAppWidget` (WidgetKit eklentisi) yalnızca `project.yml` (XcodeGen) ile derlenir;
  uygulama ile paylaşılan modeller `Sources/DevApp/Shared/` altında ve yalnızca Foundation kullanır.
- Kullanım verisi: `UsageService` (actor). Claude: `~/.claude/projects/**/*.jsonl`, Codex: `~/.codex/sessions/**/rollout-*`.
