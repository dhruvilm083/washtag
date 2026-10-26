import SwiftUI

struct LoadView: View {
    @Environment(AppStore.self) private var store
    @State private var suggestions: Suggestions?
    @State private var suggesting = false
    @State private var suggestError: String?
    @State private var mode = "load"   // load | sort

    var body: some View {
        @Bindable var store = store
        let items = store.items.filter { store.load.ids.contains($0.id) && $0.care?.structured != nil }
        let combined = LoadPlanner.combine(items, units: store.units)
        let delicate = ["gentle", "hand"].contains(combined.cycle) || store.load.needs.contains("wool")
        let dose = LoadPlanner.dose(store.load, delicate: delicate, units: store.units)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MachinesSummary()
                    Segmented(options: [("sort", "Sort my laundry"), ("load", "One load")], selection: $mode)
                    Text(mode == "sort"
                         ? "Pick everything in the basket. Washtag sorts it into loads, picks the order to run them, and matches cycles to your machines."
                         : "Pick what’s going in the machine. Washtag uses the strictest label in the pile and works out how much detergent to use.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                    picker
                    if mode == "sort" {
                        Panel(title: "Detergent") {
                            Segmented(options: [("liquid", "Liquid"), ("powder", "Powder"), ("pod", "Pods")], selection: $store.load.form)
                            Segmented(options: [("soft", "Soft water"), ("medium", "Average"), ("hard", "Hard water"), ("unknown", "Not sure")], selection: $store.load.water)
                        }
                        sortPlan(items)
                    } else {
                        Panel(title: "About the load") {
                            field("Load size") { Segmented(options: [("small", "Small"), ("medium", "Medium"), ("large", "Large"), ("xl", "Extra large")], selection: $store.load.size) }
                            field("How dirty") { Segmented(options: [("light", "Light"), ("normal", "Normal"), ("heavy", "Heavy / stained")], selection: $store.load.soil) }
                            field("Water") { Segmented(options: [("soft", "Soft"), ("medium", "Average"), ("hard", "Hard"), ("unknown", "Not sure")], selection: $store.load.water) }
                            field("Machine") {
                                if let w = store.washer {
                                    Text("\(w.title) · \(w.isHE ? "HE detergent" : "standard detergent")").font(.subheadline)
                                } else {
                                    Segmented(options: [("he", "HE / front loader"), ("standard", "Standard top loader")], selection: $store.load.machine)
                                }
                            }
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
            HStack {
                Text(mode == "sort" ? "In the basket" : "Items in this load").font(.headline); Spacer()
                if mode == "sort" { Button("All") { store.load.ids = withCare.map(\.id) }.font(.subheadline) }
                Button("Clear") { store.load.ids = [] }.font(.subheadline)
            }
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
            Text(items.isEmpty ? "Detergent for this load" : "Washtag recommends for these \(items.count) item\(items.count == 1 ? "" : "s")").font(.title3.weight(.heavy))
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
            row("Cycle", machineCycleName(c) + (delicate && c.cycle != "hand" ? " — use a delicate detergent" : ""))
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

    /// The washer's own cycle name when we know the model, otherwise the generic one.
    private func machineCycleName(_ c: LoadPlanner.Combined) -> String {
        let generic = LoadPlanner.cycleName[c.cycle] ?? c.cycle
        let want = ["hand": ["hand", "wool", "delicate"], "gentle": ["delicate", "gentle"], "permanent_press": ["perm", "synthetic", "casual"]][c.cycle] ?? ["normal", "cotton"]
        guard let w = store.washer, let name = LaundryPlanner.machineCycle(w.cycles, want) else { return generic }
        return "\(name) on your \(w.title)"
    }

    // MARK: sort my laundry

    @ViewBuilder private func sortPlan(_ items: [ScanRecord]) -> some View {
        let plan = LaundryPlanner.plan(items, washer: store.washer, dryer: store.dryer, units: store.units)
        if items.isEmpty {
            Text("Pick some items above and Washtag recommends how to split them into loads.").font(.subheadline).foregroundStyle(Theme.ink2)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Washtag recommends \(plan.loads.count) load\(plan.loads.count == 1 ? "" : "s")").font(.title3.weight(.heavy))
                if plan.totalMinutes > 0 { Text("About \(duration(plan.totalMinutes)) from first wash to last dry.").font(.subheadline).foregroundStyle(Theme.ink2) }
                ForEach(plan.orderWhy, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.ink2) }
                if store.washer == nil || store.dryer == nil {
                    Text("Using typical machine specs — add your washer and dryer above for settings that match them.").font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            if !plan.notForMachine.isEmpty {
                Text("**Keep out of the machine:** \(plan.notForMachine.joined(separator: "; ")).").padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.stopSoft, in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(Array(plan.loads.enumerated()), id: \.element.id) { i, l in loadCard(i + 1, of: plan.loads.count, l) }
        }
    }

    private func loadCard(_ n: Int, of total: Int, _ l: LaundryPlanner.PlannedLoad) -> some View {
        var L = store.load
        L.size = l.size
        if let w = store.washer { L.machine = w.isHE ? "he" : "standard" }
        let dose = LoadPlanner.dose(L, delicate: l.delicate, units: store.units)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(n)").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Theme.tub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.title).font(.headline)
                    Text("\(l.items.count) item\(l.items.count == 1 ? "" : "s") · about \(Int((min(l.fill, 1.5) * 100).rounded()))% of the drum").font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            Text(l.items.map(\.name).joined(separator: ", ")).font(.subheadline)
            Divider()
            row("Wash", "\(l.washCycle) · \(LoadPlanner.tempAdvice(l.combined, store.load, units: store.units).lowercasedFirst)")
            row("Spin", l.spin)
            row("Detergent", "\(dose.amount) \(dose.unit)" + (l.delicate ? " of a gentle, enzyme-free detergent" : ""))
            row("Bleach", ["any": "Any bleach if needed", "non_chlorine": "Oxygen / non-chlorine only", "none": "No bleach"][l.combined.bleach] ?? l.combined.bleach)
            row("Dry", l.dry.setting + (l.dry.airDry.isEmpty ? "" : "\n" + l.dry.airDry.map { "• \($0)" }.joined(separator: "\n")))
            if !l.notes.isEmpty { bullets("Washtag recommends", l.notes) }
            Button {
                store.load.ids = l.items.map(\.id)
                store.load.size = l.size
                mode = "load"
            } label: { Text("Open as this load") }
            .buttonStyle(.bordered)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tag, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Load \(n) of \(total): \(l.title)")
    }

    private func duration(_ m: Int) -> String { m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min" }

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

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
