import SwiftUI
import Observation

/// Scan flow logic. One camera: the photo or code decides whether it's a care label,
/// a barcode, or a product, so there are no modes to pick.
@MainActor
@Observable
final class ScanModel {
    var image: UIImage?
    var status: String?
    var statusIsError = false
    var isBusy = false
    var current: ScanRecord?

    private var task: Task<Void, Never>?
    private let api = APIClient.shared

    func stop() { task?.cancel() }

    /// Something came back from the smart camera.
    func handle(_ result: SmartScanResult) {
        switch result {
        case .barcode(let code): lookUp(code: code, via: .bars, thumbnail: nil)
        case .number(let code): lookUp(code: code, via: .printed, thumbnail: nil)
        case .photo(let img): analyze(img)
        }
    }

    /// A photo from the camera or library: work out what it shows and read it.
    func analyze(_ img: UIImage) {
        image = img
        run { [self] in try await runPhoto(img) }
    }

    func retry() {
        guard let image else { return }
        analyze(image)
    }

    enum Via { case bars, printed, typed }

    func lookUp(code: String, via: Via, thumbnail: Data?) {
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 5 else { show("Type the barcode or item number first (at least 5 characters).", error: true); return }
        if via != .typed { image = nil }
        run { [self] in
            var rec = ScanRecord(mode: .upc)
            rec.thumbnail = thumbnail
            rec.upc = upcInfo(raw, via: via)
            rec.name = "Item \(rec.upc!.code)"
            current = rec
            show(GTIN.isGood(rec.upc!.code) ? "Looking up the product…" : "Searching the web for this number…")
            rec.product = await ProductLookup.lookup(rec.upc!.code, context: nil)
            rec.name = rec.product?.productName ?? rec.product?.brand ?? rec.name
            current = rec
        }
    }

    // MARK: photo

    private func runPhoto(_ image: UIImage) async throws {
        show("Reading the photo… this usually takes 5–20 seconds.")
        async let localRead = BarcodeReader.read(image)
        var care: CareResult?
        var aiError: Error?
        do { care = try await api.readLabel(image) }
        catch is CancellationError { throw CancellationError() }
        catch { aiError = error }
        let local = await localRead
        try Task.checkCancellation()

        let upc = chooseCode(local: local, care: care)
        let itemNumber = upc == nil ? chooseItemNumber(local: local, care: care, aiFailed: care == nil) : nil
        let isLabel = care?.symbolsFound == true
        let hint = productHint(care)

        var rec = ScanRecord(mode: isLabel ? .label : .upc)
        rec.thumbnail = image.thumbnailData()

        if isLabel, let care {
            rec.care = care
            rec.name = care.suggestedName ?? care.product?.name ?? "Unnamed item"
            current = rec
            guard upc != nil || itemNumber != nil else { return }
            rec.upc = upc ?? upcInfo(itemNumber!, via: .printed)
            current = rec
            show("Found a code on the label — looking up the product…")
            let context = [care.product?.type, care.labelText?.fibres, care.product?.brand].compactMap { $0 }.joined(separator: " ")
            rec.product = await ProductLookup.lookup(rec.upc!.code, context: context, hint: hint)
            current = rec
            return
        }

        if let found = upc ?? itemNumber.map({ upcInfo($0, via: .printed) }) {
            rec.upc = found
            rec.name = care?.suggestedName ?? "Item \(found.code)"
            current = rec
            show(GTIN.isGood(found.code) ? "Found a barcode — looking up the product…" : "Found item number \(found.code) — searching the web…")
            rec.product = await ProductLookup.lookup(found.code, context: nil, hint: hint)
            rec.name = rec.product?.productName ?? rec.product?.brand ?? rec.name
            current = rec
            return
        }

        // A product photo with no readable code: search for what the AI read on it.
        if let care, let name = productName(care) {
            rec.name = care.suggestedName ?? name
            current = rec
            show("Looking up \(name)…")
            let hit = await ProductLookup.search(name: name, hint: hint)
            rec.product = hit ?? ProductInfo(
                found: true, source: "photo", confidence: min(care.overallConfidence ?? 50, 60),
                basis: "Read from the packaging in your photo; no barcode was visible.",
                brand: care.product?.brand, productName: care.product?.name, category: care.product?.type,
                stores: [], careNotes: [])
            current = rec
            return
        }

        if let aiError { throw aiError }
        throw APIClient.APIError(code: "nothing_found", message: "Couldn't find a care label, barcode or product in that photo. Get closer with good light and try again, or type the number.")
    }

    /// Picks the barcode number, preferring bars decoded on the phone, then printed digits that two readers agree on.
    private func chooseCode(local: StillRead, care: CareResult?) -> UPCInfo? {
        let aiDigits = GTIN.digitsOnly(care?.barcode?.digits).map { GTIN.canonical($0) }
        var aiCodes: [String] = []
        if let d = aiDigits, GTIN.isGood(d) { aiCodes.append(d) }
        for n in care?.numbers ?? [] {
            guard let t = GTIN.digitsOnly(n.text) else { continue }
            let c = GTIN.canonical(t)
            if GTIN.isGood(c) && !aiCodes.contains(c) { aiCodes.append(c) }
        }

        if let bars = local.barcode {
            let printed = (local.printedCodes + aiCodes).contains(bars) ? bars : (aiCodes.first ?? local.printedCodes.first)
            return GTIN.build(decoded: bars, visual: printed, visualConfidence: care?.barcode?.confidence)
        }
        // No bars decoded: printed digits, more trusted when the phone's text reader and the AI agree.
        if let both = local.printedCodes.first(where: { aiCodes.contains($0) }) {
            return GTIN.build(decoded: nil, visual: both, visualConfidence: 90)
        }
        if let one = local.printedCodes.first {
            return GTIN.build(decoded: nil, visual: one, visualConfidence: 70)
        }
        if let one = aiCodes.first {
            return GTIN.build(decoded: nil, visual: one, visualConfidence: min(care?.barcode?.confidence ?? 60, 65))
        }
        return nil
    }

    /// A store item, style or model number to search for when there's no barcode number.
    private func chooseItemNumber(local: StillRead, care: CareResult?, aiFailed: Bool) -> String? {
        let useful = ["sku", "style", "model", "upc", "ean", "other"]
        let fromAI = (care?.numbers ?? [])
            .filter { useful.contains($0.kind ?? "other") && ($0.confidence ?? 0) >= 60 }
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.filter(\.isNumber).count >= 5 }
        if let fromAI { return fromAI }
        if let bars = local.itemBarcode { return bars }
        return aiFailed ? local.itemNumbers.first : nil
    }

    private func productName(_ care: CareResult) -> String? {
        let parts = [care.product?.brand, care.product?.name].compactMap { value -> String? in
            guard let text = value, !text.isEmpty, text.lowercased() != "unknown" else { return nil }
            return text
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func productHint(_ care: CareResult?) -> String? {
        guard let care else { return nil }
        let parts = [care.product?.brand, care.product?.name, care.product?.type, care.labelText?.fibres]
            .compactMap { $0 }.filter { !$0.isEmpty && $0.lowercased() != "unknown" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func upcInfo(_ raw: String, via: Via) -> UPCInfo {
        let canonical = GTIN.canonical(raw)
        if GTIN.isGood(canonical) {
            switch via {
            case .bars: return GTIN.build(decoded: canonical, visual: nil, visualConfidence: nil)
            case .printed: return GTIN.build(decoded: nil, visual: canonical, visualConfidence: 75)
            case .typed: return GTIN.build(decoded: nil, visual: nil, visualConfidence: nil, typed: canonical)
            }
        }
        // Not a standard barcode number: an item, style or SKU number to search for.
        let how = via == .typed ? "typed by you" : via == .bars ? "on-device decoder" : "read from printed digits"
        let digitsOnly = raw.allSatisfy(\.isNumber)
        let kind = digitsOnly && [8, 12, 13, 14].contains(raw.count) ? GTIN.type(raw) : "Item number"
        return UPCInfo(code: raw, type: kind, checksum: digitsOnly ? GTIN.isValid(raw) : nil, via: how,
                       visualDigits: nil, agree: nil, readConfidence: via == .typed ? 70 : 55)
    }

    // MARK: plumbing

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        isBusy = true
        current = nil
        task = Task {
            do { try await work(); status = nil }
            catch is CancellationError { show("Stopped.") }
            catch { show(error.localizedDescription, error: true) }
            isBusy = false
        }
    }

    private func show(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }
}
