// The saved index, household and settings. Kept in this browser's storage, so it stays on
// the device. Port of Store.swift, plus backup/restore since a browser can clear site data.

const KEY = "washtag.v1";
export const PERSON_COLORS = ["#2358C9", "#C4572F", "#2E7D6B", "#8A4FBF", "#B7791F", "#C23B6E", "#3B8FA8", "#5B6B2E"];

const defaults = () => ({
  items: [], people: [], units: "metric", washer: null, dryer: null,
  load: { ids: [], size: "medium", soil: "normal", water: "unknown", machine: "he", form: "liquid", needs: [] },
});

export const store = {
  ...defaults(),
  saveError: null,
  listeners: new Set(),

  init() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) this.apply(JSON.parse(raw));
    } catch { /* start empty */ }
    // Ask the browser not to clear the index when space runs low.
    navigator.storage?.persist?.().catch(() => {});
  },

  apply(s) {
    const d = defaults();
    this.items = Array.isArray(s.items) ? s.items : d.items;
    this.people = Array.isArray(s.people) ? s.people : d.people;
    this.units = s.units === "us" ? "us" : "metric";
    this.washer = s.washer || null;
    this.dryer = s.dryer || null;
    this.load = { ...d.load, ...(s.load || {}) };
  },

  snapshot() {
    const { items, people, units, load, washer, dryer } = this;
    return { items, people, units, load, washer, dryer };
  },

  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.snapshot()));
      this.saveError = null;
    } catch {
      this.saveError = "This browser is out of space for Washtag. Delete a few saved items or download a backup.";
    }
    this.listeners.forEach((f) => f());
  },

  isSaved(id) { return this.items.some((r) => r.id === id); },

  upsert(record) {
    const i = this.items.findIndex((r) => r.id === record.id);
    if (i >= 0) this.items[i] = record; else this.items.unshift(record);
    this.save();
  },

  remove(id) {
    this.items = this.items.filter((r) => r.id !== id);
    this.load.ids = this.load.ids.filter((x) => x !== id);
    this.save();
  },

  addPerson(name) {
    const n = name.trim().slice(0, 40);
    if (!n) return;
    this.people.push({ id: uid(), name: n, colorIndex: this.people.length % PERSON_COLORS.length });
    this.save();
  },

  removePerson(id) {
    this.people = this.people.filter((p) => p.id !== id);
    this.items.forEach((r) => { r.people = (r.people || []).filter((x) => x !== id); });
    this.save();
  },

  person(id) { return this.people.find((p) => p.id === id); },
};

export const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

export function newRecord(mode) {
  return { id: uid(), createdAt: new Date().toISOString(), mode, name: "", people: [], notes: "", thumbnail: null,
    care: null, upc: null, product: null, suggestions: null };
}
