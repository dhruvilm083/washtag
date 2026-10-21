import SwiftUI
import UIKit

/// Colours from the prototype, with the same light and dark values.
enum Theme {
    static let bg = dynamic(0xE6EDF1, 0x0E1524)
    static let surface = dynamic(0xFFFFFF, 0x172238)
    static let surface2 = dynamic(0xF3F7F9, 0x1D2A44)
    static let ink = dynamic(0x16233F, 0xE7EDF6)
    static let ink2 = dynamic(0x4A5874, 0xA7B4CB)
    static let line = dynamic(0xC9D5DD, 0x2C3B58)
    static let tub = dynamic(0x2358C9, 0x7FA6F5)
    static let tubSoft = dynamic(0xDCE6FA, 0x1E2F55)
    static let dry = dynamic(0xA8650F, 0xE9B062)
    static let drySoft = dynamic(0xF8EBD6, 0x3A2C17)
    static let care = dynamic(0x2E7D6B, 0x6FC7AF)
    static let careSoft = dynamic(0xDDF0EA, 0x16362F)
    static let stop = dynamic(0xB8372A, 0xF08A7C)
    static let stopSoft = dynamic(0xF8E0DC, 0x3E1E1B)
    static let tag = dynamic(0xFBFCFD, 0x1A263D)
    static let stitch = dynamic(0x8FA3B8, 0x50658A)
    static let good = dynamic(0x2E7D4F, 0x6BCB8F)
    static let mid = dynamic(0xB7791F, 0xE9B062)
    static let low = dynamic(0xB8372A, 0xF08A7C)

    static func confidenceColor(_ v: Double) -> Color { v >= 80 ? good : v >= 55 ? mid : low }
    static func confidenceWord(_ v: Double) -> String { v >= 80 ? "High" : v >= 55 ? "Medium" : "Low" }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum PersonColors {
    static let all: [Color] = [0x2358C9, 0xC4572F, 0x2E7D6B, 0x8A4FBF, 0xB7791F, 0xC23B6E, 0x3B8FA8, 0x5B6B2E].map { Color(UIColor(hex: $0)) }
    static func color(_ i: Int) -> Color { all[i % all.count] }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// White rounded card used for every panel.
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1.5))
    }
}

struct Chip: View {
    var label: String
    var selected: Bool
    var dot: Color? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 10, height: 10) }
                Text(label).font(.subheadline)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? Theme.bg : Theme.ink)
            .background(selected ? Theme.ink : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.ink : Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

struct Segmented: View {
    var options: [(value: String, label: String)]
    @Binding var selection: String
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.value) { o in
                Button { selection = o.value } label: {
                    Text(o.label).font(.subheadline.weight(selection == o.value ? .bold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selection == o.value ? Theme.tubSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selection == o.value ? Theme.tub : Theme.line, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == o.value ? .isSelected : [])
            }
        }
    }
}
