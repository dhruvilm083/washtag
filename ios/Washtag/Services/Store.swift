import Foundation
import Observation

/// The saved index, household and settings. Stored as JSON in the app's
/// Documents folder, so it stays on the phone (and in the user's iCloud device backup).
@Observable
final class AppStore {
    var items: [ScanRecord] = []
    var people: [Person] = []
    var units: Units = .metric { didSet { save() } }
    var load = LoadSettings() { didSet { save() } }
    var washer: Appliance? { didSet { save() } }
    var dryer: Appliance? { didSet { save() } }

    private struct Snapshot: Codable {
        var items: [ScanRecord]; var people: [Person]; var units: Units; var load: LoadSettings
        var washer: Appliance?; var dryer: Appliance?
    }
    private let url = URL.documentsDirectory.appending(path: "washtag.json")
    private var loading = false

    init() {
        loading = true
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            items = s.items; people = s.people; units = s.units; load = s.load; washer = s.washer; dryer = s.dryer
        }
        loading = false
    }

    func save() {
        guard !loading else { return }
        let snap = Snapshot(items: items, people: people, units: units, load: load, washer: washer, dryer: dryer)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
    }

    func isSaved(_ id: String) -> Bool { items.contains { $0.id == id } }

    func upsert(_ record: ScanRecord) {
        if let i = items.firstIndex(where: { $0.id == record.id }) { items[i] = record } else { items.insert(record, at: 0) }
        save()
    }

    func delete(_ id: String) {
        items.removeAll { $0.id == id }
        load.ids.removeAll { $0 == id }
        save()
    }

    func addPerson(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !trimmed.isEmpty else { return }
        people.append(Person(name: trimmed, colorIndex: people.count % PersonColors.all.count))
        save()
    }

    func removePerson(_ id: String) {
        people.removeAll { $0.id == id }
        for i in items.indices { items[i].people.removeAll { $0 == id } }
        save()
    }

    func person(_ id: String) -> Person? { people.first { $0.id == id } }
}
