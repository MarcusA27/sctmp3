import SwiftUI
import AppKit

// MARK: - Background

/// Frosts the desktop behind the window (real vibrancy) so the frame is see-through.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Translucent dark tint + slowly drifting orange/violet light blobs for the glass to refract.
/// Kept see-through so the desktop shows through the vibrancy behind it.
struct Background: View {
    var intensity: Double

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    Color(red: 0.03, green: 0.035, blue: 0.05).opacity(0.15)
                    blob(scOrange, at: point(0.22, 0.14, t, 0.06, geo),
                         radius: 300, opacity: 0.55 + 0.30 * intensity, geo: geo)
                    blob(Color(red: 1, green: 0.55, blue: 0.15), at: point(0.82, 0.26, t, 0.05, geo),
                         radius: 240, opacity: 0.38 + 0.28 * intensity, geo: geo)
                    blob(Color(red: 0.09, green: 0.09, blue: 0.11), at: point(0.68, 0.92, t, 0.045, geo),
                         radius: 340, opacity: 0.55, geo: geo)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func point(_ fx: Double, _ fy: Double, _ t: Double, _ speed: Double, _ geo: GeometryProxy) -> CGPoint {
        let dx = sin(t * speed) * 40
        let dy = cos(t * speed * 0.8) * 34
        return CGPoint(x: geo.size.width * fx + dx, y: geo.size.height * fy + dy)
    }

    private func blob(_ color: Color, at p: CGPoint, radius: CGFloat, opacity: Double, geo: GeometryProxy) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .position(p)
            .blur(radius: 40)
    }
}

// MARK: - Window chrome

/// Makes the hosting window borderless-feeling: transparent titlebar, full-size content,
/// draggable by background, forced dark.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.appearance = NSAppearance(named: .darkAqua)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Dot arrow button

/// A downward arrow drawn from glowing white dots. Subtle glow at rest,
/// scales up and brightens when the cursor is over it.
struct DotArrowButton: View {
    var enabled: Bool
    var action: () -> Void
    @State private var hover = false

    // Dot centers in a 34×30 space: horizontal shaft + right-pointing chevron.
    private let dots: [CGPoint] = [
        // shaft
        CGPoint(x: 2,  y: 15), CGPoint(x: 6,  y: 15), CGPoint(x: 10, y: 15),
        CGPoint(x: 14, y: 15), CGPoint(x: 18, y: 15), CGPoint(x: 22, y: 15),
        // arrowhead
        CGPoint(x: 30, y: 15),                        // tip
        CGPoint(x: 22, y: 7),  CGPoint(x: 26, y: 11),
        CGPoint(x: 22, y: 23), CGPoint(x: 26, y: 19),
    ]

    private let boxW: CGFloat = 34
    private let sigma = 0.15          // width of the wave bump
    private let period = 1.1          // seconds for one left→right sweep

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !hover)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let front = (t / period).truncatingRemainder(dividingBy: 1)   // 0→1 sweep
                ZStack {
                    ForEach(dots.indices, id: \.self) { i in
                        let nx = dots[i].x / boxW
                        let d = nx - front
                        let bump = hover ? exp(-(d * d) / (2 * sigma * sigma)) : 0
                        Circle()
                            .fill(.white)
                            .frame(width: 3.2, height: 3.2)
                            .scaleEffect(1 + bump * 0.7)
                            .shadow(color: .white.opacity(0.4 + bump * 0.6), radius: 2 + bump * 3)
                            .position(dots[i])
                    }
                }
                .frame(width: boxW, height: 30)
            }
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 && enabled }
    }
}

// MARK: - Progress bar

struct Bar: View {
    var value: Double?   // nil = indeterminate (converting)

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                if let v = value {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.5, blue: 0.15), scOrange],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, g.size.width * min(max(v, 0), 1)))
                        .shadow(color: scOrange.opacity(0.6), radius: 5)
                } else {
                    TimelineView(.animation) { tl in
                        let phase = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)) / 1.2
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.5, blue: 0.15), scOrange],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * 0.4)
                            .offset(x: (g.size.width * 1.0) * phase - g.size.width * 0.4)
                            .shadow(color: scOrange.opacity(0.6), radius: 5)
                    }
                    .mask(Capsule())
                }
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Thumbnail

struct Thumb: View {
    var url: String
    var size: CGFloat = 46

    var body: some View {
        AsyncImage(url: URL(string: url)) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Rectangle().fill(.white.opacity(0.06))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.08)))
    }
}

// MARK: - Queue row

struct QueueRow: View {
    let item: DownloadItem
    let onReveal: (String) -> Void
    let onChoose: (Candidate) -> Void

    private let amber = Color(red: 1, green: 0.7, blue: 0.3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Thumb(url: item.thumbnail)

                VStack(alignment: .leading, spacing: 5) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    stateView
                }

                Spacer(minLength: 6)
                trailing
            }

            if case .gated = item.state, !item.alternates.isEmpty {
                alternatesList
            }
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var displayTitle: String {
        item.title.isEmpty ? "Reading link…" : item.title
    }

    @ViewBuilder private var stateView: some View {
        switch item.state {
        case .fetching:
            caption("Reading link…")
        case .queued:
            caption("Queued")
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 4) {
                Bar(value: p)
                caption("\(Int(p * 100))%")
            }
        case .converting:
            VStack(alignment: .leading, spacing: 4) {
                Bar(value: nil)
                caption("Converting to MP3…")
            }
        case .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                caption("Finding another upload…")
            }
        case .gated:
            Text(item.note.isEmpty ? "Gated — pick a full-length upload:" : item.note)
                .font(.system(size: 11))
                .foregroundStyle(amber)
                .lineLimit(2)
        case .done:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                .lineLimit(2)
        }
    }

    private var alternatesList: some View {
        VStack(spacing: 5) {
            ForEach(item.alternates) { c in
                Button { onChoose(c) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(scOrange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            Text(c.uploader).font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(c.length).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.05)))
            }
        }
    }

    private var subtitle: String {
        item.uploader.isEmpty ? "Saved" : "Saved · \(item.uploader)"
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
    }

    @ViewBuilder private var trailing: some View {
        switch item.state {
        case .fetching, .queued:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .downloading, .converting, .searching:
            EmptyView()
        case .gated:
            Image(systemName: "lock.fill")
                .font(.system(size: 12)).foregroundStyle(amber.opacity(0.8))
        case .done(let path):
            Button { onReveal(path) } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
            }.buttonStyle(.plain)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.7))
        }
    }
}

