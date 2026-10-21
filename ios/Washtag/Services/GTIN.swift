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
}
