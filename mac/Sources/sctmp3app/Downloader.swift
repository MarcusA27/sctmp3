import Foundation

struct TrackInfo {
    var title: String
    var uploader: String
    var thumbnail: String
    var isPlaylist: Bool
    var count: Int
}

enum DLError: LocalizedError {
    case notFound
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .notFound: return "Couldn't find yt-dlp. Install it with: brew install yt-dlp ffmpeg"
        case .failed(let m): return m
        }
    }
}

/// Reference-typed buffer so process I/O handlers mutate shared state safely.
final class OutputBuffer {
    private let lock = NSLock()
    private var out = Data()
    private var err = ""
    func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
    func appendErr(_ s: String) { lock.lock(); err += s; lock.unlock() }
    var outString: String { lock.lock(); defer { lock.unlock() }; return String(data: out, encoding: .utf8) ?? "" }
    var errString: String { lock.lock(); defer { lock.unlock() }; return err }
}

enum Engine {
    /// Locate the yt-dlp binary across common install paths.
    static func ytdlpPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    /// Directories that must be on PATH so yt-dlp can find ffmpeg.
    static var toolPath: String {
        "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin"
    }

    static func isSoundcloud(_ s: String) -> Bool {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = u.host else { return false }
        return host.hasSuffix("soundcloud.com")
    }

    @discardableResult
    static func run(
        _ args: [String],
        onLine: ((String) -> Void)? = nil
    ) async throws -> String {
        guard let bin = ytdlpPath() else { throw DLError.notFound }

        let buf = OutputBuffer()

        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = toolPath
            p.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { buf.appendOut(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
                buf.appendErr(s)
                if let onLine {
                    for line in s.split(separator: "\n") where !line.isEmpty {
                        onLine(String(line))
                    }
                }
            }

            p.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    cont.resume(returning: buf.outString)
                } else {
                    let msg = buf.errString.trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: DLError.failed(msg.isEmpty ? "yt-dlp exited \(proc.terminationStatus)" : msg))
                }
            }

            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// `--cookies-from-browser` args when a browser is chosen (for login-gated tracks).
    static func cookieArgs(_ browser: String?) -> [String] {
        guard let b = browser, b != "none", !b.isEmpty else { return [] }
        return ["--cookies-from-browser", b]
    }

    static func info(url: String, cookies: String?) async throws -> TrackInfo {
        let raw = try await run(cookieArgs(cookies) + [
            "--dump-single-json", "--flat-playlist", "--no-warnings", url,
        ])
        guard let data = raw.data(using: .utf8),
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DLError.failed("Couldn't read track info")
        }
        let entries = j["entries"] as? [Any]
        var thumb = j["thumbnail"] as? String ?? ""
        if thumb.isEmpty, let thumbs = j["thumbnails"] as? [[String: Any]] {
            thumb = thumbs.last?["url"] as? String ?? ""
        }
        return TrackInfo(
            title: j["title"] as? String ?? "Untitled",
            uploader: (j["uploader"] as? String) ?? (j["uploader_id"] as? String) ?? "",
            thumbnail: thumb,
            isPlaylist: entries != nil,
            count: entries?.count ?? 1
        )
    }

    /// Downloads + converts into `dir`. `quality` is "320" or "128".
    static func download(
        url: String,
        quality: String,
        dir: URL,
        cookies: String?,
        onLine: @escaping (String) -> Void
    ) async throws {
        let bitrate = quality == "128" ? "128K" : "320K"
        let template = dir.appendingPathComponent("%(title)s.%(ext)s").path
        try await run(cookieArgs(cookies) + [
            // Exclude SoundCloud's 30s preview streams so a gated/DRM track
            // fails loudly instead of silently saving a snippet.
            "-f", "ba[format_id!*=preview]",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--postprocessor-args", "ffmpeg:-b:a \(bitrate)",
            "--embed-thumbnail",
            "--embed-metadata",
            "--no-warnings",
            "--newline",
            "-o", template,
            url,
        ], onLine: onLine)
    }

    /// Searches SoundCloud for other uploads of a track (used when one is gated).
    static func search(query: String, limit: Int, cookies: String?) async throws -> [Candidate] {
        let out = try await run(cookieArgs(cookies) + [
            "--flat-playlist", "--no-warnings",
            "--print", "%(url)s\t%(title)s\t%(uploader)s\t%(duration)s",
            "scsearch\(limit):\(query)",
        ])
        var result: [Candidate] = []
        for raw in out.split(separator: "\n") {
            let p = String(raw).components(separatedBy: "\t")
            guard p.count >= 4, !p[0].isEmpty else { continue }
            result.append(Candidate(url: p[0], title: p[1], uploader: p[2],
                                    duration: Int(Double(p[3]) ?? 0)))
        }
        return result
    }
}
