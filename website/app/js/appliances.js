// Washer and dryer specs (shape matches appliancePrompt in the backend). Port of Appliances.swift.

export const WASHER_TYPES = [["front", "Front loader"], ["top_he", "Top loader (HE, no agitator)"], ["top_agitator", "Top loader with agitator"]];
export const DRYER_TYPES = [["electric", "Electric vented"], ["gas", "Gas"], ["heat_pump", "Heat pump"], ["condenser", "Condenser"]];
export const TYPE_NAMES = Object.fromEntries([...WASHER_TYPES, ...DRYER_TYPES]);

function base(kind, type, extra) {
  return { kind, brand: "", model: "", name: null, type, capacityCuFt: null, capacityKg: null, detergent: null, maxSpinRpm: null,
    hasHeater: null, sensorDry: null, steam: null, cycles: [], tips: [], source: "default", confidence: null, basis: null, ...extra };
}

/** Built-in specs for when the model can't be looked up. Typical for the type, not for a specific machine. */
export function typical(kind, type) {
  if (kind === "washer") {
    if (type === "top_he") return base(kind, type, { capacityCuFt: 5.0, capacityKg: 11, detergent: "he", maxSpinRpm: 800, hasHeater: false, steam: false,
      cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Whites", "Towels", "Perm Press", "Delicates", "Hand Wash", "Quick Wash", "Rinse & Spin"],
      tips: ["Use HE detergent only, and no more than the cap's line 1 or 2 — extra suds stop the low-water rinse working.",
        "Load loosely around the wash plate; don't wrap long items around the centre.",
        "Leave the lid open after washing so the tub dries out."] });
    if (type === "top_agitator") return base(kind, type, { capacityCuFt: 4.0, capacityKg: 8, detergent: "standard", maxSpinRpm: 700, hasHeater: false, steam: false,
      cycles: ["Normal", "Heavy Duty", "Bulky", "Whites", "Perm Press", "Delicates", "Quick Wash", "Rinse & Spin"],
      tips: ["Standard or HE detergent both work; add it to the water before the clothes.",
        "Don't load above the top row of holes in the tub, so clothes can turn over.",
        "The agitator is rough on delicates — use a mesh bag and the Delicates cycle."] });
    return base(kind, "front", { capacityCuFt: 4.5, capacityKg: 10, detergent: "he", maxSpinRpm: 1200, hasHeater: true, steam: false,
      cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Whites", "Towels", "Perm Press", "Delicates", "Hand Wash / Wool", "Quick Wash", "Rinse & Spin", "Self Clean"],
      tips: ["Use HE detergent only; liquid in the dispenser, pods in the empty drum.",
        "Fill the drum loosely to about a hand's width from the top for normal cycles.",
        "Leave the door ajar and wipe the gasket after washing to stop mildew.",
        "Run the clean cycle about once a month."] });
  }
  if (type === "heat_pump") return base(kind, type, { capacityCuFt: 4.0, capacityKg: 8, sensorDry: true, steam: false,
    cycles: ["Normal", "Heavy Duty", "Bulky", "Towels", "Perm Press", "Delicates", "Wool", "Timed Dry", "Air Fluff"],
    tips: ["Heat pump dryers run cooler and take longer, which is kinder to fabrics.",
      "Clean the lint filter every load and the condenser filter every few loads.",
      "Empty the water tank (if not plumbed to a drain)."] });
  if (type === "condenser") return base(kind, type, { capacityCuFt: 4.0, capacityKg: 8, sensorDry: true, steam: false,
    cycles: ["Normal", "Heavy Duty", "Towels", "Perm Press", "Delicates", "Timed Dry", "Air Fluff"],
    tips: ["Clean the lint filter every load and rinse the condenser regularly.",
      "Empty the water tank after each load (if not plumbed to a drain)."] });
  return base(kind, type === "gas" ? "gas" : "electric", { capacityCuFt: 7.4, capacityKg: 11, sensorDry: true, steam: false,
    cycles: ["Normal", "Heavy Duty", "Bulky / Bedding", "Towels", "Perm Press", "Delicates", "Timed Dry", "Air Fluff"],
    tips: ["Clean the lint filter before every load — it saves energy and is a fire-safety must.",
      "Use the sensor (auto) cycles rather than timed dry so clothes aren't over-dried.",
      "Don't fill more than about three-quarters full so clothes can tumble."] });
}

/** What the drum holds, in kg. US makers quote cubic feet, so convert roughly when that's all we have. */
export function capacityKg(a) {
  if (a.capacityKg > 0) return a.capacityKg;
  if (a.capacityCuFt > 0) return a.capacityCuFt * (a.kind === "washer" ? 2.2 : 1.4);
  return typical(a.kind, a.type).capacityKg ?? 8;
}

export function title(a) {
  const t = [a.brand, a.model].filter(Boolean).join(" ");
  return t || TYPE_NAMES[a.type] || a.type;
}

export const isHE = (a) => a.kind === "washer" && (a.detergent ?? (a.type === "top_agitator" ? "standard" : "he")) === "he";

/** Fills in what the lookup knew; anything it didn't know keeps the typical value for the type. */
export function applyLookup(r, current) {
  const types = (current.kind === "washer" ? WASHER_TYPES : DRYER_TYPES).map((t) => t[0]);
  const t = types.includes(r.type) ? r.type : current.type;
  const a = typical(current.kind, t);
  a.brand = current.brand; a.model = current.model;
  a.name = r.name ?? null;
  a.capacityCuFt = r.capacityCuFt ?? (r.capacityKg == null ? a.capacityCuFt : null);
  a.capacityKg = r.capacityKg ?? (r.capacityCuFt == null ? a.capacityKg : null);
  if (["he", "standard"].includes(r.detergent)) a.detergent = r.detergent;
  a.maxSpinRpm = r.maxSpinRpm ?? a.maxSpinRpm;
  a.hasHeater = r.hasHeater ?? a.hasHeater;
  a.sensorDry = r.sensorDry ?? a.sensorDry;
  a.steam = r.steam ?? a.steam;
  if (r.cycles?.length) a.cycles = r.cycles.slice(0, 20);
  if (r.tips?.length) a.tips = r.tips.slice(0, 6);
  a.source = r.found === true ? "lookup" : "default";
  a.confidence = r.confidence ?? null;
  a.basis = r.basis ?? null;
  return a;
}
