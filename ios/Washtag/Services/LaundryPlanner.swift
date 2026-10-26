import Foundation

/// Sorts a pile of saved items into machine loads and picks the order to run them,
/// using each item's care label and the household's washer and dryer specs.
enum LaundryPlanner {
    struct PlannedLoad: Identifiable {
        var id: String { items.map(\.id).joined(separator: ",") }
        var title: String
        var items: [ScanRecord]
        var combined: LoadPlanner.Combined
        var kg: Double
        var fill: Double            // share of the washer drum
        var size: String            // small | medium | large | xl, for the detergent dose
        var delicate: Bool
        var washCycle: String
        var spin: String
        var washMinutes: Int
        var dry: DryPlan
        var notes: [String]
    }

    struct DryPlan {
        var tumbleNames: [String]   // items that go in the dryer
        var airDry: [String]        // "Item: how"
        var setting: String
        var minutes: Int            // 0 when nothing goes in the dryer
        var dryerLoads: Int
    }

    struct Plan {
        var loads: [PlannedLoad]
        var notForMachine: [String]
        var totalMinutes: Int
        var orderWhy: [String]
    }

    // MARK: grouping

    private enum Care: Int { case sturdy, synthetic, gentle, wool, hand }
    private enum Colour: String { case whites, colours, darks }

    private struct Group {
        var care: Care
        var colour: Colour
        var hot: Bool
        var towels: Bool
        var items: [ScanRecord]
        var notes: [String] = []
        var kg: Double { items.reduce(0) { $0 + LaundryPlanner.weight($1) } }
    }

    static func plan(_ items: [ScanRecord], washer: Appliance?, dryer: Appliance?, units: Units) -> Plan {
        let washer = washer ?? Appliance.typical(.washer, type: "front")
        let dryer = dryer ?? Appliance.typical(.dryer, type: "electric")
        var notForMachine: [String] = []
        var groups: [Group] = []

        for it in items {
            let s = it.care?.structured ?? StructuredCare()
            if s.dryClean == "only" { notForMachine.append("\(it.name) — dry clean only"); continue }
            if s.washCycle == "do_not_wash" { notForMachine.append("\(it.name) — do not wash"); continue }
            let g = Group(care: care(it), colour: colour(it), hot: (s.maxWashTempC ?? 40) >= 50, towels: isTowel(it), items: [it])
            if let i = groups.firstIndex(where: { $0.care == g.care && $0.colour == g.colour && $0.hot == g.hot && $0.towels == g.towels }) {
                groups[i].items.append(it)
            } else { groups.append(g) }
        }

        // Merge small groups into the closest compatible one, so the plan doesn't run lots of tiny loads.
        let cap = washer.capacityKgEstimate
        while true {
            let small = groups.indices.filter { groups[$0].kg < cap * target(groups[$0]) * 0.4 }
                .sorted { groups[$0].kg < groups[$1].kg }
            var merged = false
            for i in small {
                let best = groups.indices.filter { $0 != i }
                    .map { ($0, mergeCost(groups[i], groups[$0])) }
                    .filter { $0.1 != nil }
                    .min { $0.1! < $1.1! }
                guard let j = best?.0 else { continue }
                var into = groups[j]
                let from = groups[i]
                if let why = mergeNote(from, into) { into.notes.append(why) }
                into.items += from.items
                if from.care.rawValue > into.care.rawValue { into.care = from.care }  // strictest care wins
                into.hot = into.hot && from.hot
                into.towels = into.towels && from.towels
                if from.colour != into.colour { into.colour = .colours }
                groups[j] = into
                groups.remove(at: i)
                merged = true
                break
            }
            if !merged { break }
        }

        // Split anything bigger than the drum should take.
        var split: [Group] = []
        for g in groups {
            let limit = cap * target(g)
            var chunk = g; chunk.items = []
            for it in g.items.sorted(by: { weight($0) > weight($1) }) {
                if !chunk.items.isEmpty && chunk.kg + weight(it) > limit {
                    split.append(chunk); chunk = g; chunk.items = []; chunk.notes = []
                }
                chunk.items.append(it)
            }
            if !chunk.items.isEmpty { split.append(chunk) }
        }

        var loads = split.map { load($0, washer: washer, dryer: dryer, units: units) }
        loads = order(loads)

        // Number repeated titles: "Darks 1", "Darks 2".
        let titles = loads.map(\.title)
        for i in loads.indices where titles.filter({ $0 == titles[i] }).count > 1 {
            loads[i].title += " \(titles[..<i].filter { $0 == titles[i] }.count + 1)"
        }

        var t = 0, dryerFree = 0
        for l in loads {
            t += l.washMinutes
            if l.dry.minutes > 0 { dryerFree = max(dryerFree, t) + l.dry.minutes }
        }
        var why: [String] = []
        if loads.count > 1 {
            why.append("Washtag recommends this order so your dryer is busy while the next load washes: quick-washing, slow-drying loads go first and air-dry loads go last.")
        }
        if loads.contains(where: { $0.dry.dryerLoads > 1 }) {
            why.append("Your dryer holds less than a full wash, so Washtag recommends drying the bigger loads in two goes for even drying.")
        }
        return Plan(loads: loads, notForMachine: notForMachine, totalMinutes: max(t, dryerFree), orderWhy: why)
    }

    /// Johnson's rule for two machines in a row: it finishes the whole pile in the least time.
    private static func order(_ loads: [PlannedLoad]) -> [PlannedLoad] {
        let first = loads.filter { $0.washMinutes < $0.dry.minutes }.sorted { $0.washMinutes < $1.washMinutes }
        let second = loads.filter { $0.washMinutes >= $0.dry.minutes }.sorted { $0.dry.minutes > $1.dry.minutes }
        return first + second
    }

    private static func target(_ g: Group) -> Double {
        switch g.care {
        case .sturdy: return g.towels ? 0.75 : 0.8
        case .synthetic: return 0.6
        case .gentle, .wool: return 0.5
        case .hand: return 0.35
        }
    }

    private static func mergeCost(_ a: Group, _ b: Group) -> Int? {
        let colourOK = a.colour == b.colour || (a.colour == .whites && b.colour == .colours) || (a.care.rawValue >= Care.gentle.rawValue && b.care.rawValue >= Care.gentle.rawValue && a.colour != .whites && b.colour != .whites)
        guard colourOK else { return nil }
        if a.towels != b.towels && (a.colour == .darks || b.care == .synthetic || a.care == .synthetic) { return nil }  // lint
        var cost = 0
        if a.colour != b.colour { cost += 4 }
        if a.hot != b.hot { cost += 1 }
        if a.towels != b.towels { cost += 3 }
        switch (a.care, b.care) {
        case let (x, y) where x == y: break
        case (.sturdy, .synthetic), (.synthetic, .sturdy): cost += 2
        case (.gentle, .hand), (.hand, .gentle), (.wool, .hand), (.hand, .wool), (.wool, .gentle), (.gentle, .wool): cost += 2
        default: return nil
        }
        return cost
    }

    private static func mergeNote(_ from: Group, _ into: Group) -> String? {
        if from.colour == .whites && into.colour != .whites { return "Only a few whites, so Washtag recommends washing them with light colours on cold, with a colour-catcher sheet." }
        if from.hot != into.hot { return "Hot-wash items are joining a cooler load, so everything washes at the lower temperature." }
        if from.care == .wool || into.care == .wool { return "Wool or silk is in this load, so Washtag recommends an enzyme-free wool detergent for all of it." }
        return nil
    }

    private static func load(_ g: Group, washer: Appliance, dryer: Appliance, units: Units) -> PlannedLoad {
        let c = LoadPlanner.combine(g.items, units: units)
        let kg = g.kg
        let fill = kg / washer.capacityKgEstimate
        let size = fill < 0.35 ? "small" : fill < 0.6 ? "medium" : fill < 0.85 ? "large" : "xl"
        let delicate = g.care.rawValue >= Care.gentle.rawValue || ["gentle", "hand"].contains(c.cycle)
        let isFront = washer.type == "front"

        let wantCycle: [String]
        switch c.cycle {
        case "hand": wantCycle = g.care == .wool ? ["wool", "hand", "delicate"] : ["hand", "wool", "delicate"]
        case "gentle": wantCycle = g.care == .wool ? ["wool", "delicate", "gentle", "hand"] : ["delicate", "gentle"]
        case "permanent_press": wantCycle = ["perm", "synthetic", "easy care", "casual", "wrinkle"]
        default:
            if g.towels { wantCycle = ["towel", "bulky", "bedding", "heavy", "cotton", "normal"] }
            else if g.colour == .whites && g.hot { wantCycle = ["white", "cotton", "normal"] }
            else { wantCycle = ["normal", "cotton", "everyday", "colou", "color"] }
        }
        let washCycle = machineCycle(washer.cycles, wantCycle) ?? (LoadPlanner.cycleName[c.cycle] ?? "Normal")

        let rpm = washer.maxSpinRpm
        let spin: String
        if delicate { spin = "Low" + (rpm.map { " (about \(min($0, 800)) rpm or less)" } ?? "") }
        else if c.cycle == "permanent_press" { spin = "Medium" + (rpm.map { " (about \(min($0, 1000)) rpm)" } ?? "") + " to limit creases" }
        else { spin = "High" + (rpm.map { " (up to \($0) rpm)" } ?? "") + " so it dries faster" }

        var washMinutes = ["hand": 35, "gentle": 40, "permanent_press": 50][c.cycle] ?? (g.towels ? 65 : 55)
        if isFront { washMinutes += 15 }

        // Drying: items that can't tumble come out first; the rest share the strictest heat.
        let tumbleItems = g.items.filter { $0.care?.structured?.tumble != "none" }
        let tc = LoadPlanner.combine(tumbleItems, units: units)
        let speed = ["heat_pump": 1.6, "condenser": 1.3][dryer.type] ?? 1
        var dryMinutes = 0, dryerLoads = 0
        var setting = "Nothing in this load goes in the dryer."
        if !tumbleItems.isEmpty {
            let tumbleKg = tumbleItems.reduce(0) { $0 + weight($1) }
            dryerLoads = Int((tumbleKg / (dryer.capacityKgEstimate * 0.85)).rounded(.up))
            let low = tc.tumble == "low" || delicate
            let want = low ? ["delicate", "low", "perm", "synthetic"] : g.towels ? ["towel", "heavy", "bulky", "normal"] : c.cycle == "permanent_press" ? ["perm", "synthetic", "casual", "normal"] : ["normal", "cotton", "regular"]
            let name = machineCycle(dryer.cycles, want) ?? (low ? "Delicates / low heat" : "Normal")
            let base = low ? 35 : g.towels ? 60 : c.cycle == "permanent_press" ? 40 : 50
            dryMinutes = Int(Double(base) * speed * max(1, Double(dryerLoads)))
            setting = "\(name) · \(low ? "low" : g.towels ? "high" : "medium") heat" + (dryer.sensorDry == false ? ", timed about \(Int(Double(base) * speed)) min" : ", sensor dry")
            if dryerLoads > 1 { setting += " · in \(dryerLoads) batches" }
        }

        var notes = g.notes
        if !c.airDry.isEmpty && !tumbleItems.isEmpty { notes.append("Washtag recommends pulling the air-dry items out before the rest go in the dryer.") }
        if g.colour == .darks { notes.append("Turn darks and jeans inside out and wash cold to keep the colour.") }
        if g.towels { notes.append("Skip fabric softener on towels — it makes them less absorbent.") }
        if delicate && washer.type == "top_agitator" { notes.append("Your agitator can snag delicates — use a mesh laundry bag.") }
        if fill > 1 { notes.append("This is more than your drum holds comfortably — split it if the clothes can't move freely.") }
        notes += c.conflicts

        return PlannedLoad(title: title(g, c), items: g.items, combined: c, kg: kg, fill: fill, size: size, delicate: delicate,
                           washCycle: washCycle, spin: spin, washMinutes: washMinutes,
                           dry: DryPlan(tumbleNames: tumbleItems.map(\.name), airDry: c.airDry, setting: setting, minutes: dryMinutes, dryerLoads: dryerLoads),
                           notes: notes)
    }

    private static func title(_ g: Group, _ c: LoadPlanner.Combined) -> String {
        switch g.care {
        case .hand: return "Hand wash"
        case .wool: return "Wool & silk"
        case .gentle: return "Delicates"
        case .synthetic: return g.colour == .darks ? "Dark synthetics" : "Synthetics & activewear"
        case .sturdy:
            if g.towels { return g.colour == .darks ? "Dark towels & bedding" : "Towels & bedding" }
            switch g.colour {
            case .whites: return g.hot ? "Whites (hot)" : "Whites"
            case .darks: return "Darks"
            case .colours: return g.hot ? "Colours (warm)" : "Colours"
            }
        }
    }

    /// Picks the machine's own cycle name that best matches, e.g. "Bulky / Bedding" for towels.
    static func machineCycle(_ cycles: [String], _ keywords: [String]) -> String? {
        for k in keywords { if let c = cycles.first(where: { $0.lowercased().contains(k) }) { return c } }
        return nil
    }

    // MARK: item guesses (from name, product and label text)

    private static func text(_ it: ScanRecord) -> String {
        [it.name, it.product?.productName, it.product?.color, it.product?.category, it.care?.product?.type, it.care?.product?.name, it.notes]
            .compactMap { $0 }.joined(separator: " ").lowercased()
    }

    private static func fibres(_ it: ScanRecord) -> String { (it.care?.labelText?.fibres ?? it.product?.material ?? "").lowercased() }

    private static func care(_ it: ScanRecord) -> Care {
        let s = it.care?.structured
        let f = fibres(it)
        if s?.washCycle == "hand" { return .hand }
        if ["wool", "silk", "cashmere", "merino", "alpaca", "mohair", "angora"].contains(where: { f.contains($0) }) { return .wool }
        if s?.washCycle == "gentle" { return .gentle }
        if s?.washCycle == "permanent_press" { return .synthetic }
        let t = text(it)
        let stretchy = ["elastane", "spandex", "lycra"].contains(where: { f.contains($0) })
        if stretchy || ["legging", "gym", "running", "sports", "activewear", "athletic", "yoga"].contains(where: { t.contains($0) }) { return .synthetic }
        return .sturdy
    }

    private static func colour(_ it: ScanRecord) -> Colour {
        let t = text(it)
        if ["black", "navy", "charcoal", "dark", "denim", "jeans", "indigo", "brown", "burgundy", "maroon", "olive", "forest green"].contains(where: { t.contains($0) }) { return .darks }
        if ["white", "ivory", "cream", "off-white"].contains(where: { t.contains($0) }) { return .whites }
        return .colours
    }

    private static func isTowel(_ it: ScanRecord) -> Bool {
        ["towel", "bath mat", "bedding", "sheet", "pillowcase", "duvet", "comforter", "blanket", "flannel", "washcloth"].contains(where: { text(it).contains($0) })
    }

    /// Rough dry weight in kg, used to fill the drum sensibly.
    static func weight(_ it: ScanRecord) -> Double {
        let t = text(it)
        let table: [(String, Double)] = [
            ("comforter", 2.0), ("duvet cover", 0.9), ("duvet", 2.0), ("blanket", 1.5), ("coat", 1.2), ("jacket", 1.0),
            ("bath mat", 0.8), ("beach towel", 0.8), ("hand towel", 0.15), ("washcloth", 0.06), ("towel", 0.6),
            ("sheet", 0.7), ("pillowcase", 0.15), ("jeans", 0.7), ("denim", 0.7), ("hoodie", 0.6), ("sweatshirt", 0.6),
            ("sweatpant", 0.5), ("jogger", 0.5), ("jumper", 0.45), ("sweater", 0.45), ("cardigan", 0.4), ("trouser", 0.5),
            ("pants", 0.5), ("chino", 0.5), ("dress", 0.35), ("skirt", 0.3), ("pyjama", 0.3), ("pajama", 0.3), ("shirt", 0.25),
            ("blouse", 0.2), ("shorts", 0.25), ("legging", 0.2), ("tee", 0.2), ("top", 0.2), ("sock", 0.05),
            ("bra", 0.08), ("underwear", 0.08), ("boxer", 0.08),
        ]
        return table.first { t.contains($0.0) }?.1 ?? 0.35
    }
}
