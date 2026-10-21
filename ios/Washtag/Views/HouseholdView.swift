import SwiftUI

struct HouseholdView: View {
    @Environment(AppStore.self) private var store
    @State private var newName = ""
    @State private var removing: Person?

    private let privacyURL = (Bundle.main.object(forInfoDictionaryKey: "WashtagPrivacyURL") as? String).flatMap(URL.init(string:))

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Add a person") {
                    HStack {
                        TextField("Name, e.g. Asha or Kids", text: $newName).onSubmit(add)
                        Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("People") {
                    if store.people.isEmpty { Text("No one added yet.").foregroundStyle(Theme.ink2) }
                    ForEach(store.people) { p in
                        let n = store.items.filter { $0.people.contains(p.id) }.count
                        HStack {
                            Circle().fill(PersonColors.color(p.colorIndex)).frame(width: 12, height: 12)
                            Text(p.name).bold()
                            Text("\(n) item\(n == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.ink2)
                            Spacer()
                            Button("Remove") { removing = p }.font(.subheadline)
                        }
                    }
                }
                Section("Units") {
                    Picker("Units", selection: $store.units) {
                        Text("°C and ml").tag(Units.metric)
                        Text("°F and fl oz").tag(Units.us)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Privacy & ads") {
                    if AdsManager.shared.privacyOptionsRequired {
                        Button("Ad privacy choices") { Task { await AdsManager.shared.presentPrivacyOptions() } }
                    }
                    if let privacyURL { Link("Privacy policy", destination: privacyURL) }
                    Link("Report an inappropriate ad", destination: URL(string: "mailto:support@example.com?subject=Washtag%20ad%20report")!)
                }
                Section {
                    Text("Care labels are read by Claude (Anthropic) and products are looked up in the Barcode Lookup database. Each result shows how confident it is. Detergent amounts are starting points — your detergent’s cap or scoop markings win. Your index stays on this phone.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                }
            }
            .navigationTitle("Household")
            .confirmationDialog("Remove \(removing?.name ?? "")? Their items stay in the index, unlabelled.",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) { if let r = removing { store.removePerson(r.id) }; removing = nil }
            }
        }
    }

    private func add() {
        store.addPerson(newName)
        newName = ""
    }
}
