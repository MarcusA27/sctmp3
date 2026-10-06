import SwiftUI
import AppKit

struct Candidate: Identifiable, Equatable {
    let id = UUID()
    var url: String
    var title: String
    var uploader: String
    var duration: Int   // seconds

    var length: String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }
}

struct DownloadItem: Identifiable {
    let id = UUID()
    var url: String
    var title: String = ""
    var uploader: String = ""
    var thumbnail: String = ""
    var isPlaylist = false
    var count = 1
    var state: State = .fetching
    var alternates: [Candidate] = []   // other uploads found when gated
    var note: String = ""              // e.g. "that upload was also gated"
    var searched = false               // guard against repeated alternate searches

    enum State: Equatable {
        case fetching
        case queued
        case downloading(Double)   // 0...1
        case converting
        case searching             // looking for alternate uploads
        case gated                 // gated; show `alternates` to pick from
        case done(String)          // file (or folder) path
        case failed(String)
    }

    var isActive: Bool {
        switch state { case .done, .failed, .gated: return false; default: return true }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var quality = "320"
    @Published var items: [DownloadItem] = []
    @Published var dropTargeted = false
    @Published var saveDir: URL
    @Published var cookieBrowser: String {   // "none" | "chrome" | "safari" | ...
        didSet { UserDefaults.standard.set(cookieBrowser, forKey: cookieKey) }
    }

    private var processing = false
    private let saveDirKey = "saveDir"
    private let cookieKey = "cookieBrowser"

    /// The browser to pull login cookies from, or nil when off.
    private var cookies: String? { cookieBrowser == "none" ? nil : cookieBrowser }

    init() {
        let defaults = UserDefaults.standard
        if let p = defaults.string(forKey: saveDirKey) {
            saveDir = URL(fileURLWithPath: p)
        } else {
            let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            saveDir = music.appendingPathComponent("sctmp3", isDirectory: true)
        }
        cookieBrowser = defaults.string(forKey: cookieKey) ?? "none"
    }

    // MARK: - Input

    func submit() {
        let urls = Self.parseURLs(input)
        input = ""
        add(urls)
    }

    func add(_ urls: [String]) {
        let fresh = urls.filter { Engine.isSoundcloud($0) }
        guard !fresh.isEmpty else { return }
        for u in fresh {
            let item = DownloadItem(url: u)
            items.append(item)
            let id = item.id
            Task { await self.fetchInfo(id: id, url: u) }
        }
    }

    /// Pull the clipboard once; if it holds a SoundCloud URL, prefill the field.
    func peekClipboard() {
        guard input.isEmpty,
              let s = NSPasteboard.general.string(forType: .string),
              Engine.isSoundcloud(s) else { return }
        input = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseURLs(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Pipeline

    private func idx(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func fetchInfo(id: UUID, url: String) async {
        do {
            let t = try await Engine.info(url: url, cookies: cookies)
            if let i = idx(id) {
                items[i].title = t.title
                items[i].uploader = t.uploader
                items[i].thumbnail = t.thumbnail
                items[i].isPlaylist = t.isPlaylist
                items[i].count = t.count
                items[i].state = .queued
            }
            drainQueue()
        } catch {
            if let i = idx(id) {
                items[i].title = items[i].title.isEmpty ? shortURL(url) : items[i].title
                items[i].state = .failed(Self.friendly(error.localizedDescription))
            }
        }
    }

    private func drainQueue() {
        guard !processing else { return }
        processing = true
        Task {
            while let i = items.firstIndex(where: { $0.state == .queued }) {
                await process(id: items[i].id)
            }
            processing = false
        }
    }

    private func process(id: UUID) async {
        guard let start = idx(id), items[start].state == .queued else { return }
        items[start].state = .downloading(0)
        let url = items[start].url

        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            let before = mp3s()
            try await Engine.download(url: url, quality: quality, dir: saveDir, cookies: cookies) { [weak self] line in
                Task { @MainActor in self?.interpret(line, id: id) }
            }
            let path = (mp3s().subtracting(before).sorted { modDate($0) > modDate($1) }.first
                        ?? mp3s().sorted { modDate($0) > modDate($1) }.first)?.path ?? saveDir.path
            if let i = idx(id) {
                items[i].state = .done(path)
            }
        } catch {
            let msg = error.localizedDescription
            guard let i = idx(id) else { return }
            if Self.isGated(msg) {
                if !items[i].searched {
                    await findAlternates(id: id)                  // first gate → search
                } else if !items[i].alternates.isEmpty {
                    items[i].note = "That upload is also gated — try another."
                    items[i].state = .gated                        // let them pick again
                } else {
                    items[i].state = .failed(Self.friendly(msg))
                }
            } else {
                items[i].state = .failed(Self.friendly(msg))
            }
        }
    }

    // MARK: - Alternate uploads (for gated tracks)

    private func findAlternates(id: UUID) async {
        guard let i = idx(id) else { return }
        items[i].searched = true
        items[i].state = .searching
        let title = items[i].title, uploader = items[i].uploader, orig = items[i].url

        do {
            let cands = try await Engine.search(
                query: Self.searchQuery(title: title, uploader: uploader), limit: 16, cookies: cookies)
            let good = Self.rankCandidates(cands, excluding: orig, originalTitle: title)
            guard let j = idx(id) else { return }
            if good.isEmpty {
                items[j].state = .failed("Gated — no full-length upload found on SoundCloud.")
            } else {
                items[j].alternates = good
                items[j].note = ""
                items[j].state = .gated
            }
        } catch {
            guard let j = idx(id) else { return }
            items[j].state = .failed(Self.friendly(error.localizedDescription))
        }
    }

    func chooseAlternate(_ itemId: UUID, _ c: Candidate) {
        guard let i = idx(itemId) else { return }
        items[i].alternates.removeAll { $0.id == c.id }
        items[i].url = c.url
        items[i].title = c.title
        items[i].uploader = c.uploader
        items[i].thumbnail = ""
        items[i].note = ""
        items[i].state = .queued
        drainQueue()
    }

    static func isGated(_ raw: String) -> Bool {
        let l = raw.lowercased()
        return l.contains("drm") || l.contains("requested format is not available")
    }

    /// Strip parenthetical noise from the title and append the artist for a good search.
    static func searchQuery(title: String, uploader: String) -> String {
        var t = title.replacingOccurrences(of: #"[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        return (t + (uploader.isEmpty ? "" : " " + uploader)).trimmingCharacters(in: .whitespaces)
    }

    private static let stop: Set<String> = ["the", "a", "an", "on", "of", "to", "in", "and",
                                            "feat", "ft", "prod", "official", "audio", "video"]

    private static func words(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) })
    }

    /// Keep plausible full-length uploads, ranked by title overlap with the original.
    static func rankCandidates(_ cands: [Candidate], excluding orig: String, originalTitle: String) -> [Candidate] {
        let ow = words(originalTitle)
        return cands
            .filter { $0.url != orig && $0.duration >= 45 && $0.duration <= 1200 && !$0.title.isEmpty }
            .map { (c: $0, score: words($0.title).intersection(ow).count) }
            .filter { $0.score >= 1 }
            .sorted { $0.score > $1.score }
            .prefix(6)
            .map { $0.c }
    }

    private func interpret(_ line: String, id: UUID) {
        guard let i = idx(id) else { return }
        if case .done = items[i].state { return }
        if case .failed = items[i].state { return }

        if line.contains("[download]"),
           let m = line.range(of: #"([0-9]{1,3}(?:\.[0-9]+)?)%"#, options: .regularExpression) {
            let pct = Double(line[m].dropLast()) ?? 0
            items[i].state = .downloading(min(pct / 100.0, 1.0))
        } else if line.contains("[ExtractAudio]") || line.contains("[Metadata]")
                    || line.contains("[ThumbnailsConvertor]") || line.contains("Deleting original") {
            items[i].state = .converting
        }
    }

    func clearFinished() { items.removeAll { !$0.isActive } }

    // MARK: - Folder

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveDir
        if panel.runModal() == .OK, let dir = panel.url {
            saveDir = dir
            UserDefaults.standard.set(dir.path, forKey: saveDirKey)
        }
    }

    // MARK: - Helpers

    private func mp3s() -> Set<URL> {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: saveDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return Set(items.filter { $0.pathExtension.lowercased() == "mp3" })
    }

    private func modDate(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func shortURL(_ u: String) -> String {
        URL(string: u)?.lastPathComponent.replacingOccurrences(of: "-", with: " ") ?? u
    }

    static func friendly(_ raw: String) -> String {
        let l = raw.lowercased()
        if l.contains("drm") { return "DRM-protected by SoundCloud — can't be downloaded." }
        if l.contains("requested format is not available") {
            return "Only a 30-second preview exists — the full track is Go+/DRM-gated on SoundCloud."
        }
        if l.contains("geo") || l.contains("not available in your") { return "Not available in your region." }
        if l.contains("404") || l.contains("not found") { return "Track not found — it may be private or deleted." }
        if l.contains("403") || l.contains("forbidden") { return "Access denied — the track may be private." }
        if l.contains("yt-dlp") && l.contains("find") { return "yt-dlp isn't installed. Run: brew install yt-dlp ffmpeg" }
        // Strip the noisy "ERROR: [soundcloud] 12345:" prefix if present.
        if let r = raw.range(of: #"^ERROR:\s*\[[^\]]+\]\s*\d*:?\s*"#, options: .regularExpression) {
            return String(raw[r.upperBound...])
        }
        return raw
    }
}
