import SwiftUI
import Observation

/// Scan flow logic, ported from the prototype's runLabel / runUpcFromPhoto / runUpc.
@MainActor
@Observable
final class ScanModel {
    var mode: ScanMode = .label
    var image: UIImage?
    var status: String?
    var statusIsError = false
    var isBusy = false
    var current: ScanRecord?

    private var task: Task<Void, Never>?
    private let api = APIClient.shared

    func setImage(_ img: UIImage?) {
        image = img
        current = nil
        status = nil
    }

    func stop() { task?.cancel() }

    func scanPhoto() {
        guard let image else { return }
        run { [self] in
            if mode == .label { try await runLabel(image) } else { try await runUPCPhoto(image) }
        }
    }

    func lookUp(code: String, via: String) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { show("Type the digits under the barcode first.", error: true); return }
        run { [self] in
            var rec = ScanRecord(mode: .upc)
            rec.upc = via == "typed by you"
                ? GTIN.build(decoded: nil, visual: nil, visualConfidence: nil, typed: digits)
                : GTIN.build(decoded: digits, visual: nil, visualConfidence: nil)
            rec.name = "Item \(digits)"
            current = rec
            show("Looking up the product…")
            rec.product = await lookup(rec.upc!.code, context: nil)
            rec.name = rec.product?.productName ?? rec.product?.brand ?? rec.name
            current = rec
        }
    }

    private func runLabel(_ image: UIImage) async throws {
        show("Reading the label… this usually takes 5–20 seconds.")
        async let decoded = BarcodeReader.decode(image)
        let care = try await api.readLabel(image)
        let bars = await decoded
        var rec = ScanRecord(mode: .label)
        rec.thumbnail = image.thumbnailData()
        rec.care = care
        rec.name = care.suggestedName ?? care.product?.name ?? "Unnamed item"
        let visual = care.barcode?.present == true ? GTIN.digitsOnly(care.barcode?.digits) : nil
        current = rec
        if bars != nil || visual != nil {
            rec.upc = GTIN.build(decoded: bars, visual: visual, visualConfidence: care.barcode?.confidence)
            current = rec
            show("Found a barcode beside the symbols — looking up the product…")
            let context = [care.product?.type, care.labelText?.fibres, care.product?.brand].compactMap { $0 }.joined(separator: " ")
            rec.product = await lookup(rec.upc!.code, context: context)
            current = rec
        }
    }

    private func runUPCPhoto(_ image: UIImage) async throws {
        show("Looking for a barcode in the photo…")
        let decoded = await BarcodeReader.decode(image)
        show("Reading the printed digits to double-check…")
        let printed: DigitsResult? = try? await api.readDigits(image)
        let visual = GTIN.digitsOnly(printed?.digits)
        let visualConf = printed?.confidence
        try Task.checkCancellation()
        guard decoded != nil || visual != nil else {
            throw APIClient.APIError(code: "no_barcode", message: "No barcode found in that photo. Get closer, keep it straight on with the numbers visible, or type the numbers.")
        }
        var rec = ScanRecord(mode: .upc)
        rec.thumbnail = image.thumbnailData()
        rec.upc = GTIN.build(decoded: decoded, visual: visual, visualConfidence: visualConf)
        current = rec
        show("Looking up the product…")
        rec.product = await lookup(rec.upc!.code, context: nil)
        rec.name = rec.product?.productName ?? rec.product?.brand ?? "Item \(rec.upc!.code)"
        current = rec
    }

    private func lookup(_ code: String, context: String?) async -> ProductInfo {
        do { return try await api.product(code: code, context: context) }
        catch { return ProductInfo(found: false, confidence: 0, basis: "Lookup failed: \(error.localizedDescription)") }
    }

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
