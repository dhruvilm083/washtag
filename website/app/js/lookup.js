// Free product lookup (no API key): UPCitemdb's free tier first, then Open Products,
// Open Beauty and Open Food Facts. The AI then adds care notes on top. Port of ProductLookup.swift.

import * as API from "./api.js";
import { region } from "./gtin.js";

const OFF_FIELDS = "product_name,generic_name,brands,categories,image_url,image_front_url,quantity";
const DIRECT = {
  upcitemdb: (c) => `https://api.upcitemdb.com/prod/trial/lookup?upc=${c}`,
  opf: (c) => `https://world.openproductsfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
  obf: (c) => `https://world.openbeautyfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
  off: (c) => `https://world.openfoodfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
};
const OPEN_FACTS = [
  ["opf", "world.openproductsfacts.org", "Open Products Facts"],
  ["obf", "world.openbeautyfacts.org", "Open Beauty Facts"],
  ["off", "world.openfoodfacts.org", "Open Food Facts"],
];

/** Asks the database straight from the browser; if the browser blocks that, asks through this site. */
async function get(src, code) {
  try {
    return await fetch(DIRECT[src](code), { headers: { accept: "application/json" } });
  } catch {
    return API.productViaServer(src, code);
  }
}

export async function lookup(code, context) {
  let info = null;
  const failures = [];

  try { info = await upcItemDB(code); } catch (e) { failures.push(e.message); }
  if (!info) {
    for (const [src, host, name] of OPEN_FACTS) {
      try { info = await openFacts(code, src, host, name); } catch { info = null; }
      if (info) break;
    }
  }

  if (!info) {
    return { found: false, source: null, confidence: 0, basis: failures[0] || "No free product database has a record of this code.",
      stores: [], gs1Region: region(code), careNotes: [] };
  }

  // Ask the AI for care notes; the product data is still useful if this fails.
  try {
    const e = await API.enrich(info, context);
    if (e.category) info.category = e.category;
    info.careNotes = e.careNotes || [];
    info.detergentUse = e.detergentUse || null;
  } catch { /* keep the catalogue data */ }
  return info;
}

async function upcItemDB(code) {
  const res = await get("upcitemdb", code);
  if (res.status === 429) throw new Error("The free barcode database's daily limit (100 lookups) is used up. Try again tomorrow.");
  if (!res.ok) return null;
  const body = await res.json();
  const item = body.items?.[0];
  if (!item?.title) return null;
  const exact = [item.ean, item.upc].filter(Boolean).some((c) => normalise(c) === normalise(code));
  return {
    found: true, source: "upcitemdb", confidence: exact ? 90 : 70,
    basis: exact ? "Exact barcode match in the UPCitemdb database" : "Close match in the UPCitemdb database",
    brand: nonEmpty(item.brand), manufacturer: null, productName: item.title, category: nonEmpty(item.category),
    description: nonEmpty(item.description)?.slice(0, 1200) ?? null, material: null, color: nonEmpty(item.color),
    imageURL: item.images?.[0] || null,
    stores: (item.offers || []).slice(0, 5).map((o) => ({
      name: o.merchant, country: null, link: o.link,
      price: o.price != null ? (!o.currency || o.currency === "USD" ? "$" : o.currency + " ") + Number(o.price).toFixed(2) : null,
    })),
    gs1Region: region(code), careNotes: [], detergentUse: null,
  };
}

async function openFacts(code, src, host, sourceName) {
  const res = await get(src, code);
  if (res.status !== 200) return null;
  const body = await res.json();
  const p = body.product;
  const name = nonEmpty(p?.product_name) || nonEmpty(p?.generic_name);
  if (body.status !== 1 || !name) return null;
  const brand = p.brands?.split(",")[0]?.trim();
  const category = p.categories?.split(",").pop()?.trim();
  return {
    found: true, source: host, confidence: 85, basis: `Exact barcode match in ${sourceName}`,
    brand: nonEmpty(brand), manufacturer: null, productName: name, category: nonEmpty(category),
    description: [p.generic_name, p.quantity].map(nonEmpty).filter(Boolean).join(" · ") || null,
    material: null, color: null, imageURL: p.image_front_url || p.image_url || null, stores: [],
    gs1Region: region(code), careNotes: [], detergentUse: null,
  };
}

const normalise = (s) => String(s).replace(/\D/g, "").replace(/^0+/, "");
const nonEmpty = (s) => (typeof s === "string" && s.trim() ? s.trim() : null);
