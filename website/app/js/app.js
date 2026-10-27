// Washtag web app: Scan, Index, This load and Household, ported from the SwiftUI app.
// Everything renders from plain state into HTML strings; clicks and edits are handled
// by delegation on data-act / data-bind attributes.

import * as API from "./api.js";
import * as GTIN from "./gtin.js";
import * as Planner from "./planner.js";
import * as Appl from "./appliances.js";
import { careSymbol, symbolFor } from "./symbols.js";
import { store, newRecord, PERSON_COLORS } from "./store.js";
import { loadImage, jpegBase64, thumbnail } from "./image.js";
import { decodeImage, startLive, liveAvailable } from "./barcode.js";
import { lookup } from "./lookup.js";
import { ADSENSE } from "./config.js";

/* ---------- helpers ---------- */

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
const clone = (o) => JSON.parse(JSON.stringify(o));
const confWord = (v) => (v >= 80 ? "High" : v >= 55 ? "Medium" : "Low");
const confColor = (v) => (v >= 80 ? "var(--good)" : v >= 55 ? "var(--mid)" : "var(--low)");
const lowerFirst = (s) => s.charAt(0).toLowerCase() + s.slice(1);
const duration = (m) => (m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`);

const ICON = {
  tag: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M3.5 12.2V4.5a1 1 0 0 1 1-1h7.7l8.3 8.3a1.4 1.4 0 0 1 0 2l-6.2 6.2a1.4 1.4 0 0 1-2 0Z"/><circle cx="8" cy="8" r="1.6"/></svg>`,
  barcode: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6v12M7 6v12M10.5 6v12M13 6v12M17 6v12M20 6v12"/></svg>`,
  camera: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M3.5 8.5a2 2 0 0 1 2-2h2l1.5-2h6l1.5 2h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z"/><circle cx="12" cy="13" r="3.6"/></svg>`,
  photo: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="m4 17 5-5 4 4 2.5-2.5L20 18"/><circle cx="15.5" cy="9" r="1.5"/></svg>`,
  viewfinder: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16M8 9v6M11 9v6M14 9v6M16.5 9v6"/></svg>`,
  washer: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="4" y="3" width="16" height="18" rx="2.5"/><circle cx="12" cy="13" r="4.5"/><path d="M7 6.5h2" stroke-linecap="round"/></svg>`,
  nosign: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="8.5"/><path d="m6 6 12 12"/></svg>`,
};

/* ---------- UI state (everything not saved lives here) ---------- */

const ui = {
  route: "scan", itemId: null,
  scan: { mode: "label", img: null, imgURL: null, status: null, statusErr: false, busy: false, current: null, typed: "", run: 0 },
  detail: null,                       // working copy of the saved item being viewed
  recUI: {},                          // per record: { needs, suggesting, suggestError }
  index: { query: "", person: null },
  load: { mode: "load", suggestions: null, suggesting: false, suggestError: null },
  machines: { washer: null, dryer: null, looking: {}, error: {} },
  newPerson: "",
  installPrompt: null,
  stopLive: null,
};

const recUI = (id) => (ui.recUI[id] ||= { needs: [], suggesting: false, suggestError: null });

/* ---------- routing ---------- */

const TITLES = { scan: "Washtag", index: "Saved index", load: "This load", household: "Household", machines: "Washer & dryer" };

function readRoute() {
  const h = location.hash.replace(/^#/, "");
  const [r, id] = h.split("/");
  if (r === "item" && id && store.items.some((x) => x.id === id)) {
    if (ui.itemId !== id || !ui.detail) ui.detail = clone(store.items.find((x) => x.id === id));
    ui.route = "item"; ui.itemId = id;
  } else {
    ui.route = TITLES[r] ? r : "scan"; ui.itemId = null; ui.detail = null;
  }
  if (ui.route === "machines") { ui.machines.washer = null; ui.machines.dryer = null; ui.machines.error = {}; }
}

function go(hash) {
  if (location.hash === hash) { readRoute(); render(); } else location.hash = hash;
}

/* ---------- render ---------- */

function render() {
  const view = $("#view");
  const tab = ui.route === "item" ? "index" : ui.route === "machines" ? "household" : ui.route;
  document.querySelectorAll(".tabs a").forEach((a) => {
    if (a.dataset.tab === tab) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
  });
  $("#back").hidden = !(ui.route === "item" || ui.route === "machines");
  $("#title").textContent = ui.route === "item" ? (ui.detail?.name || "Item") : TITLES[ui.route];
  document.title = ui.route === "scan" ? "Washtag" : `${$("#title").textContent} · Washtag`;

  // Keep focus and caret in a text box across re-renders.
  const a = document.activeElement;
  const keep = a && a.dataset?.bind ? { bind: a.dataset.bind, start: a.selectionStart, end: a.selectionEnd } : null;

  const html = { scan: viewScan, index: viewIndex, item: viewItem, load: viewLoad, household: viewHousehold, machines: viewMachines }[ui.route]();
  view.innerHTML = installBanner() + (store.saveError ? `<div class="warn">${esc(store.saveError)}</div>` : "") + html;

  if (keep) {
    const el = view.querySelector(`[data-bind="${CSS.escape(keep.bind)}"]`);
    if (el) { el.focus(); try { el.setSelectionRange(keep.start, keep.end); } catch { /* number inputs */ } }
  }
  if (ui.route === "scan") mountAd();
}

/* ---------- Scan ---------- */

function viewScan() {
  const s = ui.scan;
  const label = s.mode === "label";
  return `
  <div class="modes" role="group" aria-label="Scan mode">
    <button type="button" data-act="mode" data-v="label" aria-pressed="${label}">${ICON.tag}<b>Care symbols</b><span>Photo of a wash label</span></button>
    <button type="button" data-act="mode" data-v="upc" aria-pressed="${!label}">${ICON.barcode}<b>UPC / barcode</b><span>Look up the product</span></button>
  </div>
  <p class="small muted">${label
    ? "Photograph the care label flat and in focus. If the symbols sit next to a barcode, keep both in frame — Washtag reads both."
    : "Point the camera at the barcode, photograph it straight on, or type the numbers."}</p>
  <div class="photo">
    ${s.imgURL ? `<img src="${s.imgURL}" alt="Your photo">` : `<b>${label ? "Add a photo of the label" : "Add a photo of the barcode"}</b>`}
    <div class="row" style="justify-content:center">
      <button class="btn primary" type="button" data-act="camera">${ICON.camera}Take photo</button>
      <button class="btn" type="button" data-act="pick">${ICON.photo}Choose photo</button>
    </div>
    ${!label && liveAvailable() ? `<button class="btn" type="button" data-act="live">${ICON.viewfinder}Scan live with camera</button>` : ""}
  </div>
  ${!label ? manualEntry() : ""}
  <div class="row">
    <button class="btn primary" type="button" data-act="scan" ${!s.img || s.busy ? "disabled" : ""}>${label ? "Read label" : "Read barcode"}</button>
    ${s.busy ? `<button class="btn" type="button" data-act="stop">Stop</button>` : ""}
  </div>
  ${s.status ? `<div class="status ${s.statusErr ? "err" : ""}" role="status">${s.busy ? `<span class="spin" aria-hidden="true"></span>` : ""}<span>${esc(s.status)}</span></div>` : ""}
  ${s.current ? recordView(s.current, "scan") : ""}
  <div class="ad-slot" id="ad"></div>`;
}

function manualEntry() {
  const v = ui.scan.typed.replace(/\D/g, "");
  let hint = "";
  if (v) {
    const ok = GTIN.isValid(v);
    hint = `<p class="tiny ${ok === false ? "bad" : "muted"}" id="typed-hint">${ok == null ? `${v.length} digits — UPC is 12, EAN is 13 or 8`
      : ok ? `✓ Valid ${GTIN.type(v)} check digit` : "✕ Check digit doesn’t match — recheck the numbers"}</p>`;
  } else hint = `<p class="tiny muted" id="typed-hint"></p>`;
  return `<form class="panel" data-form="typed">
    <h2><label for="typed">Or type the number under the barcode</label></h2>
    <div class="row" style="flex-wrap:nowrap">
      <input type="text" id="typed" inputmode="numeric" autocomplete="off" placeholder="e.g. 012345678905" data-bind="scan.typed" value="${esc(ui.scan.typed)}">
      <button class="btn" type="submit">Look up</button>
    </div>
    ${hint}
  </form>`;
}

function setStatus(text, err = false) {
  ui.scan.status = text; ui.scan.statusErr = err;
  render();
}

/** Runs one scan job; Stop or a newer job makes the old one's results drop on the floor. */
async function run(work) {
  const id = ++ui.scan.run;
  ui.scan.busy = true; ui.scan.current = null;
  render();
  const alive = () => ui.scan.run === id;
  try {
    await work(alive);
    if (alive()) ui.scan.status = null;
  } catch (e) {
    if (alive()) { ui.scan.status = e.message || "Something went wrong."; ui.scan.statusErr = true; }
  }
  if (alive()) { ui.scan.busy = false; render(); }
}

async function scanPhoto() {
  const img = ui.scan.img;
  if (!img) return;
  if (ui.scan.mode === "label") await run((alive) => runLabel(img, alive));
  else await run((alive) => runUPCPhoto(img, alive));
}

async function runLabel(img, alive) {
  setStatus("Reading the label… this usually takes 5–20 seconds.");
  const decoded = decodeImage(img);
  const care = await API.readLabel(jpegBase64(img));
  const bars = await decoded;
  if (!alive()) return;
  const rec = newRecord("label");
  rec.thumbnail = thumbnail(img);
  rec.care = care;
  rec.name = care.suggestedName || care.product?.name || "Unnamed item";
  const visual = care.barcode?.present === true ? GTIN.digitsOnly(care.barcode?.digits) : null;
  ui.scan.current = rec;
  if (bars || visual) {
    rec.upc = GTIN.build({ decoded: bars, visual, visualConfidence: care.barcode?.confidence });
    setStatus("Found a barcode beside the symbols — looking up the product…");
    const context = [care.product?.type, care.labelText?.fibres, care.product?.brand].filter(Boolean).join(" ");
    const product = await lookup(rec.upc.code, context);
    if (!alive()) return;
    rec.product = product;
  }
}

async function runUPCPhoto(img, alive) {
  setStatus("Looking for a barcode in the photo…");
  const decoded = await decodeImage(img);
  if (!alive()) return;
  setStatus("Reading the printed digits to double-check…");
  let printed = null;
  try { printed = await API.readDigits(jpegBase64(img)); } catch { printed = null; }
  if (!alive()) return;
  const visual = GTIN.digitsOnly(printed?.digits);
  if (!decoded && !visual) throw new Error("No barcode found in that photo. Get closer, keep it straight on with the numbers visible, or type the numbers.");
  const rec = newRecord("upc");
  rec.thumbnail = thumbnail(img);
  rec.upc = GTIN.build({ decoded, visual, visualConfidence: printed?.confidence });
  ui.scan.current = rec;
  setStatus("Looking up the product…");
  const product = await lookup(rec.upc.code, null);
  if (!alive()) return;
  rec.product = product;
  rec.name = product.productName || product.brand || `Item ${rec.upc.code}`;
}

async function lookUpCode(code, via) {
  const digits = String(code).replace(/\D/g, "");
  if (!digits) { setStatus("Type the digits under the barcode first.", true); return; }
  await run(async (alive) => {
    const rec = newRecord("upc");
    rec.upc = via === "typed" ? GTIN.build({ typed: digits }) : GTIN.build({ decoded: digits });
    rec.name = `Item ${digits}`;
    ui.scan.current = rec;
    setStatus("Looking up the product…");
    const product = await lookup(rec.upc.code, null);
    if (!alive()) return;
    rec.product = product;
    rec.name = product.productName || product.brand || rec.name;
  });
}

async function setPhoto(file) {
  if (!file) return;
  try {
    const img = await loadImage(file);
    if (ui.scan.imgURL) URL.revokeObjectURL(ui.scan.imgURL);
    ui.scan.img = img; ui.scan.imgURL = img.src;
    ui.scan.current = null; ui.scan.status = null;
    ui.scan.run++; ui.scan.busy = false;
  } catch (e) {
    ui.scan.status = e.message; ui.scan.statusErr = true;
  }
  render();
}

async function openLive() {
  const box = $("#live");
  box.hidden = false;
  try {
    ui.stopLive = await startLive($("#live-video"), (code) => {
      closeLive();
      lookUpCode(code, "decoded");
    });
  } catch (e) {
    closeLive();
    setStatus(e?.name === "NotAllowedError" ? "Camera access was blocked. Allow the camera for this site in your browser settings, or take a photo instead." : "The camera couldn't start. Take a photo instead.", true);
  }
}

function closeLive() {
  ui.stopLive?.();
  ui.stopLive = null;
  $("#live").hidden = true;
}

/* ---------- One record: care tag, confidence, product, suggestions, save ---------- */

function recordView(rec, where) {
  return `<section class="rec" aria-label="Result" style="display:flex;flex-direction:column;gap:14px">
    ${rec.care ? careTag(rec) : ""}
    ${confidencePanel(rec)}
    ${rec.upc ? productPanel(rec) : ""}
    ${rec.care ? suggestionsPanel(rec, where) : ""}
    ${savePanel(rec, where)}
  </section>`;
}

function careTag(rec) {
  const care = rec.care;
  const symbols = (care.symbols || []).slice(0, 20);
  const sec = care.sections || {};
  if (care.symbolsFound === false && !symbols.length) {
    return `<div class="tag"><div class="stitch"></div><h2>No care symbols found</h2>
      <p class="muted">${esc(care.qualityNotes || "Try again with the label flat, well lit and filling most of the photo.")}</p></div>`;
  }
  const sub = [care.labelText?.fibres, care.product?.type].filter(Boolean).join(" — ");
  const section = (title, lines, fg, bg, icon, first, danger) => `
    ${first ? "" : `<div class="dash"></div>`}
    <div class="sec-h"><span class="ic" style="color:${fg};background:${bg}">${icon}</span>${title}</div>
    ${lines?.length ? `<ul class="lines ${danger ? "no" : ""}">${lines.map((l) => `<li><span>${esc(l)}</span></li>`).join("")}</ul>`
      : `<p class="small muted">Nothing on the label for this.</p>`}`;
  const other = care.labelText?.other;
  const lang = care.labelText?.language || "";
  return `<div class="tag">
    <div class="stitch"></div>
    <h2>${esc(rec.name || "Care label")}</h2>
    ${sub ? `<p class="tiny muted">${esc(sub)}</p>` : ""}
    ${section("Wash", sec.wash, "var(--tub)", "var(--tub-soft)", careSymbol({ category: "wash", tempLabel: "~" }), true)}
    ${section("Dry", sec.dry, "var(--dry)", "var(--dry-soft)", careSymbol({ category: "dry", code: "tumble" }))}
    ${section("Iron, bleach &amp; cleaning", sec.care, "var(--care)", "var(--care-soft)", careSymbol({ category: "iron", code: "medium" }))}
    ${section("Do not", sec.doNot, "var(--stop)", "var(--stop-soft)", ICON.nosign, false, true)}
    <div class="dash"></div>
    <h3 class="h">Symbols read</h3>
    <div class="syms">${symbols.map((s) => {
      const c = s.confidence ?? 0;
      return `<div class="symc">${symbolFor(s)}<div>${esc(s.meaning)}<br><span class="tiny" style="color:${confColor(c)}">${confWord(c)} confidence · ${Math.round(c)}%</span></div></div>`;
    }).join("")}</div>
    ${other ? `<p class="small"><b>Other text on label:</b> ${esc(other)}${!lang || lang.toLowerCase().includes("english") ? "" : ` (translated from ${esc(lang)})`}</p>` : ""}
  </div>`;
}

function bar(label, value) {
  const v = Math.max(0, Math.min(100, Math.round(value)));
  return `<div class="bar" role="img" aria-label="${esc(label)}: ${v} percent, ${confWord(v)}">
    <div class="k"><span>${esc(label)}</span><span>${confWord(v)} · ${v}%</span></div>
    <div class="t"><i style="width:${v}%;background:${confColor(v)}"></i></div></div>`;
}

function confidencePanel(rec) {
  const checks = [];
  if (rec.care) checks.push([rec.care.imageQuality === "good" ? "✓" : "!", `Photo quality: ${rec.care.imageQuality || "unknown"}${rec.care.qualityNotes ? ` — ${rec.care.qualityNotes}` : ""}`]);
  const u = rec.upc;
  if (u) {
    checks.push([u.checksum === true ? "✓" : u.checksum === false ? "✕" : "?",
      u.checksum === true ? `${u.type} check digit is valid` : u.checksum === false ? "Check digit doesn’t match — some digits are probably misread" : "Not a standard UPC/EAN length"]);
    checks.push([u.via === "on-device decoder" ? "✓" : "·", `Digits ${u.via}`]);
    if (u.agree === true) checks.push(["✓", "Decoded bars and printed numbers agree"]);
    if (u.agree === false) checks.push(["✕", `Bars read ${u.code} but printed digits look like ${u.visualDigits || ""}`]);
  }
  if (rec.product?.basis) checks.push(["·", rec.product.basis]);
  const p = rec.product;
  return `<div class="panel"><h2>How sure Washtag is</h2>
    ${rec.care ? bar("Label reading", rec.care.overallConfidence ?? 0) : ""}
    ${u ? bar("Barcode digits", u.readConfidence) : ""}
    ${p ? bar("Product match", p.found ? (p.confidence ?? 0) : Math.min(p.confidence ?? 0, 30)) : ""}
    <ul class="checks">${checks.map(([m, t]) => `<li><b>${m}</b><span>${esc(t)}</span></li>`).join("")}</ul>
    ${rec.care?.recheck?.length ? `<div class="note"><b>Double-check on the label:</b> ${esc(rec.care.recheck.join("; "))}</div>` : ""}
  </div>`;
}

function productPanel(rec) {
  const u = rec.upc, p = rec.product;
  let body = "";
  if (!p) body = `<div class="row"><span class="spin" aria-hidden="true"></span><span class="muted">Looking up…</span></div>`;
  else if (!p.found) body = `<p><b>Not found in the product database.</b> ${p.gs1Region ? `The code prefix is registered in ${esc(p.gs1Region)}. ` : ""}Use the links below to search elsewhere.</p>`;
  else {
    const meta = [p.category, p.material, p.manufacturer && p.manufacturer !== p.brand ? `Made by ${p.manufacturer}` : null, p.gs1Region ? `Registered in ${p.gs1Region}` : null].filter(Boolean);
    body = `<div class="prod">${p.imageURL ? `<img src="${esc(p.imageURL)}" alt="" loading="lazy" referrerpolicy="no-referrer">` : ""}
        <div><b>${esc(p.productName || "Unnamed product")}</b>${p.brand ? `<br><span class="muted">${esc(p.brand)}</span>` : ""}</div></div>
      ${p.description ? `<p class="small">${esc(p.description)}</p>` : ""}
      ${meta.length ? `<p class="tiny muted">${esc(meta.join(" · "))}</p>` : ""}
      ${p.careNotes?.length ? `<ul class="b small">${p.careNotes.map((n) => `<li>${esc(n)}</li>`).join("")}</ul>` : ""}
      ${p.detergentUse?.isLaundryProduct && p.detergentUse?.typicalDoseNote ? `<div class="note"><b>Dosing:</b> ${esc(p.detergentUse.typicalDoseNote)}</div>` : ""}
      ${p.stores?.some((s) => s.link) ? `<b class="small">Where to buy</b>${p.stores.filter((s) => s.link).map((s) =>
        `<a class="small" href="${esc(s.link)}" target="_blank" rel="noopener noreferrer">${esc(s.name || "Store")}${s.price ? ` · ${esc(s.price)}` : ""} ↗</a>`).join("")}` : ""}`;
  }
  const links = [];
  const brand = p?.brand || rec.care?.product?.brand;
  const name = p?.productName || rec.care?.product?.name || "";
  const q = encodeURIComponent;
  if (brand) links.push(["Manufacturer care info", `https://www.google.com/search?q=${q(`${brand} ${name} care instructions`)}`]);
  if (u?.code) {
    links.push(["UPCitemdb", `https://www.upcitemdb.com/upc/${u.code}`]);
    links.push(["Open Products Facts", `https://world.openproductsfacts.org/product/${u.code}`]);
    links.push(["Web search", `https://www.google.com/search?q=${u.code}`]);
  }
  const src = p?.source || "";
  const credit = src === "upcitemdb" ? "Product data from UPCitemdb."
    : src.includes("openproductsfacts") ? "Product data from Open Products Facts (ODbL)."
    : src.includes("openbeautyfacts") ? "Product data from Open Beauty Facts (ODbL)."
    : src.includes("openfoodfacts") ? "Product data from Open Food Facts (ODbL)." : "Searched UPCitemdb and the Open Facts databases.";
  return `<div class="panel"><h2>Product details</h2>
    ${u ? `<p class="tiny muted mono">Barcode ${esc(u.code)} · ${esc(u.type)}</p>` : ""}
    ${body}
    <div class="row">${links.map(([t, h]) => `<a class="ext" href="${esc(h)}" target="_blank" rel="noopener noreferrer">${t} ↗</a>`).join("")}</div>
    <p class="tiny muted">${credit}</p>
  </div>`;
}

function suggestionsList(s) {
  return `<div style="display:flex;flex-direction:column;gap:10px">
    ${(s.suggestions || []).map((x) => `<div><b>${esc(x.type)}</b>
      ${x.why ? `<p class="small">${esc(x.why)}</p>` : ""}
      ${x.examples?.length ? `<p class="tiny muted">Examples: ${esc(x.examples.join(", "))}</p>` : ""}
      ${x.howMuch ? `<p class="tiny">${esc(x.howMuch)}</p>` : ""}</div>`).join("")}
    ${s.avoid?.length ? `<b class="bad">Avoid</b>${s.avoid.map((x) => `<p class="small"><b>${esc(x.what)}</b> — ${esc(x.why)}</p>`).join("")}` : ""}
  </div>`;
}

function needChips(selected, act, where) {
  return `<div class="chips">${Planner.NEEDS.map(([k, l]) =>
    `<button type="button" class="chip" data-act="${act}" data-v="${k}" data-where="${where}" aria-pressed="${selected.includes(k)}">${l}</button>`).join("")}</div>`;
}

function suggestionsPanel(rec, where) {
  const r = recUI(rec.id);
  return `<div class="panel"><h2>Product suggestions</h2>
    <p class="tiny muted">Based on this label. Pick any needs that apply.</p>
    ${needChips(r.needs, "rec-need", where)}
    <div><button class="btn" type="button" data-act="rec-suggest" data-where="${where}" ${r.suggesting ? "disabled" : ""}>
      ${r.suggesting ? `<span class="spin" aria-hidden="true"></span>Thinking…` : rec.suggestions ? "Refresh suggestions" : "Get suggestions"}</button></div>
    ${r.suggestError ? `<p class="small muted">${esc(r.suggestError)}</p>` : ""}
    ${rec.suggestions ? suggestionsList(rec.suggestions) : ""}
  </div>`;
}

function savePanel(rec, where) {
  const saved = store.isSaved(rec.id);
  return `<div class="panel"><h2>${saved ? "Saved to your index" : "Save to your index"}</h2>
    <label class="sr" for="name-${where}">Name</label>
    <input type="text" id="name-${where}" placeholder="Name" data-bind="${where}.name" value="${esc(rec.name)}" maxlength="80">
    <b class="small">Belongs to</b>
    ${store.people.length ? `<div class="chips">${store.people.map((p) =>
      `<button type="button" class="chip" data-act="rec-person" data-v="${p.id}" data-where="${where}" aria-pressed="${(rec.people || []).includes(p.id)}"><span class="dot" style="background:${PERSON_COLORS[p.colorIndex % PERSON_COLORS.length]}"></span>${esc(p.name)}</button>`).join("")}</div>`
      : `<p class="tiny muted">Add people in <a href="#household">Household</a> to label items.</p>`}
    <label class="sr" for="notes-${where}">Notes</label>
    <textarea id="notes-${where}" placeholder="Notes, e.g. shrinks if too warm" data-bind="${where}.notes" rows="2">${esc(rec.notes)}</textarea>
    <div class="row">
      <button class="btn primary" type="button" data-act="rec-save" data-where="${where}">${saved ? "Save changes" : "Save to index"}</button>
      ${rec.care ? `<button class="btn" type="button" data-act="rec-load" data-where="${where}">Plan a load with this</button>` : ""}
    </div>
  </div>`;
}

const recAt = (where) => (where === "scan" ? ui.scan.current : ui.detail);

async function recSuggest(where) {
  const rec = recAt(where);
  if (!rec) return;
  const r = recUI(rec.id);
  r.suggesting = true; r.suggestError = null;
  render();
  try {
    rec.suggestions = await API.suggest(rec.care?.structured || null, r.needs.map(Planner.needLabel), rec.care?.labelText?.fibres || null, rec.care?.product?.type || null);
    if (store.isSaved(rec.id)) store.upsert(clone(rec));
  } catch (e) { r.suggestError = e.message; }
  r.suggesting = false;
  render();
}

/* ---------- Index ---------- */

function itemRow(r, { link = true } = {}) {
  const owners = (r.people || []).map((id) => store.person(id)).filter(Boolean);
  const sub = owners.length
    ? `<span class="owners">${owners.map((p) => `<span><span class="dot" style="width:9px;height:9px;background:${PERSON_COLORS[p.colorIndex % PERSON_COLORS.length]}"></span>${esc(p.name)}</span>`).join("")}</span>`
    : `<span class="tiny muted">${r.upc ? `Barcode ${esc(r.upc.code)}` : new Date(r.createdAt).toLocaleDateString(undefined, { dateStyle: "medium" })}</span>`;
  const inner = `<span class="thumb">${r.thumbnail ? `<img src="${r.thumbnail}" alt="">` : careSymbol({ category: r.mode === "upc" ? "other" : "wash" })}</span>
    <span class="meta"><b>${esc(r.name || "Unnamed")}</b>${sub}
      <span class="minisyms">${(r.care?.symbols || []).slice(0, 5).map(symbolFor).join("")}</span></span>`;
  return link ? `<a class="item" href="#item/${r.id}">${inner}<span class="chev" aria-hidden="true">›</span></a>` : inner;
}

function viewIndex() {
  const q = ui.index.query.trim().toLowerCase();
  const person = ui.index.person;
  const list = store.items.filter((r) => (!person || (r.people || []).includes(person))
    && (!q || [r.name, r.notes, r.upc?.code, r.product?.brand, r.product?.productName, r.care?.labelText?.fibres, r.care?.product?.type]
      .some((x) => x && x.toLowerCase().includes(q))));
  return `
  <label class="sr" for="q">Search</label>
  <input type="search" id="q" placeholder="Search by name, brand, fabric or code" data-bind="index.query" value="${esc(ui.index.query)}">
  ${store.people.length ? `<div class="chips">
    <button type="button" class="chip" data-act="filter" data-v="" aria-pressed="${!person}">Everyone</button>
    ${store.people.map((p) => `<button type="button" class="chip" data-act="filter" data-v="${p.id}" aria-pressed="${person === p.id}"><span class="dot" style="background:${PERSON_COLORS[p.colorIndex % PERSON_COLORS.length]}"></span>${esc(p.name)}</button>`).join("")}
  </div>` : ""}
  <div id="index-list">${indexList(list)}</div>`;
}

function indexList(list) {
  if (!list.length) return `<p class="empty">${store.items.length ? "Nothing matches that search." : "Your index is empty. Scan a label, then tap “Save to index”."}</p>`;
  return `<div class="list">${list.map((r) => itemRow(r)).join("")}</div>`;
}

function viewItem() {
  return `${recordView(ui.detail, "detail")}
    <div><button class="btn danger" type="button" data-act="delete-item">Delete from index</button></div>`;
}

/* ---------- This load ---------- */

function machinesSummary() {
  const w = store.washer, d = store.dryer;
  return `<a class="machines" href="#machines">${ICON.washer}
    <span style="flex:1;min-width:0"><b>Your washer &amp; dryer</b><br>
    <span class="tiny muted">${!w && !d ? "Add your models so Washtag recommends settings for your machines."
      : esc([w && `Washer: ${Appl.title(w)}`, d && `Dryer: ${Appl.title(d)}`].filter(Boolean).join(" · "))}</span></span>
    <span class="chev" aria-hidden="true">›</span></a>`;
}

function seg(path, options, value) {
  return `<div class="seg" role="group">${options.map(([v, l]) =>
    `<button type="button" data-act="set" data-path="${path}" data-v="${v}" aria-pressed="${value === v}">${l}</button>`).join("")}</div>`;
}

function viewLoad() {
  const L = store.load;
  const withCare = store.items.filter((r) => r.care?.structured);
  const items = withCare.filter((r) => L.ids.includes(r.id));
  const sort = ui.load.mode === "sort";
  return `
  ${machinesSummary()}
  ${seg("ui.load.mode", [["sort", "Sort my laundry"], ["load", "One load"]], ui.load.mode)}
  <p class="small muted">${sort
    ? "Pick everything in the basket. Washtag sorts it into loads, picks the order to run them, and matches cycles to your machines."
    : "Pick what’s going in the machine. Washtag uses the strictest label in the pile and works out how much detergent to use."}</p>
  <div class="panel" style="padding:0;gap:0">
    <div class="row" style="padding:14px 14px 8px;justify-content:space-between">
      <h2 class="h">${sort ? "In the basket" : "Items in this load"}</h2>
      <span class="row" style="gap:14px">${sort ? `<button class="link" type="button" data-act="load-all">All</button>` : ""}<button class="link" type="button" data-act="load-clear">Clear</button></span>
    </div>
    ${!withCare.length ? `<p class="small muted" style="padding:0 14px 14px">Save a few scanned labels to plan a mixed load. You can still work out a detergent amount below.</p>` : ""}
    ${withCare.map((r) => `<label class="check"><input type="checkbox" data-act="load-toggle" data-v="${r.id}" ${L.ids.includes(r.id) ? "checked" : ""}><span class="item" style="padding:0;border:0">${itemRow(r, { link: false })}</span></label>`).join("")}
  </div>
  ${sort ? `<div class="panel"><h2>Detergent</h2>
      ${seg("load.form", [["liquid", "Liquid"], ["powder", "Powder"], ["pod", "Pods"]], L.form)}
      ${seg("load.water", [["soft", "Soft water"], ["medium", "Average"], ["hard", "Hard water"], ["unknown", "Not sure"]], L.water)}
    </div>${sortPlan(items)}`
    : `${aboutLoad()}${loadPlan(items)}
    <div class="panel"><h2>Products for this load</h2>
      <p class="tiny muted">Suggestions based on the combined labels and the needs you picked.</p>
      <div><button class="btn" type="button" data-act="load-suggest" ${ui.load.suggesting ? "disabled" : ""}>${ui.load.suggesting ? `<span class="spin" aria-hidden="true"></span>Thinking…` : "Get suggestions"}</button></div>
      ${ui.load.suggestError ? `<p class="small muted">${esc(ui.load.suggestError)}</p>` : ""}
      ${ui.load.suggestions ? suggestionsList(ui.load.suggestions) : ""}
    </div>`}`;
}

function aboutLoad() {
  const L = store.load, w = store.washer;
  return `<div class="panel"><h2>About the load</h2>
    <div class="field"><span class="lbl">Load size</span>${seg("load.size", [["small", "Small"], ["medium", "Medium"], ["large", "Large"], ["xl", "Extra large"]], L.size)}</div>
    <div class="field"><span class="lbl">How dirty</span>${seg("load.soil", [["light", "Light"], ["normal", "Normal"], ["heavy", "Heavy / stained"]], L.soil)}</div>
    <div class="field"><span class="lbl">Water</span>${seg("load.water", [["soft", "Soft"], ["medium", "Average"], ["hard", "Hard"], ["unknown", "Not sure"]], L.water)}</div>
    <div class="field"><span class="lbl">Machine</span>${w ? `<p class="small">${esc(Appl.title(w))} · ${Appl.isHE(w) ? "HE detergent" : "standard detergent"}</p>`
      : seg("load.machine", [["he", "HE / front loader"], ["standard", "Standard top loader"]], L.machine)}</div>
    <div class="field"><span class="lbl">Detergent</span>${seg("load.form", [["liquid", "Liquid"], ["powder", "Powder"], ["pod", "Pods"]], L.form)}</div>
    <div class="field"><span class="lbl">Needs</span>${needChips(L.needs, "load-need", "load")}</div>
  </div>`;
}

const BLEACH = { any: "Any bleach allowed if needed", non_chlorine: "Oxygen / non-chlorine only", none: "No bleach" };
const IRON = { none: "Don’t iron at least one item", low: "Low heat (up to 110°C / 230°F)", medium: "Medium heat (up to 150°C / 300°F)", high: "High heat (up to 200°C / 390°F)" };
const kv = (rows) => `<dl class="kv">${rows.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join("")}</dl>`;
const bullets = (title, lines) => `<div><b>${title}</b><ul class="b">${lines.map((l) => `<li>${esc(l)}</li>`).join("")}</ul></div>`;

/** The washer's own cycle name when we know the model, otherwise the generic one. */
function machineCycleName(c) {
  const generic = Planner.CYCLE_NAME[c.cycle] || c.cycle;
  const want = { hand: ["hand", "wool", "delicate"], gentle: ["delicate", "gentle"], permanent_press: ["perm", "synthetic", "casual"] }[c.cycle] || ["normal", "cotton"];
  const w = store.washer;
  const name = w && Planner.machineCycle(w.cycles, want);
  return name ? `${name} on your ${Appl.title(w)}` : generic;
}

function loadPlan(items) {
  const L = { ...store.load };
  if (store.washer) L.machine = Appl.isHE(store.washer) ? "he" : "standard";
  const units = store.units;
  const c = Planner.combine(items, units);
  const delicate = ["gentle", "hand"].includes(c.cycle) || L.needs.includes("wool");
  const d = Planner.dose(L, delicate, units);
  const warn = [...c.noMachine.map((n) => `${n} must not be washed — take it out of this load.`), ...c.dryCleanOnly.map((n) => `${n} is dry clean only — take it out of this load.`)];
  const extra = Planner.extras(c, L);
  const drying = (c.tumble === "none" ? "No tumble drying for at least one item." : c.tumble === "low" ? "Tumble on low heat." : "Tumble dry normal is fine.")
    + (c.airDry.length ? "\n" + c.airDry.map((x) => `• ${x}`).join("\n") : "");
  return `<div class="plan" aria-live="polite">
    <h2>${items.length ? `Washtag recommends for these ${plural(items.length, "item")}` : "Detergent for this load"}</h2>
    ${warn.length ? `<div class="warn"><b>Remove first:</b> ${esc(warn.join(" "))}</div>` : ""}
    <div class="dose"><b>${esc(d.amount)}</b><span style="font-weight:700">${esc(d.unit)}</span></div>
    <p class="tiny muted">${esc(d.detail)}. A starting point for a standard-concentration detergent — if its cap or scoop markings differ, follow them.</p>
    <hr>
    ${kv([
      ["Temperature", Planner.tempAdvice(c, L, units)],
      ["Cycle", machineCycleName(c) + (delicate && c.cycle !== "hand" ? " — use a delicate detergent" : "")],
      ["Bleach", BLEACH[c.bleach] || c.bleach],
      ["Drying", drying],
      ...(c.ironMax ? [["Ironing", IRON[c.ironMax] || c.ironMax]] : []),
    ])}
    ${c.conflicts.length ? bullets("Watch out", c.conflicts) : ""}
    ${extra.length ? bullets("For your needs", extra) : ""}
  </div>`;
}

function sortPlan(items) {
  if (!items.length) return `<p class="small muted">Pick some items above and Washtag recommends how to split them into loads.</p>`;
  const units = store.units;
  const p = Planner.plan(items, store.washer, store.dryer, units);
  return `<div style="display:flex;flex-direction:column;gap:8px" aria-live="polite">
      <h2 class="h" style="font-size:21px;font-weight:800">Washtag recommends ${plural(p.loads.length, "load")}</h2>
      ${p.totalMinutes > 0 ? `<p class="small muted">About ${duration(p.totalMinutes)} from first wash to last dry.</p>` : ""}
      ${p.orderWhy.map((w) => `<p class="small muted">${esc(w)}</p>`).join("")}
      ${!store.washer || !store.dryer ? `<p class="tiny muted">Using typical machine specs — <a href="#machines">add your washer and dryer</a> for settings that match them.</p>` : ""}
    </div>
    ${p.notForMachine.length ? `<div class="warn"><b>Keep out of the machine:</b> ${esc(p.notForMachine.join("; "))}.</div>` : ""}
    ${p.loads.map((l, i) => loadCard(i + 1, p.loads.length, l)).join("")}`;
}

function loadCard(n, total, l) {
  const L = { ...store.load, size: l.size };
  if (store.washer) L.machine = Appl.isHE(store.washer) ? "he" : "standard";
  const d = Planner.dose(L, l.delicate, store.units);
  return `<section class="plan" aria-label="Load ${n} of ${total}: ${esc(l.title)}">
    <div class="loadn"><b>${n}</b><div><b>${esc(l.title)}</b><br><span class="tiny muted">${plural(l.items.length, "item")} · about ${Math.round(Math.min(l.fill, 1.5) * 100)}% of the drum</span></div></div>
    <p class="small">${esc(l.items.map((it) => it.name).join(", "))}</p>
    <hr>
    ${kv([
      ["Wash", `${l.washCycle} · ${lowerFirst(Planner.tempAdvice(l.combined, store.load, store.units))}`],
      ["Spin", l.spin],
      ["Detergent", `${d.amount} ${d.unit}` + (l.delicate ? " of a gentle, enzyme-free detergent" : "")],
      ["Bleach", { any: "Any bleach if needed", non_chlorine: "Oxygen / non-chlorine only", none: "No bleach" }[l.combined.bleach] || l.combined.bleach],
      ["Dry", l.dry.setting + (l.dry.airDry.length ? "\n" + l.dry.airDry.map((x) => `• ${x}`).join("\n") : "")],
    ])}
    ${l.notes.length ? bullets("Washtag recommends", l.notes) : ""}
    <div><button class="btn" type="button" data-act="open-load" data-v="${esc(l.items.map((it) => it.id).join(","))}" data-size="${l.size}">Open as this load</button></div>
  </section>`;
}

async function loadSuggest() {
  const items = store.items.filter((r) => r.care?.structured && store.load.ids.includes(r.id));
  const c = Planner.combine(items, store.units);
  ui.load.suggesting = true; ui.load.suggestError = null;
  render();
  try {
    ui.load.suggestions = await API.suggest({ maxWashTempC: c.maxTemp, washCycle: c.cycle, bleach: c.bleach, tumble: c.tumble },
      store.load.needs.map(Planner.needLabel), items.map((r) => r.care?.labelText?.fibres).filter(Boolean).join("; "), items.map((r) => r.name).join(", "));
  } catch (e) { ui.load.suggestError = e.message; }
  ui.load.suggesting = false;
  render();
}

/* ---------- Household ---------- */

function viewHousehold() {
  const w = store.washer, d = store.dryer;
  return `
  <form class="panel" data-form="person"><h2><label for="newp">Add a person</label></h2>
    <div class="row" style="flex-wrap:nowrap">
      <input type="text" id="newp" placeholder="Name, e.g. Asha or Kids" data-bind="newPerson" value="${esc(ui.newPerson)}" maxlength="40" autocomplete="off">
      <button class="btn" type="submit">Add</button>
    </div></form>
  <div class="panel"><h2>People</h2>
    ${!store.people.length ? `<p class="muted">No one added yet.</p>` : store.people.map((p) => {
      const n = store.items.filter((r) => (r.people || []).includes(p.id)).length;
      return `<div class="row" style="justify-content:space-between;flex-wrap:nowrap">
        <span class="row" style="gap:8px;min-width:0"><span class="dot" style="width:12px;height:12px;background:${PERSON_COLORS[p.colorIndex % PERSON_COLORS.length]}"></span><b>${esc(p.name)}</b><span class="tiny muted">${plural(n, "item")}</span></span>
        <button class="link" type="button" data-act="remove-person" data-v="${p.id}">Remove</button></div>`;
    }).join("")}
  </div>
  <a class="machines" href="#machines">${ICON.washer}<span style="flex:1;min-width:0"><b>Washer &amp; dryer</b><br>
    <span class="tiny muted">${esc([w && Appl.title(w), d && Appl.title(d)].filter(Boolean).join(" · ") || "Not added")}</span></span><span class="chev" aria-hidden="true">›</span></a>
  <div class="panel"><h2>Units</h2>${seg("units", [["metric", "°C and ml"], ["us", "°F and fl oz"]], store.units)}</div>
  <div class="panel"><h2>Backup</h2>
    <p class="small muted">Your index is stored in this browser only. Download a backup now and then, and restore it on another phone or browser.</p>
    <div class="row"><button class="btn" type="button" data-act="backup">Download backup</button><button class="btn" type="button" data-act="restore">Restore from backup</button></div>
  </div>
  <div class="panel"><p class="small muted">Care labels are read by Google Gemini, and products are looked up in UPCitemdb and the Open Products, Beauty and Food Facts databases. Each result shows how confident it is. Detergent amounts are starting points — your detergent’s cap or scoop markings win. Your index stays in this browser on this device.</p>
    <p class="small"><a href="/">About Washtag</a></p></div>`;
}

function backup() {
  const blob = new Blob([JSON.stringify({ washtag: 1, savedAt: new Date().toISOString(), ...store.snapshot() })], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `washtag-backup-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

async function restore(file) {
  if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    if (!data || data.washtag !== 1 || !Array.isArray(data.items)) throw new Error();
    if (!confirm(`Replace what's here with the backup (${plural(data.items.length, "item")})?`)) return;
    store.apply(data);
    store.save();
    toast("Backup restored");
  } catch {
    alert("That file isn't a Washtag backup.");
  }
}

/* ---------- Washer & dryer ---------- */

function viewMachines() {
  return `<p class="small muted">Add your machines and Washtag recommends cycles, load sizes and detergent that match them. Specs from a lookup show how sure they are — check them against your manual or the sticker inside the door.</p>
    ${applianceSection("washer")}${applianceSection("dryer")}`;
}

const applianceShown = (kind) => ui.machines[kind] || store[kind] || Appl.typical(kind, kind === "washer" ? "front" : "electric");

function applianceSection(kind) {
  const a = applianceShown(kind);
  const saved = store[kind];
  const noun = kind;
  const us = store.units === "us";
  const cap = us ? (a.capacityCuFt ?? Appl.capacityKg(a) / (kind === "washer" ? 2.2 : 1.4)) : Appl.capacityKg(a);
  const looking = ui.machines.looking[kind];
  let source;
  if (a.source === "lookup") source = `<p class="small"><span class="ok">✓</span> Specs for ${esc(a.name || Appl.title(a))}${a.confidence != null ? ` · ${Math.round(a.confidence)}% sure` : ""}</p>${a.basis ? `<p class="tiny muted">${esc(a.basis)}</p>` : ""}`;
  else if (a.source === "manual") source = `<p class="small muted">Using your own settings.</p>`;
  else source = `<p class="small muted">Using typical specs for a ${esc((Appl.TYPE_NAMES[a.type] || noun).toLowerCase())}. Look up your model for the maker’s own.</p>${a.basis ? `<p class="tiny muted">${esc(a.basis)}</p>` : ""}`;
  return `<section class="panel" aria-labelledby="h-${kind}"><h2 id="h-${kind}">${kind === "washer" ? "Washer" : "Dryer"}</h2>
    <label class="sr" for="${kind}-brand">Brand</label>
    <input type="text" id="${kind}-brand" placeholder="Brand, e.g. LG or Whirlpool" data-bind="m.${kind}.brand" value="${esc(a.brand)}" maxlength="60" autocapitalize="words">
    <label class="sr" for="${kind}-model">Model number</label>
    <input type="text" id="${kind}-model" placeholder="Model number (inside the door or lid)" data-bind="m.${kind}.model" value="${esc(a.model)}" maxlength="60" autocapitalize="characters" autocorrect="off" spellcheck="false">
    <div><button class="btn" type="button" data-act="m-lookup" data-v="${kind}" ${looking || (!a.brand.trim() && !a.model.trim()) ? "disabled" : ""}>
      ${looking ? `<span class="spin" aria-hidden="true"></span>Looking up…` : "Look up maker’s specs"}</button></div>
    ${ui.machines.error[kind] ? `<p class="small bad">${esc(ui.machines.error[kind])}</p>` : ""}
    ${source}
    <div class="field"><span class="lbl">Type</span>
      <div class="seg" role="group">${(kind === "washer" ? Appl.WASHER_TYPES : Appl.DRYER_TYPES).map(([v, l]) =>
        `<button type="button" data-act="m-type" data-kind="${kind}" data-v="${v}" aria-pressed="${a.type === v}">${l}</button>`).join("")}</div></div>
    <div class="field"><label for="${kind}-cap">Drum (${us ? "cu ft" : "kg"})</label>
      <div class="stepper"><input type="number" id="${kind}-cap" inputmode="decimal" step="${us ? 0.1 : 0.5}" min="${us ? 1 : 3}" max="${us ? 10 : 20}" value="${cap.toFixed(1)}" data-change="m-cap" data-kind="${kind}"></div></div>
    ${kind === "washer" ? `
      <div class="field"><span class="lbl">Detergent</span>
        <div class="seg" role="group">${[["he", "HE (high efficiency)"], ["standard", "Standard"]].map(([v, l]) =>
          `<button type="button" data-act="m-set" data-kind="washer" data-key="detergent" data-v="${v}" aria-pressed="${(a.detergent ?? "he") === v}">${l}</button>`).join("")}</div></div>
      <div class="field"><label for="washer-rpm">Max spin (rpm)</label>
        <div class="stepper"><input type="number" id="washer-rpm" inputmode="numeric" step="100" min="400" max="1800" value="${a.maxSpinRpm ?? ""}" placeholder="not sure" data-change="m-rpm" data-kind="washer"></div></div>
      <label class="switch"><span>Heats its own water</span><input type="checkbox" data-change="m-bool" data-kind="washer" data-key="hasHeater" ${a.hasHeater ? "checked" : ""}></label>`
    : `<label class="switch"><span>Sensor / auto dry</span><input type="checkbox" data-change="m-bool" data-kind="dryer" data-key="sensorDry" ${a.sensorDry ?? true ? "checked" : ""}></label>`}
    ${a.cycles.length ? `<div class="field"><span class="lbl">Cycles</span><div class="cycles">${a.cycles.map((c) => `<span>${esc(c)}</span>`).join("")}</div></div>` : ""}
    ${a.tips.length ? `<div class="field"><span class="lbl">${a.source === "lookup" ? "Maker’s recommendations" : "Recommended for this type"}</span><ul class="b small">${a.tips.map((t) => `<li>${esc(t)}</li>`).join("")}</ul></div>` : ""}
    <div class="row" style="justify-content:space-between">
      <button class="btn primary" type="button" data-act="m-save" data-v="${kind}" ${!ui.machines[kind] && saved ? "disabled" : ""}>${saved ? "Save changes" : `Save ${noun}`}</button>
      ${saved ? `<button class="btn danger" type="button" data-act="m-remove" data-v="${kind}">Remove</button>` : ""}
    </div>
  </section>`;
}

/** Edits the draft; changing a spec by hand marks it as the user's own settings. */
function editAppliance(kind, change, { manual = true, rerender = true } = {}) {
  const a = clone(applianceShown(kind));
  change(a);
  if (manual) a.source = "manual";
  ui.machines[kind] = a;
  if (rerender) render();
}

async function lookupAppliance(kind) {
  const a = applianceShown(kind);
  ui.machines.looking[kind] = true; ui.machines.error[kind] = null;
  render();
  try {
    const r = await API.lookupAppliance(kind, a.brand, a.model);
    ui.machines[kind] = Appl.applyLookup(r, a);
    if (r.found !== true) ui.machines.error[kind] = "Washtag couldn’t find that exact model, so it’s showing typical specs. Check the model number, or adjust the settings below.";
  } catch (e) { ui.machines.error[kind] = e.message; }
  ui.machines.looking[kind] = false;
  render();
}

/* ---------- install banner and ads ---------- */

const standalone = () => matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
const isIOS = () => /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
let installDismissed = false;
try { installDismissed = localStorage.getItem("washtag.install-dismissed") === "1"; } catch { /* private mode */ }

function installBanner() {
  if (ui.route !== "scan" || standalone() || installDismissed) return "";
  if (ui.installPrompt) {
    return `<div class="install"><img src="/app/icons/icon-180.png" alt=""><div><b>Install Washtag</b><br>Add it to your home screen to use it like an app.</div>
      <button class="btn primary" type="button" data-act="install">Install</button><button class="x" type="button" data-act="install-dismiss" aria-label="Dismiss">×</button></div>`;
  }
  if (isIOS()) {
    return `<div class="install"><img src="/app/icons/icon-180.png" alt=""><div><b>Add Washtag to your Home Screen</b><br>In Safari, tap the Share button, then <b>Add to Home Screen</b>.</div>
      <button class="x" type="button" data-act="install-dismiss" aria-label="Dismiss">×</button></div>`;
  }
  return "";
}

let adLoaded = false;
function mountAd() {
  if (!ADSENSE.client || !ADSENSE.slot || !navigator.onLine) return;
  const slot = $("#ad");
  if (!slot) return;
  slot.innerHTML = `<p class="tiny muted" style="text-align:center;margin-bottom:4px">Advertisement</p><ins class="adsbygoogle" style="display:block" data-ad-client="${esc(ADSENSE.client)}" data-ad-slot="${esc(ADSENSE.slot)}" data-ad-format="auto" data-full-width-responsive="true"></ins>`;
  if (!adLoaded) {
    adLoaded = true;
    const s = document.createElement("script");
    s.async = true; s.crossOrigin = "anonymous";
    s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${encodeURIComponent(ADSENSE.client)}`;
    document.head.appendChild(s);
  }
  try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch { /* ad blocked */ }
}

let toastTimer;
function toast(text) {
  const t = $("#toast");
  t.textContent = text; t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 1800);
}

/* ---------- events ---------- */

const actions = {
  mode: (el) => { ui.scan.mode = el.dataset.v; ui.scan.status = null; ui.scan.current = null; ui.scan.run++; ui.scan.busy = false; render(); },
  camera: () => $("#cam").click(),
  pick: () => $("#pick").click(),
  live: () => openLive(),
  scan: () => scanPhoto(),
  stop: () => { ui.scan.run++; ui.scan.busy = false; ui.scan.status = "Stopped."; ui.scan.statusErr = false; render(); },

  "rec-need": (el) => {
    const rec = recAt(el.dataset.where); if (!rec) return;
    const r = recUI(rec.id), k = el.dataset.v;
    r.needs = r.needs.includes(k) ? r.needs.filter((x) => x !== k) : [...r.needs, k];
    render();
  },
  "rec-suggest": (el) => recSuggest(el.dataset.where),
  "rec-person": (el) => {
    const rec = recAt(el.dataset.where); if (!rec) return;
    const id = el.dataset.v;
    rec.people = (rec.people || []).includes(id) ? rec.people.filter((x) => x !== id) : [...(rec.people || []), id];
    render();
  },
  "rec-save": (el) => {
    const rec = recAt(el.dataset.where); if (!rec) return;
    store.upsert(clone(rec));
    toast("Saved to index");
    render();
  },
  "rec-load": (el) => {
    const rec = recAt(el.dataset.where); if (!rec) return;
    store.upsert(clone(rec));
    if (!store.load.ids.includes(rec.id)) store.load.ids.push(rec.id);
    ui.load.mode = "load";
    store.save();
    go("#load");
  },

  filter: (el) => { ui.index.person = el.dataset.v || null; render(); },
  "delete-item": () => {
    if (!ui.detail || !confirm(`Delete “${ui.detail.name}” from your index?`)) return;
    store.remove(ui.detail.id);
    go("#index");
  },

  set: (el) => {
    const [root, key] = splitPath(el.dataset.path);
    if (root === "ui.load") ui.load[key] = el.dataset.v;
    else if (root === "load") { store.load[key] = el.dataset.v; store.save(); }
    else if (root === "units") { store.units = el.dataset.v; store.save(); }
    render();
  },
  "load-all": () => { store.load.ids = store.items.filter((r) => r.care?.structured).map((r) => r.id); store.save(); render(); },
  "load-clear": () => { store.load.ids = []; store.save(); render(); },
  "load-need": (el) => {
    const k = el.dataset.v, n = store.load.needs;
    store.load.needs = n.includes(k) ? n.filter((x) => x !== k) : [...n, k];
    store.save(); render();
  },
  "load-suggest": () => loadSuggest(),
  "open-load": (el) => {
    store.load.ids = el.dataset.v.split(",");
    store.load.size = el.dataset.size;
    ui.load.mode = "load";
    store.save(); render();
    scrollTo({ top: 0 });
  },

  "remove-person": (el) => {
    const p = store.person(el.dataset.v);
    if (p && confirm(`Remove ${p.name}? Their items stay in the index, unlabelled.`)) { store.removePerson(p.id); render(); }
  },
  backup: () => backup(),
  restore: () => $("#restore").click(),

  "m-lookup": (el) => lookupAppliance(el.dataset.v),
  "m-type": (el) => {
    // A new type brings that type's typical specs, keeping the name and model.
    const kind = el.dataset.kind, cur = applianceShown(kind);
    const n = Appl.typical(kind, el.dataset.v);
    n.brand = cur.brand; n.model = cur.model; n.source = "manual";
    ui.machines[kind] = n;
    render();
  },
  "m-set": (el) => editAppliance(el.dataset.kind, (a) => { a[el.dataset.key] = el.dataset.v; }),
  "m-save": (el) => {
    const kind = el.dataset.v, a = applianceShown(kind);
    store[kind] = clone(a);
    if (kind === "washer") store.load.machine = Appl.isHE(a) ? "he" : "standard";
    ui.machines[kind] = null;
    store.save();
    toast(kind === "washer" ? "Washer saved" : "Dryer saved");
    render();
  },
  "m-remove": (el) => { store[el.dataset.v] = null; ui.machines[el.dataset.v] = null; store.save(); render(); },

  install: async () => {
    const p = ui.installPrompt; if (!p) return;
    ui.installPrompt = null;
    p.prompt();
    try { await p.userChoice; } catch { /* ignored */ }
    render();
  },
  "install-dismiss": () => {
    installDismissed = true;
    try { localStorage.setItem("washtag.install-dismissed", "1"); } catch { /* private mode */ }
    render();
  },
};

const splitPath = (p) => { const i = p.lastIndexOf("."); return i < 0 ? [p, null] : [p.slice(0, i), p.slice(i + 1)]; };

/** Text boxes write straight into state; only views that depend on them re-render. */
function onInput(el) {
  const b = el.dataset.bind, v = el.value;
  if (b === "scan.typed") {
    ui.scan.typed = v;
    const hint = document.getElementById("typed-hint");
    const d = v.replace(/\D/g, "");
    if (hint) {
      const ok = d ? GTIN.isValid(d) : null;
      hint.className = `tiny ${ok === false ? "bad" : "muted"}`;
      hint.textContent = !d ? "" : ok == null ? `${d.length} digits — UPC is 12, EAN is 13 or 8` : ok ? `✓ Valid ${GTIN.type(d)} check digit` : "✕ Check digit doesn’t match — recheck the numbers";
    }
  } else if (b === "index.query") {
    ui.index.query = v;
    const q = v.trim().toLowerCase(), person = ui.index.person;
    const list = store.items.filter((r) => (!person || (r.people || []).includes(person))
      && (!q || [r.name, r.notes, r.upc?.code, r.product?.brand, r.product?.productName, r.care?.labelText?.fibres, r.care?.product?.type].some((x) => x && x.toLowerCase().includes(q))));
    $("#index-list").innerHTML = indexList(list);
  } else if (b === "newPerson") ui.newPerson = v;
  else if (b === "scan.name" || b === "scan.notes" || b === "detail.name" || b === "detail.notes") {
    const [where, key] = b.split(".");
    const rec = recAt(where);
    if (rec) rec[key] = v;
  } else if (b.startsWith("m.")) {
    const [, kind, key] = b.split(".");
    editAppliance(kind, (a) => { a[key] = v.slice(0, 60); }, { manual: false, rerender: false });
    const btn = document.querySelector(`[data-act="m-lookup"][data-v="${kind}"]`);
    const a = ui.machines[kind];
    if (btn && !ui.machines.looking[kind]) btn.disabled = !a.brand.trim() && !a.model.trim();
    const save = document.querySelector(`[data-act="m-save"][data-v="${kind}"]`);
    if (save) save.disabled = false;
  }
}

function onChange(el) {
  const kind = el.dataset.kind;
  switch (el.dataset.change) {
    case "m-cap": {
      const v = parseFloat(el.value);
      if (!(v > 0)) return;
      const us = store.units === "us";
      editAppliance(kind, (a) => { if (us) { a.capacityCuFt = v; a.capacityKg = null; } else { a.capacityKg = v; a.capacityCuFt = null; } });
      break;
    }
    case "m-rpm": {
      const v = parseInt(el.value, 10);
      editAppliance(kind, (a) => { a.maxSpinRpm = v > 0 ? Math.max(400, Math.min(1800, v)) : null; });
      break;
    }
    case "m-bool": editAppliance(kind, (a) => { a[el.dataset.key] = el.checked; }); break;
  }
}

function wire() {
  document.addEventListener("click", (e) => {
    const el = e.target.closest("[data-act]");
    if (!el || el.tagName === "INPUT") return;
    const f = actions[el.dataset.act];
    if (f) { e.preventDefault(); f(el); }
  });
  document.addEventListener("change", (e) => {
    const el = e.target;
    if (el.dataset?.act === "load-toggle") {
      const id = el.dataset.v;
      store.load.ids = el.checked ? [...new Set([...store.load.ids, id])] : store.load.ids.filter((x) => x !== id);
      store.save(); render();
    } else if (el.dataset?.change) onChange(el);
  });
  document.addEventListener("input", (e) => { if (e.target.dataset?.bind) onInput(e.target); });
  document.addEventListener("submit", (e) => {
    const f = e.target.dataset?.form;
    if (!f) return;
    e.preventDefault();
    if (f === "typed") lookUpCode(ui.scan.typed, "typed");
    if (f === "person") { store.addPerson(ui.newPerson); ui.newPerson = ""; render(); }
  });
  $("#cam").addEventListener("change", (e) => { setPhoto(e.target.files[0]); e.target.value = ""; });
  $("#pick").addEventListener("change", (e) => { setPhoto(e.target.files[0]); e.target.value = ""; });
  $("#restore").addEventListener("change", (e) => { restore(e.target.files[0]); e.target.value = ""; });
  $("#live-close").addEventListener("click", closeLive);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#live").hidden) closeLive(); });
  $("#back").addEventListener("click", () => go(ui.route === "machines" ? "#household" : "#index"));
  addEventListener("hashchange", () => { closeLive(); readRoute(); render(); scrollTo({ top: 0 }); });
  addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); ui.installPrompt = e; render(); });
  addEventListener("appinstalled", () => { ui.installPrompt = null; render(); });
  // Another tab changed the index.
  addEventListener("storage", (e) => { if (e.key === "washtag.v1") { store.init(); readRoute(); render(); } });
}

/* ---------- start ---------- */

store.init();
wire();
readRoute();
render();

if ("serviceWorker" in navigator) {
  addEventListener("load", () => navigator.serviceWorker.register("/app/sw.js", { scope: "/app/" }).catch(() => {}));
}
