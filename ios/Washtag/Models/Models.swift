import Foundation

// MARK: - Care label (shape matches LABEL_PROMPT in the backend)

struct CareResult: Codable, Hashable {
    var symbolsFound: Bool?
    var overallConfidence: Double?
    var imageQuality: String?
    var qualityNotes: String?
    var symbols: [CareSymbol]?
    var sections: CareSections?
    var structured: StructuredCare?
    var labelText: LabelText?
    var barcode: LabelBarcode?
    var product: LabelProduct?
    var suggestedName: String?
    var recheck: [String]?

    var safeSymbols: [CareSymbol] { Array((symbols ?? []).prefix(20)) }
    var safeSections: CareSections { sections ?? CareSections() }
}

struct CareSymbol: Codable, Hashable, Identifiable {
    var id: String { "\(category ?? "")-\(code ?? "")-\(meaning ?? "")" }
    var category: String?
    var code: String?
    var prohibited: Bool?
    var tempC: Double?
    var meaning: String?
    var confidence: Double?
}

struct CareSections: Codable, Hashable {
    var wash: [String]? = []
    var dry: [String]? = []
    var care: [String]? = []
    var doNot: [String]? = []
}

struct StructuredCare: Codable, Hashable {
    var maxWashTempC: Double?
    var washCycle: String?
    var bleach: String?
    var tumble: String?
    var naturalDry: String?
    var iron: String?
    var dryClean: String?
}

struct LabelText: Codable, Hashable {
    var fibres: String?
    var other: String?
    var language: String?
}

struct LabelBarcode: Codable, Hashable {
    var present: Bool?
    var digits: String?
    var confidence: Double?
}

struct LabelProduct: Codable, Hashable {
    var brand: String?
    var name: String?
    var type: String?
}

struct DigitsResult: Codable { var digits: String?; var confidence: Double?; var note: String? }

// MARK: - Barcode + product

struct UPCInfo: Codable, Hashable {
    var code: String
    var type: String
    var checksum: Bool?
    var via: String
    var visualDigits: String?
    var agree: Bool?
    var readConfidence: Double
}

struct ProductInfo: Codable, Hashable {
    var found: Bool
    var source: String?
    var confidence: Double?
    var basis: String?
    var brand: String?
    var manufacturer: String?
    var productName: String?
    var category: String?
    var description: String?
    var material: String?
    var color: String?
    var imageURL: String?
    var stores: [Store]?
    var gs1Region: String?
    var careNotes: [String]?
    var detergentUse: DetergentUse?

    struct Store: Codable, Hashable { var name: String?; var country: String?; var price: String?; var link: String? }
    struct DetergentUse: Codable, Hashable { var isLaundryProduct: Bool?; var typicalDoseNote: String? }
}

// MARK: - Suggestions

struct Suggestions: Codable, Hashable {
    var suggestions: [Item]?
    var avoid: [Avoid]?
    struct Item: Codable, Hashable { var type: String?; var why: String?; var examples: [String]?; var howMuch: String? }
    struct Avoid: Codable, Hashable { var what: String?; var why: String? }
}

// MARK: - Saved index + household

enum ScanMode: String, Codable { case label, upc }

struct ScanRecord: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var createdAt = Date()
    var mode: ScanMode
    var name = ""
    var people: [String] = []
    var notes = ""
    var thumbnail: Data?
    var care: CareResult?
    var upc: UPCInfo?
    var product: ProductInfo?
    var suggestions: Suggestions?
}

struct Person: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var colorIndex: Int
}

enum Units: String, Codable, CaseIterable { case metric, us }

struct LoadSettings: Codable, Hashable {
    var ids: [String] = []
    var size = "medium"     // small | medium | large | xl
    var soil = "normal"     // light | normal | heavy
    var water = "unknown"   // soft | medium | hard | unknown
    var machine = "he"      // he | standard
    var form = "liquid"     // liquid | powder | pod
    var needs: [String] = []
}

let NEEDS: [(key: String, label: String)] = [
    ("sensitive", "Sensitive skin"), ("fragrance", "Fragrance-free"), ("baby", "Baby clothes"), ("active", "Activewear odour"),
    ("stains", "Tough stains"), ("darks", "Keep darks dark"), ("whites", "Brighten whites"), ("wool", "Wool / delicates"),
    ("pets", "Pet hair"), ("eco", "Eco / cold wash"), ("towels", "Towels & absorbency"),
]

func needLabel(_ key: String) -> String { NEEDS.first { $0.key == key }?.label ?? key }
