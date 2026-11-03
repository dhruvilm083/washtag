import Foundation

/// Free product lookup, run from the phone (no API key needed):
/// 1. UPCitemdb free tier — broad retail database (clothing, household, detergents). 100 lookups a day per network.
/// 2. Open Products Facts, Open Beauty Facts, Open Food Facts — open community databases, used when UPCitemdb has no match.
/// 3. A web search (Gemini with Google Search, free tier) for anything the databases don't know,
///    including store item numbers and style numbers that aren't barcodes.
/// The AI then adds care notes on top of whatever was found.
enum ProductLookup {
    private static let userAgent = "Washtag-iOS/1.0 (personal app)"

    /// Looks up a barcode or item number. Results that were found are remembered on the phone,
    /// so scanning the same code again always gives the same answer (and saves the daily limits).
    /// - hint: other words seen on the tag or package, to help a web search.
    static func lookup(_ raw: String, context: String?, hint: String? = nil) async -> ProductInfo {
        let isBarcode = GTIN.isGood(GTIN.canonical(raw))
        let code = isBarcode ? GTIN.canonical(raw) : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = cached(code) { return cached }

        var info: ProductInfo?
        var failures: [String] = []

        if isBarcode {
            do { info = try await upcItemDB(code) } catch { failures.append(error.localizedDescription) }
            if info == nil {
                outer: for (host, name) in [("world.openproductsfacts.org", "Open Products Facts"),
                                            ("world.openbeautyfacts.org", "Open Beauty Facts"),
                                            ("world.openfoodfacts.org", "Open Food Facts")] {
                    for variant in GTIN.variants(code) {
                        let hit: ProductInfo? = try? await openFacts(variant, host: host, sourceName: name)
                        if let hit { info = hit; break outer }
                    }
                }
            }
        }

        // Nothing in the databases (or not a barcode number at all): search the web for it.
        if info == nil {
            do { info = try await webLookup(code, hint: hint ?? context, region: isBarcode ? GTIN.region(code) : nil) }
            catch { failures.append(error.localizedDescription) }
        }

        guard var found = info else {
            let what = isBarcode ? "No free product database or web result has a record of this code." : "A web search didn't find a product for this number."
            let basis = failures.first.map { "\(what) (\($0))" } ?? what
            return ProductInfo(found: false, source: nil, confidence: 0, basis: basis, stores: [],
                               gs1Region: isBarcode ? GTIN.region(code) : nil, careNotes: [])
        }

        // Ask the AI for care notes; the product data is still useful if this fails.
        if found.source != "web" || (found.careNotes ?? []).isEmpty {
            let enrichment: APIClient.Enrichment? = try? await APIClient.shared.enrich(product: found, context: context)
            if let enrich = enrichment {
                if let c = enrich.category, !c.isEmpty { found.category = c }
                if let notes = enrich.careNotes, !notes.isEmpty || found.careNotes == nil { found.careNotes = notes }
                found.detergentUse = enrich.detergentUse
            }
        }
        remember(found, for: code)
        return found
    }

    /// Identifies a product from a photo with no code on it (brand and name the AI read), by web search.
    static func search(name: String, hint: String?) async -> ProductInfo? {
        let key = "name:" + name.lowercased()
        if let cached = cached(key) { return cached }
        guard let found = try? await webLookup(name, hint: hint, region: nil) else { return nil }
        remember(found, for: key)
        return found
    }

    // MARK: Web search (Gemini with Google Search, through the Washtag server)

    private static func webLookup(_ query: String, hint: String?, region: String?) async throws -> ProductInfo? {
        let r = try await APIClient.shared.webSearch(query: query, hint: hint)
        guard r.found == true, r.productName.nonEmpty != nil || r.brand.nonEmpty != nil else { return nil }
        let sources: [ProductInfo.Store] = (r.sources ?? []).compactMap { s in
            guard let url = s.url, !url.isEmpty else { return nil }
            return ProductInfo.Store(name: s.title.nonEmpty ?? "Source", country: nil, price: nil, link: url)
        }
        return ProductInfo(
            found: true, source: "web", confidence: min(r.confidence ?? 50, 80),
            basis: r.basis.nonEmpty ?? "Found by a web search",
            brand: r.brand.nonEmpty, manufacturer: nil, productName: r.productName.nonEmpty, category: r.category.nonEmpty,
            description: r.description.nonEmpty, material: r.material.nonEmpty, color: nil, imageURL: nil,
            stores: sources, gs1Region: region, careNotes: r.careNotes ?? [], detergentUse: nil)
    }

    // MARK: Remembered results

    private static let cacheKey = "wt.productCache.v1"

    private static func cached(_ code: String) -> ProductInfo? {
        guard let dict = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Data],
              let data = dict[code] else { return nil }
        return try? JSONDecoder().decode(ProductInfo.self, from: data)
    }

    private static func remember(_ info: ProductInfo, for code: String) {
        guard info.found, let data = try? JSONEncoder().encode(info) else { return }
        var dict = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Data]) ?? [:]
        if dict.count >= 300 { dict.removeAll() }
        dict[code] = data
        UserDefaults.standard.set(dict, forKey: cacheKey)
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
