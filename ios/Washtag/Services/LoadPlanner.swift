import Foundation

/// Port of the prototype's "This load" logic: strictest label wins, then a detergent dose.
enum LoadPlanner {
    struct Combined {
        var maxTemp: Double?
        var cycle = "normal"
        var bleach = "any"
        var tumble = "normal"
        var noMachine: [String] = []
        var dryCleanOnly: [String] = []
        var airDry: [String] = []
        var ironMax: String?
        var conflicts: [String] = []
    }

    struct Dose { var amount: String; var unit: String; var detail: String }

    static let cycleRank = ["normal": 0, "permanent_press": 1, "gentle": 2, "hand": 3]
    static let cycleName = ["normal": "Normal / cottons", "permanent_press": "Permanent press / synthetics",
                            "gentle": "Gentle / delicates", "hand": "Hand wash (or machine hand-wash cycle)"]

    static func combine(_ items: [ScanRecord], units: Units) -> Combined {
        var out = Combined()
        let ironRank = ["none": 0, "low": 1, "medium": 2, "high": 3]
        for it in items {
            let s = it.care?.structured ?? StructuredCare()
            if s.washCycle == "do_not_wash" || s.dryClean == "only" {
                if s.dryClean == "only" { out.dryCleanOnly.append(it.name) } else { out.noMachine.append(it.name) }
                continue
            }
            if let t = s.maxWashTempC { out.maxTemp = min(out.maxTemp ?? t, t) }
            if let c = s.washCycle, (cycleRank[c] ?? 0) > (cycleRank[out.cycle] ?? 0) { out.cycle = c }
            if s.bleach == "none" || (s.bleach == "non_chlorine" && out.bleach == "any") { out.bleach = s.bleach! }
            if s.tumble == "none" { out.tumble = "none" } else if s.tumble == "low" && out.tumble != "none" { out.tumble = "low" }
            if s.tumble == "none" {
                let how = ["line": "line dry", "flat": "dry flat", "drip": "drip dry", "shade": "dry in shade"][s.naturalDry ?? ""] ?? "air dry"
                out.airDry.append("\(it.name): \(how)")
            }
            if let i = s.iron {
                if let cur = out.ironMax { if (ironRank[i] ?? 0) < (ironRank[cur] ?? 0) { out.ironMax = i } } else { out.ironMax = i }
            }
        }
        let washable = items.filter { !out.noMachine.contains($0.name) && !out.dryCleanOnly.contains($0.name) }
        let temps = washable.compactMap { $0.care?.structured?.maxWashTempC }
        if temps.count > 1, let hi = temps.max(), let lo = temps.min(), hi - lo >= 30 {
            out.conflicts.append("Some items can take \(tempString(hi, units)) but others only \(tempString(lo, units)). Everything will wash at the lower temperature — consider splitting hot-wash items (towels, bedding) into their own load.")
        }
        let cycles = washable.compactMap { $0.care?.structured?.washCycle }
        if cycles.contains("hand") && cycles.contains("normal") {
            out.conflicts.append("Hand-wash items are mixed with sturdy ones. Heavy items can stretch or snag delicates — wash them separately or in a mesh bag.")
        }
        let fibres = washable.map { ($0.care?.labelText?.fibres ?? "").lowercased() }
        let hasWoolSilk = fibres.contains { $0.contains("wool") || $0.contains("silk") || $0.contains("cashmere") }
        let hasCotton = fibres.contains { ($0.contains("cotton") || $0.contains("denim")) && !$0.contains("wool") && !$0.contains("silk") }
        if hasWoolSilk && hasCotton {
            out.conflicts.append("Wool or silk is mixed with cotton. Wool and silk need a detergent without enzymes; use one for the whole load or split it.")
        }
        return out
    }

    static func dose(_ L: LoadSettings, delicate: Bool, units: Units) -> Dose {
        let size = ["small": 0.7, "medium": 1, "large": 1.4, "xl": 1.8][L.size] ?? 1
        let soil = ["light": 0.8, "normal": 1, "heavy": 1.3][L.soil] ?? 1
        let water = ["soft": 0.85, "medium": 1, "hard": 1.25, "unknown": 1][L.water] ?? 1
        let machine = L.machine == "standard" ? 1.25 : 1
        let f = size * soil * water * machine * (delicate ? 0.8 : 1)

        switch L.form {
        case "pod":
            let n = f <= 1.15 ? 1 : f <= 1.9 ? 2 : 3
            return Dose(amount: "\(n)", unit: n == 1 ? "pod" : "pods", detail: "Put pods in the empty drum before the clothes — never in the dispenser.")
        case "powder":
            let g = Int((60 * f / 5).rounded()) * 5
            return Dose(amount: "\(g)", unit: "g powder", detail: "Roughly \(Int((Double(g) / 15).rounded())) level tablespoons")
        default:
            let ml = Int((30 * f / 5).rounded()) * 5
            let floz = (Double(ml) / 29.57 * 4).rounded() / 4
            let tbsp = (Double(ml) / 15 * 2).rounded() / 2
            return units == .us
                ? Dose(amount: trim(floz), unit: "fl oz liquid", detail: "\(ml) ml · about \(trim(tbsp)) tablespoons")
                : Dose(amount: "\(ml)", unit: "ml liquid", detail: "About \(trim(tbsp)) tablespoons · \(trim(floz)) fl oz")
        }
    }

    static func tempAdvice(_ c: Combined, _ L: LoadSettings, units: Units) -> String {
        guard let t = c.maxTemp else {
            return L.needs.contains("eco") ? "Cold (30°C / 86°F) — no label limits in this load" : "Use the warmest the fabric allows; no label limits known for this load"
        }
        if L.needs.contains("eco") && t > 30 { return "\(tempString(30, units)) to save energy — labels allow up to \(tempString(t, units))" }
        if L.needs.contains("darks") && t > 30 { return "\(tempString(30, units)) to keep colours from fading (max allowed \(tempString(t, units)))" }
        return "Up to \(tempString(t, units))"
    }

    static func extras(_ c: Combined, _ L: LoadSettings) -> [String] {
        var x: [String] = []
        if L.needs.contains("stains") || L.soil == "heavy" {
            x.append(c.bleach == "none" ? "Pre-treat stains with a stain remover — no bleach of any kind for this load." : "Pre-treat stains; an oxygen booster (dose per the tub) helps with heavy soil.")
        }
        if L.needs.contains("whites") && c.bleach != "none" {
            x.append(c.bleach == "any" ? "For whites only: chlorine bleach is allowed — measure by the bottle and never mix with ammonia or vinegar." : "For whites: oxygen (non-chlorine) bleach only.")
        }
        if L.water == "hard" { x.append("Hard water: the dose above is already raised. A water softener additive can also help.") }
        if L.needs.contains("active") || L.needs.contains("towels") {
            x.append("Skip fabric softener — it traps odour in activewear and makes towels less absorbent. A splash of white vinegar in the softener drawer is an alternative.")
        }
        if L.needs.contains("pets") { x.append("Run a 10-minute no-heat tumble before washing to loosen pet hair, if the labels allow tumbling.") }
        if L.needs.contains("baby") || L.needs.contains("sensitive") || L.needs.contains("fragrance") {
            x.append("Use a fragrance-free, dye-free detergent and add an extra rinse.")
        }
        return x
    }

    private static func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

func tempString(_ c: Double?, _ units: Units) -> String {
    guard let c else { return "—" }
    let f = Int((c * 9 / 5 + 32).rounded())
    let ci = Int(c.rounded())
    return units == .us ? "\(f)°F (\(ci)°C)" : "\(ci)°C (\(f)°F)"
}
