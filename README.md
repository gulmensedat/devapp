# DevApp

Claude, Codex ve terminal oturumlarını **tek pencerede** yönetmek için native macOS uygulaması.
Amaç: birden fazla ajanı ve işi aynı anda yürütürken tüm terminalleri görmek, aralarında hızlı geçmek
ve projeyi Xcode'da tek tıkla açmak.

## Özellikler (v0.4)

- **Görsel pano** — açılışta her proje renkli bir kart: harf ikonu, durum (Çalışıyor / Dikkat / Hata / Durdu),
  son çıktı satırlarının canlı önizlemesi, ▶/■ komutlar ve portlar, branch, ajan sayısı, Xcode ve büyük
  Başlat/Durdur düğmesi. Tümü / Çalışanlar / Dikkat bekleyen / Durmuş filtreleri, arama (`⌘F`), altta açık portlar.
  Karta tıklayınca proje ekranı açılır: büyük başlık, komut düğmeleri ve projenin terminal ızgarası.
  Soldaki ince şeritte pano, tüm terminaller ve proje ikonları var (`⌘0` pano, `⇧⌘0` tüm terminaller).
- **Dock menüsü** — Dock'taki DevApp simgesine sağ tıklayınca: sizi bekleyen oturumlar, projelere göre açık
  terminaller (▶︎ komut + port, ✳︎ Claude, ◆ Codex, $ terminal, ■ kapanmış), proje alt menüsü (aç, başlat/durdur,
  Xcode, yeni Claude), "Projeyi Başlat" ve Pano/Tüm Terminaller. Seçince pencere açılır ve o terminale odaklanır.
- **Claude & Codex kullanımı** — panonun üstünde iki kart: 5 saatlik ve haftalık limit yüzdesi (sıfırlanmaya kalan
  süreyle), bugünkü ve son 5 saatteki token. Codex limitleri `~/.codex/sessions` kayıtlarından otomatik okunur;
  Claude token'ları `~/.claude/projects` kayıtlarından sayılır, plan yüzdesi için Ayarlar > Kullanım'dan
  "Claude plan limitini göster"i açın (Claude Code oturum anahtarı Anahtar Zinciri'nden okunur, macOS izin ister).
- **Masaüstü widget'ları** — "Claude & Codex Kullanımı" (küçük/orta) ve "DevApp Projeleri" (orta/büyük: çalışan
  projeler, açık portlar, sizi bekleyenler, büyük boyda kullanım). Satıra tıklayınca DevApp o projeyi açar.
  Widget için Xcode projesiyle derlenmesi gerekir (aşağıda).
- **Uygulama ikonu** — `Support/AppIcon.icns` (kaynağı `scripts/make-icon.py`); `swift run` ile çalışırken de Dock'ta görünür.

- **Projeyi tek tıkla çalıştır** — proje eklenince komutlar otomatik bulunur: `package.json` script'leri
  (npm/pnpm/yarn/bun), Makefile hedefleri, docker compose, Procfile, Flutter, Django, Rails, Cargo, Go, Swift;
  monorepo'da bir alt seviyedeki klasörler de taranır. Kenar çubuğunda her komutun yanında ▶/■ var;
  proje satırındaki ▶ ya da `⌥⌘R` işaretli komutların hepsini (ör. web + api + compose) birlikte başlatır.
  Durdur önce `Ctrl-C` gönderir, kapanmazsa 3 sn sonra sonlandırır. Komut çıktısında `localhost:3000` gibi bir
  adres görünürse 🌐 ile tarayıcıda açılır. Komutları `⌥⌘E` ile düzenleyebilirsiniz.
- **Portlar** — her komutun portu projeden bulunur (`--port`, `.env` içindeki `PORT=`, `vite.config`,
  docker compose eşlemesi, framework varsayılanı: Vite 5173, Next 3000, Django 8000…) ve kenar çubuğunda
  `:3000` rozeti olarak görünür; port dinleniyorsa rozet yeşil olur, tıklayınca tarayıcıda açılır.
  Komut düzenleyicide Port sütununa farklı bir değer (ör. `8779`) yazarsanız komut `PORT=8779` ve uygunsa
  `--port 8779` ile başlatılır. Başlatırken port doluysa onu tutan süreç gösterilir; tek tıkla kapatıp başlatabilirsiniz.
- **Tüm terminaller tek ekranda** — ızgara modunda her oturum canlı; odak modunda biri büyük, diğerleri altta.
- **Gerçek terminal** — SwiftTerm ile gerçek PTY; `vim`, `htop`, Claude Code ve Codex TUI'leri olduğu gibi çalışır.
- **Tek tıkla ajan** — projede Claude / Codex / Terminal / özel komut (ör. `npm run dev`) oturumu.
  Ajan çıkınca terminal kapanmaz, aynı klasörde kabuğa düşer.
- **Çoklu ajan + git worktree** — "Gelişmiş…" ile aynı görevden N ajan başlat; her biri
  `~/.devapp/worktrees/<proje>/<branch>` altında kendi worktree'sinde çalışır, birbirini ezmez.
- **Durum takibi** — Çalışıyor / Boşta / Kapandı rozetleri. Uzun süren iş bittiğinde veya ajan zil
  çaldığında (girdi beklerken) oturum turuncuya döner, Dock'ta sayaç çıkar. `⌘J` ile sıradakine atla.
- **Toplu gönderim** — seçili terminallere aynı anda metin, `⌃C` veya `Esc` gönder.
- **Dış uygulamalar** — odaktaki terminalin klasörünü Xcode'da (`.xcworkspace` › `.xcodeproj` › `Package.swift`
  otomatik bulunur), Finder'da, VS Code/Cursor/Zed'de veya Ghostty/iTerm/Terminal'de aç.
- **Kalıcılık** — projeler, komutlar, portlar ve oturumlar her değişiklikte
  `~/Library/Application Support/DevApp/state.json` (+ `state.backup.json`) dosyasına yazılır; bilgisayar yeniden başlasa da kalır;
  açılışta yeniden başlatılır (isteğe bağlı olarak ajan konuşması sürdürülür).

## Kısayollar

| Kısayol | İşlem |
|---|---|
| `⌥⌘R` | Projeyi başlat (işaretli komutlar) |
| `⌥⌘.` | Projeyi durdur |
| `⌥⌘E` | Proje komutlarını düzenle |
| `⌘T` | Mevcut projede yeni terminal |
| `⇧⌘C` / `⇧⌘K` | Yeni Claude / Codex oturumu |
| `⌘N` | Gelişmiş yeni oturum (worktree, adet, ilk görev) |
| `⌘O` | Proje ekle (klasörü kenar çubuğuna sürüklemek de olur) |
| `⌘1` … `⌘9` | N. terminale odaklan |
| `⌃Tab` / `⌃⇧Tab` | Sonraki / önceki terminal |
| `⌘↩` | Izgara ↔ odak modu (kutu başlığına çift tık da olur) |
| `⌘J` | Dikkat bekleyen terminale git |
| `⇧⌘X` | Xcode'da aç |
| `⇧⌘F` | Finder'da göster |
| `⇧⌘T` | Harici terminalde aç |
| `⇧⌘B` | Toplu gönderim çubuğu |
| `⇧⌘R` / `⇧⌘W` | Terminali yeniden başlat / kapat |

## Çalıştırma

Gereksinim: macOS 14+, Xcode 16+.

```bash
# Xcode ile: Package.swift'i aç, DevApp şemasını seç, ⌘R
open Package.swift

# Komut satırından
swift run

# .app paketi oluşturup /Applications'a kur
./scripts/build-app.sh release --install
```

### Masaüstü widget'lı sürüm (Xcode projesi)

WidgetKit eklentisi Swift Package ile derlenemez; Xcode projesi [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile üretilir:

```bash
brew install xcodegen
echo TAKIM_ID > .devapp-team        # Xcode > Settings > Accounts > Team ID (ücretsiz Apple ID de olur)
./scripts/xcode.sh build             # derler, /Applications'a kurar ve açar
# ya da ./scripts/xcode.sh → Xcode'da açar, ⌘R
```

Sonra masaüstüne sağ tık > **Widget'ları Düzenle** > **DevApp**. Widget verisi DevApp açıkken
App Group kabına (`~/Library/Group Containers/<TAKIM>.devapp.shared/snapshot.json`) yazılır.

## Ayarlar (`⌘,`)

- Claude / Codex komutu (ör. `claude --model opus`, `codex --full-auto`)
- Kabuk, yazı boyutu
- **Option = Meta** varsayılan kapalı (Türkçe klavyede `@`, `#` vb. için)
- Açılışta oturumları geri yükle / ajan konuşmasını sürdür

## Mimari

```
Sources/DevApp/
  App/        DevAppApp (giriş, menüler), AppStore (tüm durum, odak, kalıcılık)
  Models/     Project, SessionSpec, SessionKind, ayarlar
  Terminal/   TerminalSession (PTY süreci + kalıcı NSView), AgentTerminalView
  Services/   Git (worktree, branch), Launcher (Xcode/editör/terminal açma), CommandDetector (komut bulma)
  Views/      Sidebar, Workspace (ızgara/odak), TerminalTile, BroadcastBar, NewSessionSheet, Settings
```

Kritik nokta: her oturumun `LocalProcessTerminalView`'i bir kez oluşturulur ve `TerminalHost`
yalnızca onu taşıyıcıya takar. Böylece yerleşim değişse de süreç ve ekran geçmişi kaybolmaz.

## Yol haritası

- [ ] Görev panosu: iş kartı = worktree + ajan + terminaller, durum sütunları
- [ ] Worktree'yi birleştir/sil, diff önizleme
- [ ] Claude Code / Codex hook'ları ile kesin "bitti / onay bekliyor" durumu
- [ ] Bölünmüş görünüm (yan yana 2 terminal), sürükle-bırak sıralama
- [ ] Sistem bildirimleri, komut paleti (`⌘K`)
- [ ] Oturum başına kalıcı scrollback
