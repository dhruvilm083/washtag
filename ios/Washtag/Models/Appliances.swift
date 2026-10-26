import Foundation

// MARK: - Washer and dryer (shape matches appliancePrompt in the backend)

enum ApplianceKind: String, Codable { case washer, dryer }

struct Appliance: Codable, Hashable {
    var kind: ApplianceKind
    var brand = ""
    var model = ""
    var name: String?
    /// washer: front | top_he | top_agitator · dryer: electric | gas | heat_pump | condenser
    var type: String
    var capacityCuFt: Double?
    var capacityKg: Double?
    var detergent: String?      // washer: he | standard
    var maxSpinRpm: Int?
    var hasHeater: Bool?        // washer heats its own water
    var sensorDry: Bool?        // dryer stops when clothes are dry
    var steam: Bool?
    var cycles: [String] = []
    var tips: [String] = []
    var source = "default"      // lookup | manual | default
    var confidence: Double?
    var basis: String?

    /// What the drum holds, in kg. US makers quote cubic feet, so convert roughly when that's all we have.
    var capacityKgEstimate: Double {
        if let capacityKg, capacityKg > 0 { return capacityKg }
        if let capacityCuFt, capacityCuFt > 0 { return capacityCuFt * (kind == .washer ? 2.2 : 1.4) }
        return Appliance.typical(kind, type: type).capacityKg ?? 8
    }

    var title: String {
        let t = [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
        return t.isEmpty ? (Appliance.typeNames[type] ?? type) : t
    }

    var isHE: Bool { kind == .washer && (detergent ?? (type == "top_agitator" ? "standard" : "he")) == "he" }

    static let washerTypes: [(value: String, label: String)] = [("front", "Front loader"), ("top_he", "Top loader (HE, no agitator)"), ("top_agitator", "Top loader with agitator")]
    static let dryerTypes: [(value: String, label: String)] = [("electric", "Electric vented"), ("gas", "Gas"), ("heat_pump", "Heat pump"), ("condenser", "Condenser")]
    static let typeNames = Dictionary(uniqueKeysWithValues: (washerTypes + dryerTypes).map { ($0.value, $0.label) })

    /// Built-in specs for when the model can't be looked up. Typical for the type, not for a specific machine.
    static func typical(_ kind: ApplianceKind, type: String) -> Appliance {
        switch (kind, type) {
        case (.washer, "top_he"):
            return Appliance(kind: .washer, type: type, capacityCuFt: 5.0, capacityKg: 11, detergent: "he", maxSpinRpm: 800, hasHeater: false, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Whites", "Towels", "Perm Press", "Delicates", "Hand Wash", "Quick Wash", "Rinse & Spin"],
                             tips: ["Use HE detergent only, and no more than the cap's line 1 or 2 — extra suds stop the low-water rinse working.",
                                    "Load loosely around the wash plate; don't wrap long items around the centre.",
                                    "Leave the lid open after washing so the tub dries out."])
        case (.washer, "top_agitator"):
            return Appliance(kind: .washer, type: type, capacityCuFt: 4.0, capacityKg: 8, detergent: "standard", maxSpinRpm: 700, hasHeater: false, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Bulky", "Whites", "Perm Press", "Delicates", "Quick Wash", "Rinse & Spin"],
                             tips: ["Standard or HE detergent both work; add it to the water before the clothes.",
                                    "Don't load above the top row of holes in the tub, so clothes can turn over.",
                                    "The agitator is rough on delicates — use a mesh bag and the Delicates cycle."])
        case (.washer, _):
            return Appliance(kind: .washer, type: "front", capacityCuFt: 4.5, capacityKg: 10, detergent: "he", maxSpinRpm: 1200, hasHeater: true, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Whites", "Towels", "Perm Press", "Delicates", "Hand Wash / Wool", "Quick Wash", "Rinse & Spin", "Self Clean"],
                             tips: ["Use HE detergent only; liquid in the dispenser, pods in the empty drum.",
                                    "Fill the drum loosely to about a hand's width from the top for normal cycles.",
                                    "Leave the door ajar and wipe the gasket after washing to stop mildew.",
                                    "Run the clean cycle about once a month."])
        case (.dryer, "heat_pump"):
            return Appliance(kind: .dryer, type: type, capacityCuFt: 4.0, capacityKg: 8, sensorDry: true, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Bulky", "Towels", "Perm Press", "Delicates", "Wool", "Timed Dry", "Air Fluff"],
                             tips: ["Heat pump dryers run cooler and take longer, which is kinder to fabrics.",
                                    "Clean the lint filter every load and the condenser filter every few loads.",
                                    "Empty the water tank (if not plumbed to a drain)."])
        case (.dryer, "condenser"):
            return Appliance(kind: .dryer, type: type, capacityCuFt: 4.0, capacityKg: 8, sensorDry: true, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Towels", "Perm Press", "Delicates", "Timed Dry", "Air Fluff"],
                             tips: ["Clean the lint filter every load and rinse the condenser regularly.",
                                    "Empty the water tank after each load (if not plumbed to a drain)."])
        default:
            return Appliance(kind: .dryer, type: type == "gas" ? "gas" : "electric", capacityCuFt: 7.4, capacityKg: 11, sensorDry: true, steam: false,
                             cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Towels", "Perm Press", "Delicates", "Timed Dry", "Air Fluff"],
                             tips: ["Clean the lint filter before every load — it saves energy and is a fire-safety must.",
                                    "Use the sensor (auto) cycles rather than timed dry so clothes aren't over-dried.",
                                    "Don't fill more than about three-quarters full so clothes can tumble."])
        }
    }
}

struct ApplianceLookup: Decodable {
    var found: Bool?
    var confidence: Double?
    var name: String?
    var type: String?
    var capacityCuFt: Double?
    var capacityKg: Double?
    var detergent: String?
    var maxSpinRpm: Int?
    var hasHeater: Bool?
    var sensorDry: Bool?
    var steam: Bool?
    var cycles: [String]?
    var tips: [String]?
    var basis: String?

    /// Fills in what the lookup knew; anything it didn't know keeps the typical value for the type.
    func applied(to base: Appliance) -> Appliance {
        let types = (base.kind == .washer ? Appliance.washerTypes : Appliance.dryerTypes).map(\.value)
        let t = type.flatMap { types.contains($0) ? $0 : nil } ?? base.type
        var a = Appliance.typical(base.kind, type: t)
        a.brand = base.brand; a.model = base.model
        a.name = name
        a.capacityCuFt = capacityCuFt ?? (capacityKg == nil ? a.capacityCuFt : nil)
        a.capacityKg = capacityKg ?? (capacityCuFt == nil ? a.capacityKg : nil)
        if let d = detergent, ["he", "standard"].contains(d) { a.detergent = d }
        a.maxSpinRpm = maxSpinRpm ?? a.maxSpinRpm
        a.hasHeater = hasHeater ?? a.hasHeater
        a.sensorDry = sensorDry ?? a.sensorDry
        a.steam = steam ?? a.steam
        if let c = cycles, !c.isEmpty { a.cycles = Array(c.prefix(20)) }
        if let tp = tips, !tp.isEmpty { a.tips = Array(tp.prefix(6)) }
        a.source = found == true ? "lookup" : "default"
        a.confidence = confidence
        a.basis = basis
        return a
    }
}
