import SwiftUI

struct IndexView: View {
    var goToLoad: () -> Void
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var personFilter: String?

    private var filtered: [ScanRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.items.filter { r in
            (personFilter == nil || r.people.contains(personFilter!)) &&
            (q.isEmpty || [r.name, r.notes, r.upc?.code, r.product?.brand, r.product?.productName, r.care?.labelText?.fibres, r.care?.product?.type]
                .compactMap { $0?.lowercased() }.contains { $0.contains(q) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.people.isEmpty {
                    FlowLayout {
                        Chip(label: "Everyone", selected: personFilter == nil) { personFilter = nil }
                        ForEach(store.people) { p in
                            Chip(label: p.name, selected: personFilter == p.id, dot: PersonColors.color(p.colorIndex)) { personFilter = p.id }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if filtered.isEmpty {
                    Text(store.items.isEmpty ? "Your index is empty. Scan a label, then tap “Save to index”." : "Nothing matches that search.")
                        .foregroundStyle(Theme.ink2).frame(maxWidth: .infinity).padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { r in
                    NavigationLink { ItemDetailView(id: r.id, goToLoad: goToLoad) } label: { ItemRow(rec: r) }
                }
                .onDelete { idx in idx.map { filtered[$0].id }.forEach(store.delete) }
            }
            .searchable(text: $query, prompt: "Search by name, brand, fabric or code")
            .navigationTitle("Saved index")
        }
    }
}

struct ItemRow: View {
    @Environment(AppStore.self) private var store
    var rec: ScanRecord
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let d = rec.thumbnail, let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() }
                else { CareSymbolView(category: rec.mode == .upc ? "other" : "wash").padding(10) }
            }
            .frame(width: 56, height: 56).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.name.isEmpty ? "Unnamed" : rec.name).bold()
                let owners = rec.people.compactMap(store.person)
                if !owners.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(owners) { p in
                            HStack(spacing: 4) { Circle().fill(PersonColors.color(p.colorIndex)).frame(width: 9, height: 9); Text(p.name) }
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.ink2)
                } else {
                    Text(rec.upc.map { "Barcode \($0.code)" } ?? rec.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(Theme.ink2)
                }
                HStack(spacing: 2) {
                    ForEach(Array(rec.care?.safeSymbols.prefix(5) ?? []), id: \.id) { CareSymbolView($0).frame(width: 20, height: 21) }
                }
                .foregroundStyle(Theme.ink2)
            }
        }
    }
}

struct ItemDetailView: View {
    var id: String
    var goToLoad: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let rec = store.items.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 14) {
                    RecordView(record: rec, onLoad: goToLoad)
                    Button("Delete from index", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
                }
                .padding(16)
                .navigationTitle(rec.name)
                .confirmationDialog("Delete “\(rec.name)” from your index?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { store.delete(id); dismiss() }
                }
            }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
    }
}
