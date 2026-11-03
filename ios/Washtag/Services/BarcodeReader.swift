import UIKit
import Vision

/// What the phone itself can read from a still photo (Apple Vision; no network).
struct StillRead {
    /// A barcode decoded from the bars, with a valid check digit, in its canonical spelling.
    var barcode: String?
    /// Barcode numbers found in the printed text (valid check digit only).
    var printedCodes: [String] = []
    /// Other long numbers printed on the tag or package (item, style or SKU numbers).
    var itemNumbers: [String] = []
    /// A non-retail barcode (e.g. Code 128 on a clothing tag), often a store item number.
    var itemBarcode: String?
}

/// On-device barcode and number reading for a still photo.
enum BarcodeReader {
    static func read(_ image: UIImage) async -> StillRead {
        guard let cg = image.cgImage else { return StillRead() }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> StillRead in
            var out = StillRead()

            let bars = VNDetectBarcodesRequest()
            bars.symbologies = [.ean13, .ean8, .upce, .itf14, .code128, .code39]
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            try? handler.perform([bars, text])

            // Vote across every detection of the same code; ignore anything with a bad check digit.
            var votes: [String: Float] = [:]
            var itemVotes: [String: Float] = [:]
            for obs in bars.results ?? [] {
                guard let payload = obs.payloadStringValue else { continue }
                if let code = retailCode(payload, symbology: obs.symbology) {
                    votes[code, default: 0] += max(obs.confidence, 0.1)
                } else if !isRetail(obs.symbology) {
                    let clean = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.count >= 5 && clean.count <= 24 { itemVotes[clean, default: 0] += max(obs.confidence, 0.1) }
                }
            }
            out.barcode = votes.max { $0.value < $1.value }?.key
            out.itemBarcode = itemVotes.max { $0.value < $1.value }?.key

            for obs in text.results ?? [] {
                guard let line = obs.topCandidates(1).first?.string else { continue }
                for c in GTIN.codes(inText: line) where !out.printedCodes.contains(c) { out.printedCodes.append(c) }
                for n in GTIN.itemNumbers(inText: line) where !out.itemNumbers.contains(n) { out.itemNumbers.append(n) }
            }
            return out
        }.value
    }

    static func isRetail(_ symbology: VNBarcodeSymbology) -> Bool {
        symbology == .ean13 || symbology == .ean8 || symbology == .upce || symbology == .itf14
    }

    /// A retail barcode payload in canonical form, or nil if it isn't one or its check digit is wrong.
    static func retailCode(_ payload: String, symbology: VNBarcodeSymbology) -> String? {
        guard isRetail(symbology), payload.allSatisfy(\.isNumber) else { return nil }
        let code = GTIN.canonical(payload, isUPCE: symbology == .upce)
        return GTIN.isGood(code) ? code : nil
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
