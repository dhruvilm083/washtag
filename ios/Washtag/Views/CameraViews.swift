import SwiftUI
import UIKit
import Vision
import VisionKit

/// System camera, used when the live scanner isn't available on this iPhone.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - One smart camera

/// What the smart camera hands back.
enum SmartScanResult {
    /// A barcode read steadily from the bars, with a valid check digit.
    case barcode(String)
    /// A number read from print: barcode digits or an item / style number.
    case number(String)
    /// The shutter was pressed: a care label, tag or product photo for the full read.
    case photo(UIImage)
}

/// Counts what the live camera sees, so only steady, valid reads are used.
/// One glimpse of a barcode is often misread; the same code several times with a good check digit is not.
final class SmartScanTracker: ObservableObject {
    @Published var chips: [String] = []
    @Published var capturing = false

    weak var scanner: DataScannerViewController?
    var onResult: (SmartScanResult) -> Void = { _ in }

    private var barcodeVotes: [String: Int] = [:]
    private var printedVotes: [String: Int] = [:]
    private var itemVotes: [String: Int] = [:]
    private var finished = false

    /// Reads of the same barcode needed before it's accepted.
    private let barcodeNeeded = 3
    /// Printed barcode digits (with a valid check digit) needed before they're accepted on their own.
    private let printedNeeded = 5
    /// Sightings of any number before it's offered as a button.
    private let chipNeeded = 3

    func seen(_ items: [RecognizedItem]) {
        guard !finished else { return }
        for item in items {
            switch item {
            case .barcode(let b):
                guard let payload = b.payloadStringValue else { continue }
                if let code = BarcodeReader.retailCode(payload, symbology: b.observation.symbology) {
                    barcodeVotes[code, default: 0] += 1
                } else if !BarcodeReader.isRetail(b.observation.symbology) {
                    let clean = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.count >= 5 && clean.count <= 24 { itemVotes[clean, default: 0] += 1 }
                }
            case .text(let t):
                for c in GTIN.codes(inText: t.transcript) { printedVotes[c, default: 0] += 1 }
                for n in GTIN.itemNumbers(inText: t.transcript) { itemVotes[n, default: 0] += 1 }
            @unknown default:
                continue
            }
        }
        decide()
    }

    private func decide() {
        if let best = leader(barcodeVotes, needed: barcodeNeeded) {
            finish(.barcode(best))
            return
        }
        if barcodeVotes.isEmpty, let best = leader(printedVotes, needed: printedNeeded) {
            finish(.number(best))
            return
        }
        var next: [String] = []
        let printed = printedVotes.filter { $0.value >= chipNeeded }.sorted { $0.value > $1.value }.map(\.key)
        let items = itemVotes.filter { $0.value >= chipNeeded }.sorted { $0.value > $1.value }.map(\.key)
        for c in printed + items where !next.contains(c) && next.count < 3 { next.append(c) }
        if next != chips { chips = next }
    }

    /// The code with the most votes, if it has enough and is clearly ahead of any other code.
    private func leader(_ votes: [String: Int], needed: Int) -> String? {
        let sorted = votes.sorted { $0.value > $1.value }
        guard let first = sorted.first, first.value >= needed else { return nil }
        if sorted.count > 1 && first.value - sorted[1].value < 2 { return nil }
        return first.key
    }

    func pick(_ number: String) { finish(.number(number)) }

    func capture() {
        guard !capturing, !finished, let scanner else { return }
        capturing = true
        Task { @MainActor in
            do {
                let photo = try await scanner.capturePhoto()
                self.finish(.photo(photo))
            } catch {
                self.capturing = false
            }
        }
    }

    private func finish(_ result: SmartScanResult) {
        guard !finished else { return }
        finished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onResult(result)
    }
}

/// Full-screen camera that reads barcodes and numbers live, and takes a photo for labels and products.
struct SmartCameraView: View {
    var onResult: (SmartScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = SmartScanTracker()

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SmartScannerRepresentable(tracker: tracker).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    Text("Point at a barcode, care label or product. Barcodes scan by themselves. For labels and products, tap the shutter.")
                        .font(.subheadline).foregroundStyle(.white)
                        .padding(10).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Color.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Close camera")
                }
                Spacer()
                ForEach(tracker.chips, id: \.self) { code in
                    Button { tracker.pick(code) } label: {
                        Label(chipTitle(code), systemImage: "magnifyingglass")
                            .font(.subheadline.bold()).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.white, in: Capsule())
                    }
                }
                Button { tracker.capture() } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(.white).frame(width: 62, height: 62)
                        if tracker.capturing { ProgressView() }
                    }
                }
                .accessibilityLabel("Take photo of label or product")
                .padding(.bottom, 8)
            }
            .padding(16)
        }
        .onAppear {
            tracker.onResult = { result in
                onResult(result)
                dismiss()
            }
        }
    }

    private func chipTitle(_ code: String) -> String {
        GTIN.isGood(code) ? "Look up \(code)" : "Search item number \(code)"
    }
}

private struct SmartScannerRepresentable: UIViewControllerRepresentable {
    var tracker: SmartScanTracker

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: [.ean13, .ean8, .upce, .itf14, .code128, .code39]),
            .text(),
        ]
        let vc = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .accurate, recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        tracker.scanner = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(tracker: tracker) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let tracker: SmartScanTracker
        init(tracker: SmartScanTracker) { self.tracker = tracker }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            tracker.seen(addedItems)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            tracker.seen(updatedItems)
        }
    }
}
