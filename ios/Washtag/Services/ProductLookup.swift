import Foundation

/// Free product lookup, run from the phone (no API key needed):
/// 1. UPCitemdb free tier — broad retail database (clothing, household, detergents). 100 lookups a day per network.
/// 2. Open Products Facts, Open Beauty Facts, Open Food Facts — open community databases, used when UPCitemdb has no match.
/// The AI then adds care notes on top of whatever was found.
enum ProductLookup {
    private static let userAgent = "Washtag-iOS/1.0 (personal app)"

    static func lookup(_ code: String, context: String?) async -> ProductInfo {
        var info: ProductInfo?
        var failures: [String] = []

        do { info = try await upcItemDB(code) } catch { failures.append(error.localizedDescription) }
        if info == nil {
            for (host, name) in [("world.openproductsfacts.org", "Open Products Facts"),
                                 ("world.openbeautyfacts.org", "Open Beauty Facts"),
                                 ("world.openfoodfacts.org", "Open Food Facts")] {
                let hit: ProductInfo? = try? await openFacts(code, host: host, sourceName: name)
                if let hit { info = hit; break }
            }
        }

        guard var found = info else {
            let basis = failures.first ?? "No free product database has a record of this code."
            return ProductInfo(found: false, source: nil, confidence: 0, basis: basis, stores: [], gs1Region: GTIN.region(code), careNotes: [])
        }

        // Ask the AI for care notes; the product data is still useful if this fails.
        let enrichment: APIClient.Enrichment? = try? await APIClient.shared.enrich(product: found, context: context)
        if let enrich = enrichment {
            if let c = enrich.category, !c.isEmpty { found.category = c }
            found.careNotes = enrich.careNotes ?? []
            found.detergentUse = enrich.detergentUse
        }
        return found
    }

    // MARK: UPCitemdb (free trial endpoint, no key)

    private struct UPCResponse: Decodable {
        var code: String?
        var message: String?
        var items: [Item]?
        struct Item: Decodable {
            var ean: String?; var upc: String?; var title: String?; var description: String?; var brand: String?
            var category: String?; var color: String?; var size: String?; var images: [String]?; var offers: [Offer]?
        }
        struct Offer: Decodable { var merchant: String?; var price: Double?; var currency: String?; var link: String? }
    }

    private static func upcItemDB(_ code: String) async throws -> ProductInfo? {
        var comps = URLComponents(string: "https://api.upcitemdb.com/prod/trial/lookup")!
        comps.queryItems = [URLQueryItem(name: "upc", value: code)]
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 {
            throw APIClient.APIError(code: "upc_limit", message: "The free barcode database's daily limit (100 lookups) is used up. Try again tomorrow.")
        }
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { return nil }
        let body = try JSONDecoder().decode(UPCResponse.self, from: data)
        guard let item = body.items?.first, let title = item.title, !title.isEmpty else { return nil }

        let exact = [item.ean, item.upc].compactMap { $0 }.contains { normalise($0) == normalise(code) }
        return ProductInfo(
            found: true, source: "upcitemdb", confidence: exact ? 90 : 70,
            basis: exact ? "Exact barcode match in the UPCitemdb database" : "Close match in the UPCitemdb database",
            brand: item.brand.nonEmpty, manufacturer: nil, productName: title, category: item.category.nonEmpty,
            description: item.description.nonEmpty.map { String($0.prefix(1200)) }, material: nil, color: item.color.nonEmpty,
            imageURL: item.images?.first,
            stores: (item.offers ?? []).prefix(5).map { o in
                ProductInfo.Store(name: o.merchant, country: nil,
                                  price: o.price.map { (o.currency == nil || o.currency == "USD" ? "$" : "\(o.currency!) ") + String(format: "%.2f", $0) },
                                  link: o.link)
            },
            gs1Region: GTIN.region(code), careNotes: [], detergentUse: nil)
    }

    // MARK: Open Products / Beauty / Food Facts

    private struct OFFResponse: Decodable {
        var status: Int?
        var product: Product?
        struct Product: Decodable {
            var product_name: String?; var generic_name: String?; var brands: String?; var categories: String?
            var image_url: String?; var image_front_url: String?; var quantity: String?
        }
    }

    private static func openFacts(_ code: String, host: String, sourceName: String) async throws -> ProductInfo? {
        let url = URL(string: "https://\(host)/api/v2/product/\(code).json?fields=product_name,generic_name,brands,categories,image_url,image_front_url,quantity")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let body = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard body.status == 1, let p = body.product, let name = (p.product_name.nonEmpty ?? p.generic_name.nonEmpty) else { return nil }
        let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let category = p.categories?.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) }
        return ProductInfo(
            found: true, source: host, confidence: 85, basis: "Exact barcode match in \(sourceName)",
            brand: brand.nonEmpty, manufacturer: nil, productName: name, category: category.nonEmpty,
            description: [p.generic_name, p.quantity].compactMap { $0.nonEmpty }.joined(separator: " · ").nonEmpty,
            material: nil, color: nil, imageURL: p.image_front_url ?? p.image_url, stores: [],
            gs1Region: GTIN.region(code), careNotes: [], detergentUse: nil)
    }

    private static func normalise(_ s: String) -> String {
        let d = s.filter(\.isNumber)
        return String(d.drop { $0 == "0" })
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
