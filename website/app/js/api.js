// Talks to the Washtag API on this site (api/washtag.ts), which holds the Gemini key.

const BASE = "/api/washtag";

export class APIError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

async function send(op, { method = "POST", body = null, query = "" } = {}) {
  let res;
  try {
    res = await fetch(`${BASE}?op=${op}${query}`, {
      method,
      headers: body ? { "content-type": "application/json" } : {},
      body: body ? JSON.stringify(body) : null,
    });
  } catch {
    throw new APIError("network", "Couldn't reach Washtag. Check your connection and try again.");
  }
  let data = null;
  try { data = await res.json(); } catch { /* handled below */ }
  if (!res.ok) {
    if (data?.error?.message) throw new APIError(data.error.code, data.error.message);
    throw new APIError(`http_${res.status}`, `Something went wrong (${res.status}). Try again.`);
  }
  if (data == null) throw new APIError("invalid_json", "The answer came back garbled. Try again.");
  return data;
}

export const readLabel = (image) => send("label", { body: { image } });
export const readDigits = (image) => send("digits", { body: { image } });

/** Adds care notes to a product found in a barcode database. */
export function enrich(product, context) {
  const record = { title: product.productName, brand: product.brand, category: product.category, description: product.description, color: product.color };
  return send("enrich", { body: { product: record, context: context ? context.slice(0, 300) : null } });
}

export const suggest = (structured, needs, fibres, type) => send("suggest", { body: { structured, needs, fibres, type } });

export const lookupAppliance = (kind, brand, model) =>
  send("appliance", { body: { kind, brand: brand.slice(0, 60), model: model.slice(0, 60) } });

/** Relays a barcode-database request through the site, for when the browser can't call the database itself. */
export async function productViaServer(src, code) {
  const res = await fetch(`${BASE}?op=product&src=${src}&code=${encodeURIComponent(code)}`);
  return res;
}
