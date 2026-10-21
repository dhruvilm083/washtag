import SwiftUI

/// The short-ad gate shown on each cold launch, before the app opens.
/// It waits a few seconds for an ad, shows it, and lets the user in when it closes.
/// If no ad loads (offline, no fill, no consent), the user goes straight in.
struct AdGateView: View {
    var onDone: () -> Void
    @State private var status = "Getting things ready…"
    @State private var started = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark().frame(width: 72, height: 72)
                Text("Washtag").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Washtag is free thanks to a short ad.")
                    .font(.body).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                ProgressView().padding(.top, 6)
                Text(status).font(.footnote).foregroundStyle(Theme.ink2)
            }
            .padding(32)
        }
        .task {
            guard !started else { return }
            started = true
            await AdsManager.shared.prepare()
            status = "Loading a short ad…"
            // Give the ad up to ~4 seconds to arrive, then show it or move on.
            for _ in 0..<8 where !AdsManager.shared.isAdReady && AdsManager.shared.canRequestAds {
                try? await Task.sleep(for: .milliseconds(500))
            }
            AdsManager.shared.showIfAvailable { onDone() }
        }
    }
}

struct BrandMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 40
            var tub = Path()
            tub.move(to: CGPoint(x: 6 * s, y: 12 * s)); tub.addLine(to: CGPoint(x: 34 * s, y: 12 * s))
            tub.addLine(to: CGPoint(x: 31 * s, y: 32 * s)); tub.addLine(to: CGPoint(x: 9 * s, y: 32 * s)); tub.closeSubpath()
            ctx.stroke(tub, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round))
            var wave = Path()
            wave.move(to: CGPoint(x: 6 * s, y: 12 * s))
            wave.addCurve(to: CGPoint(x: 15 * s, y: 12 * s), control1: CGPoint(x: 9 * s, y: 15 * s), control2: CGPoint(x: 12 * s, y: 15 * s))
            wave.addCurve(to: CGPoint(x: 24 * s, y: 12 * s), control1: CGPoint(x: 18 * s, y: 9 * s), control2: CGPoint(x: 21 * s, y: 9 * s))
            wave.addCurve(to: CGPoint(x: 34 * s, y: 12 * s), control1: CGPoint(x: 27 * s, y: 15 * s), control2: CGPoint(x: 30 * s, y: 15 * s))
            ctx.stroke(wave, with: .color(Theme.tub), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
        }
    }
}
