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

    /// True only for a standard-length code whose check digit matches.
    static func isGood(_ code: String) -> Bool { isValid(code) == true }

    /// One spelling per product, so the same barcode always looks up the same way:
    /// UPC-E is expanded to UPC-A, and EAN-13 / GTIN-14 with leading zeros become the 12-digit UPC-A.
    static func canonical(_ raw: String, isUPCE: Bool = false) -> String {
        var d = raw.filter(\.isNumber)
        if isUPCE || (d.count == 8 && d.first == "0" && isValid(d) != true && expandUPCE(d).map(isGood) == true) {
            if let full = expandUPCE(d) { d = full }
        }
        if d.count == 14 && d.hasPrefix("00") { d = String(d.dropFirst(2)) }
        if d.count == 13 && d.hasPrefix("0") { d = String(d.dropFirst()) }
        return d
    }

    /// Other spellings of the same code that a database might store it under.
    static func variants(_ code: String) -> [String] {
        var out = [code]
        if code.count == 12 { out.append("0" + code) }
        return out
    }

    /// Expands an 8-digit UPC-E (number system 0 or 1, six digits, check digit) to its 12-digit UPC-A.
    static func expandUPCE(_ code: String) -> String? {
        var d = code.filter(\.isNumber)
        if d.count == 6 { d = "0" + d + "?" }
        if d.count == 7 { d = d + "?" }
        guard d.count == 8 else { return nil }
        let chars = Array(d)
        let ns = chars[0]
        guard ns == "0" || ns == "1" else { return nil }
        let m = chars[1...6].map { String($0) }
        let last = m[5]
        var body: String
        switch last {
        case "0", "1", "2": body = m[0] + m[1] + last + "0000" + m[2] + m[3] + m[4]
        case "3": body = m[0] + m[1] + m[2] + "00000" + m[3] + m[4]
        case "4": body = m[0] + m[1] + m[2] + m[3] + "00000" + m[4]
        default: body = m[0] + m[1] + m[2] + m[3] + m[4] + "0000" + last
        }
        body = String(ns) + body
        let check = String(chars[7])
        let computed = checkDigit(body)
        if check == "?" { return body + computed }
        return check == computed ? body + check : nil
    }

    /// The GS1 check digit for the digits given (without their check digit).
    static func checkDigit(_ body: String) -> String {
        let digits = body.compactMap { $0.wholeNumberValue }
        var sum = 0
        for (i, n) in digits.reversed().enumerated() { sum += n * (i % 2 == 0 ? 3 : 1) }
        return String((10 - sum % 10) % 10)
    }

    /// Finds barcode numbers in text read off a photo, e.g. "0 12345 67890 5" or "4006381333931".
    /// Only standard lengths with a matching check digit are returned.
    static func codes(inText text: String) -> [String] {
        var out: [String] = []
        for run in digitRuns(text) where [8, 12, 13, 14].contains(run.count) && isGood(run) {
            let c = canonical(run)
            if !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Longer number strings that could be an item, style or SKU number (6 to 14 digits),
    /// for when there's no proper barcode number.
    static func itemNumbers(inText text: String) -> [String] {
        var out: [String] = []
        for run in digitRuns(text) where run.count >= 6 && run.count <= 14 && !isGood(run) {
            if !out.contains(run) { out.append(run) }
        }
        return out
    }

    /// Digit runs, allowing single spaces or hyphens between groups (how barcodes print their numbers).
    private static func digitRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        var pendingGap = false
        for ch in text {
            if ch.isNumber && ch.isASCII {
                current.append(ch)
                pendingGap = false
            } else if (ch == " " || ch == "-") && !current.isEmpty && !pendingGap {
                pendingGap = true
            } else {
                if !current.isEmpty { runs.append(current) }
                current = ""
                pendingGap = false
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
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
