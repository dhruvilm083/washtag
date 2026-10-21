import SwiftUI

struct LoadView: View {
    @Environment(AppStore.self) private var store
    @State private var suggestions: Suggestions?
    @State private var suggesting = false
    @State private var suggestError: String?

    var body: some View {
        @Bindable var store = store
        let items = store.items.filter { store.load.ids.contains($0.id) && $0.care?.structured != nil }
        let combined = LoadPlanner.combine(items, units: store.units)
        let delicate = ["gentle", "hand"].contains(combined.cycle) || store.load.needs.contains("wool")
        let dose = LoadPlanner.dose(store.load, delicate: delicate, units: store.units)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick what’s going in the machine. Washtag uses the strictest label in the pile and works out how much detergent to use.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                    picker
                    Panel(title: "About the load") {
                        field("Load size") { Segmented(options: [("small", "Small"), ("medium", "Medium"), ("large", "Large"), ("xl", "Extra large")], selection: $store.load.size) }
                        field("How dirty") { Segmented(options: [("light", "Light"), ("normal", "Normal"), ("heavy", "Heavy / stained")], selection: $store.load.soil) }
                        field("Water") { Segmented(options: [("soft", "Soft"), ("medium", "Average"), ("hard", "Hard"), ("unknown", "Not sure")], selection: $store.load.water) }
                        field("Machine") { Segmented(options: [("he", "HE / front loader"), ("standard", "Standard top loader")], selection: $store.load.machine) }
                        field("Detergent") { Segmented(options: [("liquid", "Liquid"), ("powder", "Powder"), ("pod", "Pods")], selection: $store.load.form) }
                        field("Needs") {
                            FlowLayout {
                                ForEach(NEEDS, id: \.key) { n in
                                    Chip(label: n.label, selected: store.load.needs.contains(n.key)) {
                                        if store.load.needs.contains(n.key) { store.load.needs.removeAll { $0 == n.key } } else { store.load.needs.append(n.key) }
                                    }
                                }
                            }
                        }
                    }
                    plan(items: items, c: combined, dose: dose, delicate: delicate)
                    Panel(title: "Products for this load") {
                        Text("Suggestions based on the combined labels and the needs you picked.").font(.caption).foregroundStyle(Theme.ink2)
                        Button {
                            Task { await suggest(items: items, c: combined) }
                        } label: { if suggesting { ProgressView() } else { Text("Get suggestions") } }
                        .buttonStyle(.bordered).disabled(suggesting)
                        if let suggestError { Text(suggestError).font(.footnote).foregroundStyle(Theme.ink2) }
                        if let suggestions { SuggestionsList(s: suggestions) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("This load")
        }
    }

    private var picker: some View {
        let withCare = store.items.filter { $0.care?.structured != nil }
        return Panel(title: nil) {
            HStack { Text("Items in this load").font(.headline); Spacer(); Button("Clear") { store.load.ids = [] }.font(.subheadline) }
            if withCare.isEmpty {
                Text("Save a few scanned labels to plan a mixed load. You can still work out a detergent amount below.")
                    .font(.subheadline).foregroundStyle(Theme.ink2).padding(.vertical, 10)
            }
            ForEach(withCare) { r in
                Toggle(isOn: Binding(
                    get: { store.load.ids.contains(r.id) },
                    set: { on in if on { if !store.load.ids.contains(r.id) { store.load.ids.append(r.id) } } else { store.load.ids.removeAll { $0 == r.id } } }
                )) { ItemRow(rec: r) }
            }
        }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.subheadline.bold()); content() }
    }

    private func plan(items: [ScanRecord], c: LoadPlanner.Combined, dose: LoadPlanner.Dose, delicate: Bool) -> some View {
        let L = store.load
        let warn = c.noMachine.map { "\($0) must not be washed — take it out of this load." } + c.dryCleanOnly.map { "\($0) is dry clean only — take it out of this load." }
        let extras = LoadPlanner.extras(c, L)
        return VStack(alignment: .leading, spacing: 12) {
            Text(items.isEmpty ? "Detergent for this load" : "Plan for \(items.count) item\(items.count == 1 ? "" : "s")").font(.title3.weight(.heavy))
            if !warn.isEmpty {
                Text("**Remove first:** \(warn.joined(separator: " "))").padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.stopSoft, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(dose.amount).font(.system(size: 44, weight: .heavy, design: .rounded))
                Text(dose.unit).bold()
            }
            Text("\(dose.detail). A starting point for a standard-concentration detergent — if its cap or scoop markings differ, follow them.")
                .font(.caption).foregroundStyle(Theme.ink2)
            Divider()
            row("Temperature", LoadPlanner.tempAdvice(c, L, units: store.units))
            row("Cycle", (LoadPlanner.cycleName[c.cycle] ?? c.cycle) + (delicate && c.cycle != "hand" ? " — use a delicate detergent" : ""))
            row("Bleach", ["any": "Any bleach allowed if needed", "non_chlorine": "Oxygen / non-chlorine only", "none": "No bleach"][c.bleach] ?? c.bleach)
            row("Drying", (c.tumble == "none" ? "No tumble drying for at least one item." : c.tumble == "low" ? "Tumble on low heat." : "Tumble dry normal is fine.")
                + (c.airDry.isEmpty ? "" : "\n" + c.airDry.map { "• \($0)" }.joined(separator: "\n")))
            if let iron = c.ironMax {
                row("Ironing", ["none": "Don’t iron at least one item", "low": "Low heat (up to 110°C / 230°F)", "medium": "Medium heat (up to 150°C / 300°F)", "high": "High heat (up to 200°C / 390°F)"][iron] ?? iron)
            }
            if !c.conflicts.isEmpty { bullets("Watch out", c.conflicts) }
            if !extras.isEmpty { bullets("For your needs", extras) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tag, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1.5))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k).bold().foregroundStyle(Theme.ink2).frame(width: 104, alignment: .leading); Text(v) }
    }

    private func bullets(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { Text("• \($0)") }
        }
    }

    private func suggest(items: [ScanRecord], c: LoadPlanner.Combined) async {
        suggesting = true; suggestError = nil
        defer { suggesting = false }
        do {
            suggestions = try await APIClient.shared.suggest(
                structured: StructuredCare(maxWashTempC: c.maxTemp, washCycle: c.cycle, bleach: c.bleach, tumble: c.tumble),
                needs: store.load.needs.map(needLabel),
                fibres: items.compactMap { $0.care?.labelText?.fibres }.joined(separator: "; "),
                type: items.map(\.name).joined(separator: ", "))
        } catch { suggestError = error.localizedDescription }
    }
}
