import UIKit
import Vision

/// On-device barcode decoding for a still photo (Apple Vision; no network).
enum BarcodeReader {
    static func decode(_ image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8, .upce, .itf14]
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return nil }
            return (request.results ?? [])
                .sorted { $0.confidence > $1.confidence }
                .compactMap(\.payloadStringValue)
                .first { $0.allSatisfy(\.isNumber) }
        }.value
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
