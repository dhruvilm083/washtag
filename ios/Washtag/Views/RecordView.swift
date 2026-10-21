import SwiftUI

/// Everything about one scanned item: care tag, confidence, product, suggestions and saving.
/// Used on the Scan tab and in the saved-item detail screen.
struct RecordView: View {
    @Environment(AppStore.self) private var store
    @State private var rec: ScanRecord
    @State private var needs: [String] = []
    @State private var suggesting = false
    @State private var suggestError: String?
    @State private var savedToast = false
    var onLoad: (() -> Void)?

    init(record: ScanRecord, onLoad: (() -> Void)? = nil) {
        _rec = State(initialValue: record)
        self.onLoad = onLoad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let care = rec.care { CareTagView(name: rec.name, care: care, units: store.units) }
            ConfidencePanel(rec: rec)
            if rec.upc != nil { ProductPanel(rec: rec) }
            if rec.care != nil { suggestionsPanel }
            savePanel
        }
        .overlay(alignment: .bottom) {
            if savedToast {
                Text("Saved to index").bold().padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(Theme.bg).background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }
        }
    }

    // MARK: suggestions

    private var suggestionsPanel: some View {
        Panel(title: "Product suggestions") {
            Text("Based on this label. Pick any needs that apply.").font(.caption).foregroundStyle(Theme.ink2)
            FlowLayout {
                ForEach(NEEDS, id: \.key) { n in
                    Chip(label: n.label, selected: needs.contains(n.key)) {
                        if needs.contains(n.key) { needs.removeAll { $0 == n.key } } else { needs.append(n.key) }
                    }
                }
            }
            Button {
                Task { await suggest() }
            } label: {
                if suggesting { ProgressView() } else { Text(rec.suggestions == nil ? "Get suggestions" : "Refresh suggestions") }
            }
            .buttonStyle(.bordered).disabled(suggesting)
            if let suggestError { Text(suggestError).font(.footnote).foregroundStyle(Theme.ink2) }
            if let s = rec.suggestions { SuggestionsList(s: s) }
        }
    }

    private func suggest() async {
        suggesting = true; suggestError = nil
        defer { suggesting = false }
        do {
            rec.suggestions = try await APIClient.shared.suggest(structured: rec.care?.structured, needs: needs.map(needLabel),
                                                                 fibres: rec.care?.labelText?.fibres, type: rec.care?.product?.type)
            if store.isSaved(rec.id) { store.upsert(rec) }
        } catch { suggestError = error.localizedDescription }
    }

    // MARK: save

    private var savePanel: some View {
        Panel(title: store.isSaved(rec.id) ? "Saved to your index" : "Save to your index") {
            TextField("Name", text: $rec.name).textFieldStyle(.roundedBorder)
            Text("Belongs to").font(.subheadline.bold())
            if store.people.isEmpty {
                Text("Add people in Household to label items.").font(.caption).foregroundStyle(Theme.ink2)
            } else {
                FlowLayout {
                    ForEach(store.people) { p in
                        Chip(label: p.name, selected: rec.people.contains(p.id), dot: PersonColors.color(p.colorIndex)) {
                            if rec.people.contains(p.id) { rec.people.removeAll { $0 == p.id } } else { rec.people.append(p.id) }
                        }
                    }
                }
            }
            TextField("Notes, e.g. shrinks if too warm", text: $rec.notes, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            HStack {
                Button(store.isSaved(rec.id) ? "Save changes" : "Save to index") {
                    store.upsert(rec)
                    withAnimation { savedToast = true }
                    Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation { savedToast = false } }
                }
                .buttonStyle(.borderedProminent)
                if rec.care != nil, let onLoad {
                    Button("Plan a load with this") {
                        store.upsert(rec)
                        if !store.load.ids.contains(rec.id) { store.load.ids.append(rec.id) }
                        onLoad()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Care tag

struct CareTagView: View {
    var name: String
    var care: CareResult
    var units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stitch.padding(.bottom, 14)
            if care.symbolsFound == false && care.safeSymbols.isEmpty {
                Text("No care symbols found").font(.title3.bold())
                Text(care.qualityNotes ?? "Try again with the label flat, well lit and filling most of the photo.").foregroundStyle(Theme.ink2)
            } else {
                Text(name.isEmpty ? "Care label" : name).font(.title3.weight(.heavy))
                let sub = [care.labelText?.fibres, care.product?.type].compactMap { $0 }.joined(separator: " — ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.ink2) }
                section("Wash", care.safeSections.wash ?? [], Theme.tub, Theme.tubSoft, CareSymbolView(category: "wash", tempLabel: "~"), first: true)
                section("Dry", care.safeSections.dry ?? [], Theme.dry, Theme.drySoft, CareSymbolView(category: "dry", code: "tumble"))
                section("Iron, bleach & cleaning", care.safeSections.care ?? [], Theme.care, Theme.careSoft, CareSymbolView(category: "iron", code: "medium"))
                section("Do not", care.safeSections.doNot ?? [], Theme.stop, Theme.stopSoft, Image(systemName: "nosign").resizable().scaledToFit(), danger: true)
                dashed
                Text("Symbols read").font(.headline).padding(.vertical, 8)
                FlowLayout {
                    ForEach(care.safeSymbols) { s in
                        HStack(spacing: 8) {
                            CareSymbolView(s).frame(width: 34, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.meaning ?? "").font(.footnote)
                                let c = s.confidence ?? 0
                                Text("\(Theme.confidenceWord(c)) confidence · \(Int(c))%").font(.caption2).foregroundStyle(Theme.confidenceColor(c))
                            }
                        }
                        .padding(6)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                        .accessibilityElement(children: .combine)
                    }
                }
                if let other = care.labelText?.other, !other.isEmpty {
                    let lang = care.labelText?.language ?? ""
                    Text("**Other text on label:** \(other)\(lang.isEmpty || lang.lowercased().contains("english") ? "" : " (translated from \(lang))")")
                        .font(.footnote).padding(.top, 8)
                }
            }
        }
        .padding(18)
        .background(Theme.tag, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 6))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 6).stroke(Theme.line, lineWidth: 1.5))
    }

    private var stitch: some View {
        Rectangle().fill(.clear).frame(height: 2)
            .overlay(Line().stroke(Theme.stitch, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
    }
    private var dashed: some View {
        Line().stroke(Theme.stitch, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).frame(height: 1).padding(.top, 12)
    }

    private func section(_ title: String, _ lines: [String], _ fg: Color, _ bg: Color, _ icon: some View, first: Bool = false, danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !first { dashed }
            HStack(spacing: 10) {
                icon.frame(width: 28, height: 28).foregroundStyle(fg)
                    .padding(6).background(bg, in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
            }
            .padding(.top, first ? 12 : 4)
            if lines.isEmpty {
                Text("Nothing on the label for this.").font(.footnote).foregroundStyle(Theme.ink2)
            } else {
                ForEach(lines, id: \.self) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(danger ? "✕" : "•").bold().foregroundStyle(danger ? Theme.stop : Theme.ink)
                        Text(l)
                    }
                }
            }
        }
    }
}

struct Line: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

// MARK: - Confidence

struct ConfidenceBar: View {
    var label: String
    var value: Double
    var body: some View {
        let v = max(0, min(100, value.rounded()))
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label); Spacer(); Text("\(Theme.confidenceWord(v)) · \(Int(v))%") }.font(.caption).foregroundStyle(Theme.ink2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(Theme.confidenceColor(v)).frame(width: g.size.width * v / 100)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(v)) percent, \(Theme.confidenceWord(v))")
    }
}

struct ConfidencePanel: View {
    var rec: ScanRecord
    var body: some View {
        Panel(title: "How sure Washtag is") {
            if let c = rec.care { ConfidenceBar(label: "Label reading", value: c.overallConfidence ?? 0) }
            if let u = rec.upc { ConfidenceBar(label: "Barcode digits", value: u.readConfidence) }
            if let p = rec.product { ConfidenceBar(label: "Product match", value: p.found ? (p.confidence ?? 0) : min(p.confidence ?? 0, 30)) }
            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top, spacing: 8) { Text(c.0).bold().frame(width: 16); Text(c.1).font(.subheadline) }
            }
            if let r = rec.care?.recheck, !r.isEmpty {
                Text("**Double-check on the label:** \(r.joined(separator: "; "))")
                    .font(.subheadline).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.drySoft, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var checks: [(String, String)] {
        var out: [(String, String)] = []
        if let c = rec.care {
            out.append((c.imageQuality == "good" ? "✓" : "!", "Photo quality: \(c.imageQuality ?? "unknown")\(c.qualityNotes.map { " — \($0)" } ?? "")"))
        }
        if let u = rec.upc {
            out.append((u.checksum == true ? "✓" : u.checksum == false ? "✕" : "?",
                        u.checksum == true ? "\(u.type) check digit is valid" : u.checksum == false ? "Check digit doesn’t match — some digits are probably misread" : "Not a standard UPC/EAN length"))
            out.append((u.via == "on-device decoder" ? "✓" : "·", "Digits \(u.via)"))
            if u.agree == true { out.append(("✓", "Decoded bars and printed numbers agree")) }
            if u.agree == false { out.append(("✕", "Bars read \(u.code) but printed digits look like \(u.visualDigits ?? "")")) }
        }
        if let b = rec.product?.basis { out.append(("·", b)) }
        return out
    }
}

// MARK: - Product

struct ProductPanel: View {
    var rec: ScanRecord
    var body: some View {
        Panel(title: "Product details") {
            if let u = rec.upc { Text("Barcode \(u.code) · \(u.type)").font(.caption.monospaced()).foregroundStyle(Theme.ink2) }
            if let p = rec.product {
                if !p.found {
                    Text("**Not found in the product database.** \(p.gs1Region.map { "The code prefix is registered in \($0). " } ?? "")Use the links below to search elsewhere.")
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        if let s = p.imageURL, let url = URL(string: s) {
                            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Theme.surface2 }
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.productName ?? "Unnamed product").font(.headline)
                            if let b = p.brand { Text(b).foregroundStyle(Theme.ink2) }
                        }
                    }
                    if let d = p.description { Text(d).font(.subheadline).lineLimit(6) }
                    let meta = [p.category, p.material, p.manufacturer.flatMap { $0 != p.brand ? "Made by \($0)" : nil }, p.gs1Region.map { "Registered in \($0)" }].compactMap { $0 }
                    if !meta.isEmpty { Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.ink2) }
                    ForEach(p.careNotes ?? [], id: \.self) { Text("• \($0)").font(.subheadline) }
                    if p.detergentUse?.isLaundryProduct == true, let dose = p.detergentUse?.typicalDoseNote {
                        Text("**Dosing:** \(dose)").font(.subheadline).padding(10).background(Theme.drySoft, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let stores = p.stores, !stores.isEmpty {
                        Text("Where to buy").font(.subheadline.bold()).padding(.top, 4)
                        ForEach(stores, id: \.self) { s in
                            if let l = s.link, let url = URL(string: l) {
                                Link("\(s.name ?? "Store")\(s.price.map { " · \($0)" } ?? "") ↗", destination: url).font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                HStack { ProgressView(); Text("Looking up…").foregroundStyle(Theme.ink2) }
            }
            FlowLayout {
                ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                    Link("\(l.0) ↗", destination: l.1).font(.footnote).padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                }
            }
            .padding(.top, 6)
            Text(productCredit).font(.caption2).foregroundStyle(Theme.ink2)
        }
    }

    private var productCredit: String {
        switch rec.product?.source {
        case "upcitemdb": return "Product data from UPCitemdb."
        case let s? where s.contains("openproductsfacts"): return "Product data from Open Products Facts (ODbL)."
        case let s? where s.contains("openbeautyfacts"): return "Product data from Open Beauty Facts (ODbL)."
        case let s? where s.contains("openfoodfacts"): return "Product data from Open Food Facts (ODbL)."
        default: return "Searched UPCitemdb and the Open Facts databases."
        }
    }

    private var links: [(String, URL)] {
        var out: [(String, URL)] = []
        let p = rec.product
        let brand = p?.brand ?? rec.care?.product?.brand
        let name = p?.productName ?? rec.care?.product?.name ?? ""
        func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        if let brand, let u = URL(string: "https://www.google.com/search?q=" + q("\(brand) \(name) care instructions")) { out.append(("Manufacturer care info", u)) }
        if let code = rec.upc?.code, !code.isEmpty {
            if let u = URL(string: "https://www.upcitemdb.com/upc/\(code)") { out.append(("UPCitemdb", u)) }
            if let u = URL(string: "https://world.openproductsfacts.org/product/\(code)") { out.append(("Open Products Facts", u)) }
            if let u = URL(string: "https://www.google.com/search?q=\(code)") { out.append(("Web search", u)) }
        }
        return out
    }
}

struct SuggestionsList: View {
    var s: Suggestions
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array((s.suggestions ?? []).enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 3) {
                    Text(x.type ?? "").bold()
                    if let w = x.why { Text(w).font(.subheadline) }
                    if let e = x.examples, !e.isEmpty { Text("Examples: \(e.joined(separator: ", "))").font(.caption).foregroundStyle(Theme.ink2) }
                    if let h = x.howMuch { Text(h).font(.caption) }
                }
            }
            if let a = s.avoid, !a.isEmpty {
                Text("Avoid").bold().foregroundStyle(Theme.stop)
                ForEach(Array(a.enumerated()), id: \.offset) { _, x in
                    Text("**\(x.what ?? "")** — \(x.why ?? "")").font(.subheadline)
                }
            }
        }
        .padding(.top, 6)
    }
}
