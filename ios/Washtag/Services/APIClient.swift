import Foundation
import UIKit

/// Talks to the Washtag Worker. The Worker holds the Gemini API key.
struct APIClient {
    static let shared = APIClient()

    struct APIError: LocalizedError {
        var code: String
        var message: String
        var errorDescription: String? { message }
    }

    private let base: URL? = (Bundle.main.object(forInfoDictionaryKey: "WashtagAPIBase") as? String).flatMap(URL.init(string:))
    private let token = Bundle.main.object(forInfoDictionaryKey: "WashtagAppToken") as? String ?? ""
    private let installID: String = {
        if let id = UserDefaults.standard.string(forKey: "wt.install") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "wt.install")
        return id
    }()

    func readLabel(_ image: UIImage) async throws -> CareResult {
        try await post("v1/label", body: ["image": try jpegBase64(image)])
    }

    func readDigits(_ image: UIImage) async throws -> DigitsResult {
        try await post("v1/digits", body: ["image": try jpegBase64(image)])
    }

    struct Enrichment: Decodable { var category: String?; var careNotes: [String]?; var detergentUse: ProductInfo.DetergentUse? }

    /// Adds care notes to a product found in a barcode database.
    func enrich(product: ProductInfo, context: String?) async throws -> Enrichment {
        struct Record: Encodable { var title, brand, category, description, color: String? }
        struct Body: Encodable { var product: Record; var context: String? }
        let record = Record(title: product.productName, brand: product.brand, category: product.category,
                            description: product.description, color: product.color)
        return try await send(path: "v1/enrich", method: "POST", query: [],
                              body: try JSONEncoder().encode(Body(product: record, context: context.map { String($0.prefix(300)) })))
    }

    func suggest(structured: StructuredCare?, needs: [String], fibres: String?, type: String?) async throws -> Suggestions {
        struct Body: Encodable { var structured: StructuredCare?; var needs: [String]; var fibres: String?; var type: String? }
        return try await send(path: "v1/suggest", method: "POST", query: [],
                              body: try JSONEncoder().encode(Body(structured: structured, needs: needs, fibres: fibres, type: type)))
    }

    // MARK: plumbing

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        try await send(path: path, method: "POST", query: [], body: try JSONEncoder().encode(body))
    }

    private func send<T: Decodable>(path: String, method: String, query: [URLQueryItem], body: Data?) async throws -> T {
        guard let base, var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError(code: "config", message: "The app isn't connected to its server yet (WASHTAG_API_BASE is empty).")
        }
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 90)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(token, forHTTPHeaderField: "x-washtag-token")
        req.setValue(installID, forHTTPHeaderField: "x-washtag-install")
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch { throw APIError(code: "network", message: "Couldn't reach Washtag. Check your connection and try again.") }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Wrapper: Decodable { struct E: Decodable { var code: String; var message: String }; var error: E }
            if let w = try? JSONDecoder().decode(Wrapper.self, from: data) { throw APIError(code: w.error.code, message: w.error.message) }
            throw APIError(code: "http_\(status)", message: "Something went wrong (\(status)). Try again.")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(code: "invalid_json", message: "The answer came back garbled. Try again.") }
    }

    private func jpegBase64(_ image: UIImage) throws -> String {
        guard let data = image.resized(maxSide: 1800).jpegData(compressionQuality: 0.85) else {
            throw APIError(code: "image", message: "That photo couldn't be prepared. Try another.")
        }
        return data.base64EncodedString()
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    func thumbnailData() -> Data? { resized(maxSide: 220).jpegData(compressionQuality: 0.7) }
}
