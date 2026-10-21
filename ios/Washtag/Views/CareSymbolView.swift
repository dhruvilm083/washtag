import SwiftUI

/// Generic ISO-style care pictograms, drawn the same way as the prototype's SVGs (40×42 grid).
struct CareSymbolView: View {
    var category: String
    var code: String = ""
    var prohibited = false
    var tempC: Double? = nil
    var tempLabel: String? = nil

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 40, size.height / 42)
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let ink = GraphicsContext.Shading.color(.primary)
            func stroke(_ path: Path, _ w: Double = 2.2) { ctx.stroke(path, with: ink, style: StrokeStyle(lineWidth: w * s, lineCap: .round, lineJoin: .round)) }
            func dots(_ n: Int, _ cx: Double, _ cy: Double) {
                let x0 = cx - Double(n - 1) * 5 / 2
                for i in 0..<n { ctx.fill(Path(ellipseIn: CGRect(x: (x0 + Double(i) * 5 - 1.6) * s, y: (cy - 1.6) * s, width: 3.2 * s, height: 3.2 * s)), with: ink) }
            }
            func text(_ t: String, _ x: Double, _ y: Double, _ fs: Double) {
                ctx.draw(Text(t).font(.system(size: fs * s, weight: .bold)).foregroundColor(.primary), at: p(x, y))
            }
            let c = code.lowercased()

            switch category {
            case "wash":
                var tub = Path()
                tub.move(to: p(5, 12)); tub.addLine(to: p(35, 12)); tub.addLine(to: p(31.5, 31)); tub.addLine(to: p(8.5, 31)); tub.closeSubpath()
                stroke(tub)
                var wave = Path()
                wave.move(to: p(5, 12))
                wave.addCurve(to: p(15, 12), control1: p(8, 15), control2: p(11.5, 15))
                wave.addCurve(to: p(25, 12), control1: p(18.5, 9), control2: p(22, 9))
                wave.addCurve(to: p(35, 12), control1: p(28, 15), control2: p(31.5, 15))
                stroke(wave)
                if c.contains("hand") {
                    var h = Path(); h.move(to: p(15, 25)); h.addCurve(to: p(24, 19), control1: p(17, 21), control2: p(20, 19)); stroke(h, 2)
                    var h2 = Path(); h2.move(to: p(13, 27)); h2.addLine(to: p(23, 27)); stroke(h2, 2)
                } else if let label = tempLabel ?? tempC.map({ String(Int($0)) }) {
                    text(label, 20, 23.5, 9)
                }
                let bars = (c.contains("permanent") || c.contains("press")) ? 1 : (c.contains("gentle") || c.contains("delicate") || c.contains("wool")) ? 2 : 0
                for i in 0..<bars { var b = Path(); b.move(to: p(8, 35 + Double(i) * 3)); b.addLine(to: p(32, 35 + Double(i) * 3)); stroke(b, 1.8) }
            case "bleach":
                var t = Path(); t.move(to: p(20, 6)); t.addLine(to: p(35, 33)); t.addLine(to: p(5, 33)); t.closeSubpath(); stroke(t)
                if c.contains("non_chlorine") || c.contains("oxygen") {
                    var l = Path(); l.move(to: p(16, 30)); l.addLine(to: p(22, 14)); l.move(to: p(21, 30)); l.addLine(to: p(27, 14)); stroke(l, 1.8)
                }
            case "dry":
                stroke(Path(CGRect(x: 6 * s, y: 6 * s, width: 28 * s, height: 28 * s)))
                if c.contains("tumble") {
                    stroke(Path(ellipseIn: CGRect(x: 10 * s, y: 10 * s, width: 20 * s, height: 20 * s)))
                    if c.contains("low") { dots(1, 20, 20) } else if c.contains("high") { dots(3, 20, 20) } else if c.contains("medium") || c.contains("normal") { dots(2, 20, 20) }
                } else if c.contains("line") {
                    var l = Path(); l.move(to: p(9, 10)); l.addCurve(to: p(31, 10), control1: p(15, 15), control2: p(25, 15)); stroke(l, 2)
                } else if c.contains("flat") {
                    var l = Path(); l.move(to: p(11, 20)); l.addLine(to: p(29, 20)); stroke(l)
                } else if c.contains("drip") {
                    var l = Path(); for x in [14.0, 20, 26] { l.move(to: p(x, 11)); l.addLine(to: p(x, 29)) }; stroke(l, 2)
                }
                if c.contains("shade") { var l = Path(); l.move(to: p(6, 16)); l.addLine(to: p(16, 6)); stroke(l, 2) }
            case "iron":
                var i = Path()
                i.move(to: p(6, 30)); i.addLine(to: p(34, 30))
                i.addCurve(to: p(23, 15), control1: p(34, 21), control2: p(31, 15))
                i.addLine(to: p(16, 15)); i.addCurve(to: p(12, 19), control1: p(13, 15), control2: p(12, 17)); i.addLine(to: p(12, 20))
                stroke(i)
                if c.contains("low") { dots(1, 20, 25) } else if c.contains("high") { dots(3, 20, 25) } else if c.contains("medium") { dots(2, 20, 25) }
            case "dryclean":
                stroke(Path(ellipseIn: CGRect(x: 7 * s, y: 7 * s, width: 26 * s, height: 26 * s)))
                if let r = c.range(of: "_(p|f|w|a)\\b", options: .regularExpression) {
                    text(String(c[r].dropFirst()).uppercased(), 20, 20.5, 12)
                }
            default:
                ctx.stroke(Path(ellipseIn: CGRect(x: 7 * s, y: 7 * s, width: 26 * s, height: 26 * s)), with: ink,
                           style: StrokeStyle(lineWidth: 2 * s, dash: [3 * s, 3 * s]))
                text("?", 20, 20.5, 13)
            }
            if prohibited {
                var x = Path(); x.move(to: p(6, 6)); x.addLine(to: p(34, 34)); x.move(to: p(34, 6)); x.addLine(to: p(6, 34)); stroke(x, 2.4)
            }
        }
        .aspectRatio(40 / 42, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension CareSymbolView {
    init(_ s: CareSymbol) {
        self.init(category: s.category ?? "other", code: s.code ?? "", prohibited: s.prohibited ?? false, tempC: s.tempC)
    }
}
