import Foundation

enum GTIN {
    /// nil when the code isn't a standard length; otherwise whether the check digit matches.
    static func isValid(_ code: String) -> Bool? {
        guard code.allSatisfy(\.isNumber), [8, 12, 13, 14].contains(code.count) else { return nil }
        var digits = code.compactMap { $0.wholeNumberValue }
        let check = digits.removeLast()
        var sum = 0
        for (i, n) in digits.reversed().enumerated() { sum += n * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10 == check
    }

    static func type(_ code: String) -> String {
        [8: "EAN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14"][code.count] ?? "Unknown"
    }

    static func digitsOnly(_ s: String?) -> String? {
        guard let s else { return nil }
        let d = s.filter(\.isNumber)
        return d.isEmpty ? nil : d
    }

    /// Same scoring as the prototype: decoded bars beat printed digits, check digit and
    /// agreement between the two readings move the score up or down.
    static func build(decoded: String?, visual: String?, visualConfidence: Double?, typed: String? = nil) -> UPCInfo {
        let code = digitsOnly(decoded) ?? visual ?? typed ?? ""
        let checksum = isValid(code)
        let agree: Bool? = (decoded != nil && visual != nil) ? (digitsOnly(decoded) == visual) : nil
        var score: Double = typed != nil ? 70 : 30
        if decoded != nil { score = 80 }
        if visual != nil && decoded == nil { score = min(70, visualConfidence ?? 50) }
        if checksum == true { score += 15 } else if checksum == false { score -= 40 }
        if agree == true { score += 10 } else if agree == false { score -= 25 }
        let via = decoded != nil ? "on-device decoder" : typed != nil ? "typed by you" : "read from printed digits"
        return UPCInfo(code: code, type: type(code), checksum: checksum, via: via, visualDigits: visual,
                       agree: agree, readConfidence: max(5, min(99, score)))
    }

    /// Rough GS1 prefix → where the company registered its barcodes (not where the product was made).
    static func region(_ code: String) -> String? {
        let c = code.count == 12 ? "0" + code : code
        guard c.count == 13, let p = Int(c.prefix(3)) else { return nil }
        let ranges: [(ClosedRange<Int>, String)] = [
            (0...19, "USA / Canada"), (30...39, "USA (restricted)"), (60...139, "USA / Canada"), (300...379, "France"), (380...380, "Bulgaria"),
            (400...440, "Germany"), (450...459, "Japan"), (460...469, "Russia"), (471...471, "Taiwan"), (480...480, "Philippines"), (489...489, "Hong Kong"),
            (490...499, "Japan"), (500...509, "United Kingdom"), (520...521, "Greece"), (540...549, "Belgium / Luxembourg"), (560...560, "Portugal"),
            (570...579, "Denmark"), (590...590, "Poland"), (600...601, "South Africa"), (640...649, "Finland"), (690...699, "China"), (700...709, "Norway"),
            (729...729, "Israel"), (730...739, "Sweden"), (750...750, "Mexico"), (760...769, "Switzerland"), (779...779, "Argentina"), (789...790, "Brazil"),
            (800...839, "Italy"), (840...849, "Spain"), (858...858, "Slovakia"), (859...859, "Czechia"), (868...869, "Turkey"), (870...879, "Netherlands"),
            (880...880, "South Korea"), (885...885, "Thailand"), (888...888, "Singapore"), (890...890, "India"), (893...893, "Vietnam"), (899...899, "Indonesia"),
            (900...919, "Austria"), (930...939, "Australia"), (940...949, "New Zealand"), (955...955, "Malaysia"),
        ]
        return ranges.first { $0.0.contains(p) }?.1
    }
}
