// "This load" (strictest label wins, then a detergent dose) and "Sort my laundry"
// (group into loads, order them for washer + dryer). Port of LoadPlanner.swift and LaundryPlanner.swift.

import { capacityKg, typical } from "./appliances.js";

export const NEEDS = [
  ["sensitive", "Sensitive skin"], ["fragrance", "Fragrance-free"], ["baby", "Baby clothes"], ["active", "Activewear odour"],
  ["stains", "Tough stains"], ["darks", "Keep darks dark"], ["whites", "Brighten whites"], ["wool", "Wool / delicates"],
  ["pets", "Pet hair"], ["eco", "Eco / cold wash"], ["towels", "Towels & absorbency"],
];
export const needLabel = (k) => (NEEDS.find((n) => n[0] === k) || [k, k])[1];

const cycleRank = { normal: 0, permanent_press: 1, gentle: 2, hand: 3 };
export const CYCLE_NAME = { normal: "Normal / cottons", permanent_press: "Permanent press / synthetics",
  gentle: "Gentle / delicates", hand: "Hand wash (or machine hand-wash cycle)" };

export function tempString(c, units) {
  if (c == null) return "—";
  const f = Math.round(c * 9 / 5 + 32), ci = Math.round(c);
  return units === "us" ? `${f}°F (${ci}°C)` : `${ci}°C (${f}°F)`;
}

const st = (it) => it.care?.structured || {};

export function combine(items, units) {
  const out = { maxTemp: null, cycle: "normal", bleach: "any", tumble: "normal", noMachine: [], dryCleanOnly: [], airDry: [], ironMax: null, conflicts: [] };
  const ironRank = { none: 0, low: 1, medium: 2, high: 3 };
  for (const it of items) {
    const s = st(it);
    if (s.washCycle === "do_not_wash" || s.dryClean === "only") {
      (s.dryClean === "only" ? out.dryCleanOnly : out.noMachine).push(it.name);
      continue;
    }
    if (s.maxWashTempC != null) out.maxTemp = Math.min(out.maxTemp ?? s.maxWashTempC, s.maxWashTempC);
    if (s.washCycle && (cycleRank[s.washCycle] ?? 0) > (cycleRank[out.cycle] ?? 0)) out.cycle = s.washCycle;
    if (s.bleach === "none" || (s.bleach === "non_chlorine" && out.bleach === "any")) out.bleach = s.bleach;
    if (s.tumble === "none") out.tumble = "none"; else if (s.tumble === "low" && out.tumble !== "none") out.tumble = "low";
    if (s.tumble === "none") {
      const how = { line: "line dry", flat: "dry flat", drip: "drip dry", shade: "dry in shade" }[s.naturalDry] || "air dry";
      out.airDry.push(`${it.name}: ${how}`);
    }
    if (s.iron) {
      if (out.ironMax == null || (ironRank[s.iron] ?? 0) < (ironRank[out.ironMax] ?? 0)) out.ironMax = s.iron;
    }
  }
  const washable = items.filter((it) => !out.noMachine.includes(it.name) && !out.dryCleanOnly.includes(it.name));
  const temps = washable.map((it) => st(it).maxWashTempC).filter((t) => t != null);
  if (temps.length > 1) {
    const hi = Math.max(...temps), lo = Math.min(...temps);
    if (hi - lo >= 30) out.conflicts.push(`Some items can take ${tempString(hi, units)} but others only ${tempString(lo, units)}. Everything will wash at the lower temperature — consider splitting hot-wash items (towels, bedding) into their own load.`);
  }
  const cycles = washable.map((it) => st(it).washCycle).filter(Boolean);
  if (cycles.includes("hand") && cycles.includes("normal")) {
    out.conflicts.push("Hand-wash items are mixed with sturdy ones. Heavy items can stretch or snag delicates — wash them separately or in a mesh bag.");
  }
  const fibres = washable.map((it) => (it.care?.labelText?.fibres || "").toLowerCase());
  const hasWoolSilk = fibres.some((f) => f.includes("wool") || f.includes("silk") || f.includes("cashmere"));
  const hasCotton = fibres.some((f) => (f.includes("cotton") || f.includes("denim")) && !f.includes("wool") && !f.includes("silk"));
  if (hasWoolSilk && hasCotton) out.conflicts.push("Wool or silk is mixed with cotton. Wool and silk need a detergent without enzymes; use one for the whole load or split it.");
  return out;
}

const trim = (v) => (v === Math.round(v) ? String(Math.round(v)) : String(v));

export function dose(L, delicate, units) {
  const size = { small: 0.7, medium: 1, large: 1.4, xl: 1.8 }[L.size] ?? 1;
  const soil = { light: 0.8, normal: 1, heavy: 1.3 }[L.soil] ?? 1;
  const water = { soft: 0.85, medium: 1, hard: 1.25, unknown: 1 }[L.water] ?? 1;
  const machine = L.machine === "standard" ? 1.25 : 1;
  const f = size * soil * water * machine * (delicate ? 0.8 : 1);
  if (L.form === "pod") {
    const n = f <= 1.15 ? 1 : f <= 1.9 ? 2 : 3;
    return { amount: String(n), unit: n === 1 ? "pod" : "pods", detail: "Put pods in the empty drum before the clothes — never in the dispenser." };
  }
  if (L.form === "powder") {
    const g = Math.round(60 * f / 5) * 5;
    return { amount: String(g), unit: "g powder", detail: `Roughly ${Math.round(g / 15)} level tablespoons` };
  }
  const ml = Math.round(30 * f / 5) * 5;
  const floz = Math.round(ml / 29.57 * 4) / 4;
  const tbsp = Math.round(ml / 15 * 2) / 2;
  return units === "us"
    ? { amount: trim(floz), unit: "fl oz liquid", detail: `${ml} ml · about ${trim(tbsp)} tablespoons` }
    : { amount: String(ml), unit: "ml liquid", detail: `About ${trim(tbsp)} tablespoons · ${trim(floz)} fl oz` };
}

export function tempAdvice(c, L, units) {
  const t = c.maxTemp;
  if (t == null) return L.needs.includes("eco") ? "Cold (30°C / 86°F) — no label limits in this load" : "Use the warmest the fabric allows; no label limits known for this load";
  if (L.needs.includes("eco") && t > 30) return `${tempString(30, units)} to save energy — labels allow up to ${tempString(t, units)}`;
  if (L.needs.includes("darks") && t > 30) return `${tempString(30, units)} to keep colours from fading (max allowed ${tempString(t, units)})`;
  return `Up to ${tempString(t, units)}`;
}

export function extras(c, L) {
  const x = [];
  if (L.needs.includes("stains") || L.soil === "heavy") {
    x.push(c.bleach === "none" ? "Pre-treat stains with a stain remover — no bleach of any kind for this load." : "Pre-treat stains; an oxygen booster (dose per the tub) helps with heavy soil.");
  }
  if (L.needs.includes("whites") && c.bleach !== "none") {
    x.push(c.bleach === "any" ? "For whites only: chlorine bleach is allowed — measure by the bottle and never mix with ammonia or vinegar." : "For whites: oxygen (non-chlorine) bleach only.");
  }
  if (L.water === "hard") x.push("Hard water: the dose above is already raised. A water softener additive can also help.");
  if (L.needs.includes("active") || L.needs.includes("towels")) {
    x.push("Skip fabric softener — it traps odour in activewear and makes towels less absorbent. A splash of white vinegar in the softener drawer is an alternative.");
  }
  if (L.needs.includes("pets")) x.push("Run a 10-minute no-heat tumble before washing to loosen pet hair, if the labels allow tumbling.");
  if (L.needs.some((n) => ["baby", "sensitive", "fragrance"].includes(n))) x.push("Use a fragrance-free, dye-free detergent and add an extra rinse.");
  return x;
}

/** Picks the machine's own cycle name that best matches, e.g. "Bulky / Bedding" for towels. */
export function machineCycle(cycles, keywords) {
  for (const k of keywords) {
    const c = (cycles || []).find((x) => x.toLowerCase().includes(k));
    if (c) return c;
  }
  return null;
}

/* ---------- Sort my laundry ---------- */

const CARE = { sturdy: 0, synthetic: 1, gentle: 2, wool: 3, hand: 4 };

const itemText = (it) => [it.name, it.product?.productName, it.product?.color, it.product?.category, it.care?.product?.type, it.care?.product?.name, it.notes]
  .filter(Boolean).join(" ").toLowerCase();
const itemFibres = (it) => (it.care?.labelText?.fibres || it.product?.material || "").toLowerCase();
const has = (s, words) => words.some((w) => s.includes(w));

function careOf(it) {
  const s = st(it), f = itemFibres(it);
  if (s.washCycle === "hand") return CARE.hand;
  if (has(f, ["wool", "silk", "cashmere", "merino", "alpaca", "mohair", "angora"])) return CARE.wool;
  if (s.washCycle === "gentle") return CARE.gentle;
  if (s.washCycle === "permanent_press") return CARE.synthetic;
  const t = itemText(it);
  if (has(f, ["elastane", "spandex", "lycra"]) || has(t, ["legging", "gym", "running", "sports", "activewear", "athletic", "yoga"])) return CARE.synthetic;
  return CARE.sturdy;
}

function colourOf(it) {
  const t = itemText(it);
  if (has(t, ["black", "navy", "charcoal", "dark", "denim", "jeans", "indigo", "brown", "burgundy", "maroon", "olive", "forest green"])) return "darks";
  if (has(t, ["white", "ivory", "cream", "off-white"])) return "whites";
  return "colours";
}

const isTowel = (it) => has(itemText(it), ["towel", "bath mat", "bedding", "sheet", "pillowcase", "duvet", "comforter", "blanket", "flannel", "washcloth"]);

const WEIGHTS = [
  ["comforter", 2.0], ["duvet cover", 0.9], ["duvet", 2.0], ["blanket", 1.5], ["coat", 1.2], ["jacket", 1.0],
  ["bath mat", 0.8], ["beach towel", 0.8], ["hand towel", 0.15], ["washcloth", 0.06], ["towel", 0.6],
  ["sheet", 0.7], ["pillowcase", 0.15], ["jeans", 0.7], ["denim", 0.7], ["hoodie", 0.6], ["sweatshirt", 0.6],
  ["sweatpant", 0.5], ["jogger", 0.5], ["jumper", 0.45], ["sweater", 0.45], ["cardigan", 0.4], ["trouser", 0.5],
  ["pants", 0.5], ["chino", 0.5], ["dress", 0.35], ["skirt", 0.3], ["pyjama", 0.3], ["pajama", 0.3], ["shirt", 0.25],
  ["blouse", 0.2], ["shorts", 0.25], ["legging", 0.2], ["tee", 0.2], ["top", 0.2], ["sock", 0.05],
  ["bra", 0.08], ["underwear", 0.08], ["boxer", 0.08],
];
/** Rough dry weight in kg, used to fill the drum sensibly. */
export function weight(it) {
  const t = itemText(it);
  const hit = WEIGHTS.find(([w]) => t.includes(w));
  return hit ? hit[1] : 0.35;
}

const groupKg = (g) => g.items.reduce((s, it) => s + weight(it), 0);

function target(g) {
  if (g.care === CARE.sturdy) return g.towels ? 0.75 : 0.8;
  if (g.care === CARE.synthetic) return 0.6;
  if (g.care === CARE.hand) return 0.35;
  return 0.5;
}

function mergeCost(a, b) {
  const colourOK = a.colour === b.colour || (a.colour === "whites" && b.colour === "colours")
    || (a.care >= CARE.gentle && b.care >= CARE.gentle && a.colour !== "whites" && b.colour !== "whites");
  if (!colourOK) return null;
  if (a.towels !== b.towels && (a.colour === "darks" || b.care === CARE.synthetic || a.care === CARE.synthetic)) return null; // lint
  let cost = 0;
  if (a.colour !== b.colour) cost += 4;
  if (a.hot !== b.hot) cost += 1;
  if (a.towels !== b.towels) cost += 3;
  if (a.care !== b.care) {
    const pair = [a.care, b.care].sort().join(",");
    const ok = [[CARE.sturdy, CARE.synthetic], [CARE.gentle, CARE.hand], [CARE.wool, CARE.hand], [CARE.gentle, CARE.wool]].map((p) => p.sort().join(","));
    if (!ok.includes(pair)) return null;
    cost += 2;
  }
  return cost;
}

function mergeNote(from, into) {
  if (from.colour === "whites" && into.colour !== "whites") return "Only a few whites, so Washtag recommends washing them with light colours on cold, with a colour-catcher sheet.";
  if (from.hot !== into.hot) return "Hot-wash items are joining a cooler load, so everything washes at the lower temperature.";
  if (from.care === CARE.wool || into.care === CARE.wool) return "Wool or silk is in this load, so Washtag recommends an enzyme-free wool detergent for all of it.";
  return null;
}

export function plan(items, washerIn, dryerIn, units) {
  const washer = washerIn || typical("washer", "front");
  const dryer = dryerIn || typical("dryer", "electric");
  const notForMachine = [];
  let groups = [];

  for (const it of items) {
    const s = st(it);
    if (s.dryClean === "only") { notForMachine.push(`${it.name} — dry clean only`); continue; }
    if (s.washCycle === "do_not_wash") { notForMachine.push(`${it.name} — do not wash`); continue; }
    const g = { care: careOf(it), colour: colourOf(it), hot: (s.maxWashTempC ?? 40) >= 50, towels: isTowel(it), items: [it], notes: [] };
    const same = groups.find((x) => x.care === g.care && x.colour === g.colour && x.hot === g.hot && x.towels === g.towels);
    if (same) same.items.push(it); else groups.push(g);
  }

  // Merge small groups into the closest compatible one, so the plan doesn't run lots of tiny loads.
  const cap = capacityKg(washer);
  for (;;) {
    const small = groups.map((g, i) => i).filter((i) => groupKg(groups[i]) < cap * target(groups[i]) * 0.4)
      .sort((x, y) => groupKg(groups[x]) - groupKg(groups[y]));
    let merged = false;
    for (const i of small) {
      let best = null;
      groups.forEach((g, j) => {
        if (j === i) return;
        const c = mergeCost(groups[i], g);
        if (c != null && (best == null || c < best[1])) best = [j, c];
      });
      if (!best) continue;
      const from = groups[i], into = { ...groups[best[0]], notes: [...groups[best[0]].notes] };
      const why = mergeNote(from, into);
      if (why) into.notes.push(why);
      into.items = [...into.items, ...from.items];
      if (from.care > into.care) into.care = from.care; // strictest care wins
      into.hot = into.hot && from.hot;
      into.towels = into.towels && from.towels;
      if (from.colour !== into.colour) into.colour = "colours";
      groups[best[0]] = into;
      groups.splice(i, 1);
      merged = true;
      break;
    }
    if (!merged) break;
  }

  // Split anything bigger than the drum should take.
  const split = [];
  for (const g of groups) {
    const limit = cap * target(g);
    let chunk = { ...g, items: [] };
    for (const it of [...g.items].sort((a, b) => weight(b) - weight(a))) {
      if (chunk.items.length && groupKg(chunk) + weight(it) > limit) {
        split.push(chunk);
        chunk = { ...g, items: [], notes: [] };
      }
      chunk.items.push(it);
    }
    if (chunk.items.length) split.push(chunk);
  }

  let loads = order(split.map((g) => buildLoad(g, washer, dryer, units)));

  // Number repeated titles: "Darks 1", "Darks 2".
  const titles = loads.map((l) => l.title);
  loads.forEach((l, i) => {
    if (titles.filter((t) => t === titles[i]).length > 1) l.title += ` ${titles.slice(0, i).filter((t) => t === titles[i]).length + 1}`;
  });

  let t = 0, dryerFree = 0;
  for (const l of loads) {
    t += l.washMinutes;
    if (l.dry.minutes > 0) dryerFree = Math.max(dryerFree, t) + l.dry.minutes;
  }
  const why = [];
  if (loads.length > 1) why.push("Washtag recommends this order so your dryer is busy while the next load washes: quick-washing, slow-drying loads go first and air-dry loads go last.");
  if (loads.some((l) => l.dry.dryerLoads > 1)) why.push("Your dryer holds less than a full wash, so Washtag recommends drying the bigger loads in two goes for even drying.");
  return { loads, notForMachine, totalMinutes: Math.max(t, dryerFree), orderWhy: why };
}

/** Johnson's rule for two machines in a row: it finishes the whole pile in the least time. */
function order(loads) {
  const first = loads.filter((l) => l.washMinutes < l.dry.minutes).sort((a, b) => a.washMinutes - b.washMinutes);
  const second = loads.filter((l) => l.washMinutes >= l.dry.minutes).sort((a, b) => b.dry.minutes - a.dry.minutes);
  return [...first, ...second];
}

function buildLoad(g, washer, dryer, units) {
  const c = combine(g.items, units);
  const kg = groupKg(g);
  const fill = kg / capacityKg(washer);
  const size = fill < 0.35 ? "small" : fill < 0.6 ? "medium" : fill < 0.85 ? "large" : "xl";
  const delicate = g.care >= CARE.gentle || ["gentle", "hand"].includes(c.cycle);
  const isFront = washer.type === "front";

  let want;
  if (c.cycle === "hand") want = g.care === CARE.wool ? ["wool", "hand", "delicate"] : ["hand", "wool", "delicate"];
  else if (c.cycle === "gentle") want = g.care === CARE.wool ? ["wool", "delicate", "gentle", "hand"] : ["delicate", "gentle"];
  else if (c.cycle === "permanent_press") want = ["perm", "synthetic", "easy care", "casual", "wrinkle"];
  else if (g.towels) want = ["towel", "bulky", "bedding", "heavy", "cotton", "normal"];
  else if (g.colour === "whites" && g.hot) want = ["white", "cotton", "normal"];
  else want = ["normal", "cotton", "everyday", "colou", "color"];
  const washCycle = machineCycle(washer.cycles, want) || CYCLE_NAME[c.cycle] || "Normal";

  const rpm = washer.maxSpinRpm;
  let spin;
  if (delicate) spin = "Low" + (rpm ? ` (about ${Math.min(rpm, 800)} rpm or less)` : "");
  else if (c.cycle === "permanent_press") spin = "Medium" + (rpm ? ` (about ${Math.min(rpm, 1000)} rpm)` : "") + " to limit creases";
  else spin = "High" + (rpm ? ` (up to ${rpm} rpm)` : "") + " so it dries faster";

  let washMinutes = { hand: 35, gentle: 40, permanent_press: 50 }[c.cycle] ?? (g.towels ? 65 : 55);
  if (isFront) washMinutes += 15;

  // Drying: items that can't tumble come out first; the rest share the strictest heat.
  const tumbleItems = g.items.filter((it) => it.care?.structured?.tumble !== "none");
  const tc = combine(tumbleItems, units);
  const speed = { heat_pump: 1.6, condenser: 1.3 }[dryer.type] ?? 1;
  let dryMinutes = 0, dryerLoads = 0, setting = "Nothing in this load goes in the dryer.";
  if (tumbleItems.length) {
    const tumbleKg = tumbleItems.reduce((s, it) => s + weight(it), 0);
    dryerLoads = Math.ceil(tumbleKg / (capacityKg(dryer) * 0.85));
    const low = tc.tumble === "low" || delicate;
    const w = low ? ["delicate", "low", "perm", "synthetic"] : g.towels ? ["towel", "heavy", "bulky", "normal"]
      : c.cycle === "permanent_press" ? ["perm", "synthetic", "casual", "normal"] : ["normal", "cotton", "regular"];
    const name = machineCycle(dryer.cycles, w) || (low ? "Delicates / low heat" : "Normal");
    const baseMin = low ? 35 : g.towels ? 60 : c.cycle === "permanent_press" ? 40 : 50;
    dryMinutes = Math.floor(baseMin * speed * Math.max(1, dryerLoads));
    setting = `${name} · ${low ? "low" : g.towels ? "high" : "medium"} heat` + (dryer.sensorDry === false ? `, timed about ${Math.floor(baseMin * speed)} min` : ", sensor dry");
    if (dryerLoads > 1) setting += ` · in ${dryerLoads} batches`;
  }

  const notes = [...g.notes];
  if (c.airDry.length && tumbleItems.length) notes.push("Washtag recommends pulling the air-dry items out before the rest go in the dryer.");
  if (g.colour === "darks") notes.push("Turn darks and jeans inside out and wash cold to keep the colour.");
  if (g.towels) notes.push("Skip fabric softener on towels — it makes them less absorbent.");
  if (delicate && washer.type === "top_agitator") notes.push("Your agitator can snag delicates — use a mesh laundry bag.");
  if (fill > 1) notes.push("This is more than your drum holds comfortably — split it if the clothes can't move freely.");
  notes.push(...c.conflicts);

  return { title: loadTitle(g), items: g.items, combined: c, kg, fill, size, delicate, washCycle, spin, washMinutes,
    dry: { tumbleNames: tumbleItems.map((it) => it.name), airDry: c.airDry, setting, minutes: dryMinutes, dryerLoads }, notes };
}

function loadTitle(g) {
  switch (g.care) {
    case CARE.hand: return "Hand wash";
    case CARE.wool: return "Wool & silk";
    case CARE.gentle: return "Delicates";
    case CARE.synthetic: return g.colour === "darks" ? "Dark synthetics" : "Synthetics & activewear";
    default:
      if (g.towels) return g.colour === "darks" ? "Dark towels & bedding" : "Towels & bedding";
      if (g.colour === "whites") return g.hot ? "Whites (hot)" : "Whites";
      if (g.colour === "darks") return "Darks";
      return g.hot ? "Colours (warm)" : "Colours";
  }
}
