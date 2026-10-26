import SwiftUI

/// "Your washer & dryer": look a model up for the maker's specs, or pick the type and use typical specs.
struct AppliancesView: View {
    var body: some View {
        Form {
            Section {
                Text("Add your machines and Washtag recommends cycles, load sizes and detergent that match them. Specs from a lookup show how sure they are — check them against your manual or the sticker inside the door.")
                    .font(.footnote).foregroundStyle(Theme.ink2)
            }
            ApplianceSection(kind: .washer)
            ApplianceSection(kind: .dryer)
        }
        .navigationTitle("Washer & dryer")
    }
}

private struct ApplianceSection: View {
    @Environment(AppStore.self) private var store
    var kind: ApplianceKind
    @State private var draft: Appliance?
    @State private var looking = false
    @State private var lookupError: String?

    private var saved: Appliance? { kind == .washer ? store.washer : store.dryer }
    private var noun: String { kind == .washer ? "washer" : "dryer" }

    var body: some View {
        let a = draft ?? saved ?? Appliance.typical(kind, type: kind == .washer ? "front" : "electric")
        Section(kind == .washer ? "Washer" : "Dryer") {
            TextField("Brand, e.g. LG or Whirlpool", text: binding(a, \.brand)).textInputAutocapitalization(.words)
            TextField("Model number (inside the door or lid)", text: binding(a, \.model))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button {
                Task { await lookup(a) }
            } label: { if looking { ProgressView() } else { Label("Look up maker’s specs", systemImage: "magnifyingglass") } }
                .disabled(looking || (a.brand.trimmingCharacters(in: .whitespaces).isEmpty && a.model.trimmingCharacters(in: .whitespaces).isEmpty))
            if let lookupError { Text(lookupError).font(.footnote).foregroundStyle(Theme.stop) }
            sourceLine(a)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.subheadline.bold())
                Segmented(options: kind == .washer ? Appliance.washerTypes : Appliance.dryerTypes, selection: Binding(
                    get: { a.type },
                    set: { t in
                        // A new type brings that type's typical specs, keeping the name and model.
                        var n = Appliance.typical(kind, type: t); n.brand = a.brand; n.model = a.model; n.source = "manual"
                        draft = n
                    }))
            }
            capacityField(a)
            if kind == .washer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detergent").font(.subheadline.bold())
                    Segmented(options: [("he", "HE (high efficiency)"), ("standard", "Standard")], selection: Binding(
                        get: { a.detergent ?? "he" }, set: { v in edit(a) { $0.detergent = v } }))
                }
                Stepper("Max spin: \(a.maxSpinRpm.map { "\($0) rpm" } ?? "not sure")", value: Binding(
                    get: { a.maxSpinRpm ?? 1000 }, set: { v in edit(a) { $0.maxSpinRpm = v } }), in: 400...1800, step: 100)
                Toggle("Heats its own water", isOn: Binding(get: { a.hasHeater ?? false }, set: { v in edit(a) { $0.hasHeater = v } }))
            } else {
                Toggle("Sensor / auto dry", isOn: Binding(get: { a.sensorDry ?? true }, set: { v in edit(a) { $0.sensorDry = v } }))
            }
            if !a.cycles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cycles").font(.subheadline.bold())
                    FlowLayout(spacing: 6) {
                        ForEach(a.cycles, id: \.self) { c in
                            Text(c).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.surface2, in: Capsule())
                        }
                    }
                }
            }
            if !a.tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.source == "lookup" ? "Maker’s recommendations" : "Recommended for this type").font(.subheadline.bold())
                    ForEach(a.tips, id: \.self) { Text("• \($0)").font(.footnote) }
                }
            }
            HStack {
                Button(saved == nil ? "Save \(noun)" : "Save changes") { save(a) }
                    .buttonStyle(.borderedProminent).disabled(draft == nil && saved != nil)
                Spacer()
                if saved != nil {
                    Button("Remove", role: .destructive) {
                        if kind == .washer { store.washer = nil } else { store.dryer = nil }
                        draft = nil
                    }
                }
            }
        }
    }

    @ViewBuilder private func sourceLine(_ a: Appliance) -> some View {
        switch a.source {
        case "lookup":
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal").foregroundStyle(Theme.good)
                Text("Specs for \(a.name ?? a.title)" + (a.confidence.map { " · \(Int($0))% sure" } ?? "")).font(.footnote)
            }
            if let b = a.basis { Text(b).font(.caption).foregroundStyle(Theme.ink2) }
        case "manual":
            Text("Using your own settings.").font(.footnote).foregroundStyle(Theme.ink2)
        default:
            Text("Using typical specs for a \(Appliance.typeNames[a.type]?.lowercased() ?? noun). Look up your model for the maker’s own.")
                .font(.footnote).foregroundStyle(Theme.ink2)
            if let b = a.basis { Text(b).font(.caption).foregroundStyle(Theme.ink2) }
        }
    }

    private func capacityField(_ a: Appliance) -> some View {
        let us = store.units == .us
        let value = us ? (a.capacityCuFt ?? a.capacityKgEstimate / (kind == .washer ? 2.2 : 1.4)) : a.capacityKgEstimate
        let step = us ? 0.1 : 0.5
        return Stepper(value: Binding(
            get: { value },
            set: { v in edit(a) { if us { $0.capacityCuFt = v; $0.capacityKg = nil } else { $0.capacityKg = v; $0.capacityCuFt = nil } } }),
            in: us ? 1.0...10.0 : 3.0...20.0, step: step) {
            Text("Drum: \(value.formatted(.number.precision(.fractionLength(1)))) \(us ? "cu ft" : "kg")")
        }
    }

    private func binding(_ a: Appliance, _ key: WritableKeyPath<Appliance, String>) -> Binding<String> {
        Binding(get: { a[keyPath: key] }, set: { v in edit(a) { $0[keyPath: key] = String(v.prefix(60)) } })
    }

    private func edit(_ a: Appliance, _ change: (inout Appliance) -> Void) {
        var n = a
        change(&n)
        if n.source != "manual" && (n.capacityKg != a.capacityKg || n.capacityCuFt != a.capacityCuFt || n.detergent != a.detergent
            || n.maxSpinRpm != a.maxSpinRpm || n.hasHeater != a.hasHeater || n.sensorDry != a.sensorDry) { n.source = "manual" }
        draft = n
    }

    private func save(_ a: Appliance) {
        if kind == .washer {
            store.washer = a
            store.load.machine = a.isHE ? "he" : "standard"
        } else { store.dryer = a }
        draft = nil
    }

    private func lookup(_ a: Appliance) async {
        looking = true; lookupError = nil
        defer { looking = false }
        do {
            let r = try await APIClient.shared.lookupAppliance(kind: kind, brand: a.brand, model: a.model)
            draft = r.applied(to: a)
            if r.found != true { lookupError = "Washtag couldn’t find that exact model, so it’s showing typical specs. Check the model number, or adjust the settings below." }
        } catch { lookupError = error.localizedDescription }
    }
}

/// One-line summary of the saved machines, used at the top of "This load".
struct MachinesSummary: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationLink {
            AppliancesView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "washer").font(.title2).foregroundStyle(Theme.tub)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your washer & dryer").font(.headline)
                    if store.washer == nil && store.dryer == nil {
                        Text("Add your models so Washtag recommends settings for your machines.").font(.caption).foregroundStyle(Theme.ink2)
                    } else {
                        Text([store.washer.map { "Washer: \($0.title)" }, store.dryer.map { "Dryer: \($0.title)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.ink2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.ink2)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
