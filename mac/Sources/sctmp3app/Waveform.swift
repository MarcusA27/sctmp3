import SwiftUI

/// Continuously animating waveform. `intensity` (0...1) drives energy:
/// idle = gentle shimmer, active download = taller, faster, brighter bars.
struct Waveform: View {
    var intensity: Double
    var progress: Double?   // 0...1 when a download is active, else nil

    private let bars = 48

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let gap: CGFloat = 3
                let barW = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                let midY = size.height / 2
                let speed = 1.2 + intensity * 3.0
                let energy = 0.18 + intensity * 0.82

                for i in 0..<bars {
                    let phase = Double(i) / Double(bars)
                    // Layered sines for an organic, non-repeating look.
                    let a = sin(t * speed + phase * 8.0)
                    let b = sin(t * speed * 0.6 + phase * 17.0 + 1.3)
                    let c = sin(t * speed * 1.7 + phase * 5.0)
                    var h = (a * 0.5 + b * 0.3 + c * 0.2)
                    h = (h * 0.5 + 0.5)                       // 0...1
                    let env = 0.35 + 0.65 * sin(phase * .pi)  // taper at edges
                    let barH = max(barW, size.height * energy * h * env)

                    let x = CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: midY - barH / 2, width: barW, height: barH)
                    let path = Path(roundedRect: rect, cornerRadius: barW / 2)

                    // Bars left of the progress line glow "played".
                    let played = progress.map { phase <= $0 } ?? false
                    let color: Color = played
                        ? Color(red: 1.0, green: 0.45, blue: 0.15)
                        : Color(red: 1.0, green: 0.33, blue: 0.0)
                    let alpha = played ? 0.95 : (0.30 + 0.5 * h)
                    ctx.fill(path, with: .color(color.opacity(alpha)))
                }

                // Soft glow pass.
                ctx.addFilter(.blur(radius: 6))
                ctx.opacity = 0.35 * (0.4 + intensity)
            }
        }
        .frame(height: 92)
        .drawingGroup()
    }
}
