// Barcode digits: check digit, type, confidence scoring and GS1 region. Port of GTIN.swift.

/** null when the code isn't a standard length; otherwise whether the check digit matches. */
export function isValid(code) {
  if (!/^\d+$/.test(code) || ![8, 12, 13, 14].includes(code.length)) return null;
  const digits = [...code].map(Number);
  const check = digits.pop();
  let sum = 0;
  digits.reverse().forEach((n, i) => { sum += n * (i % 2 === 0 ? 3 : 1); });
  return (10 - (sum % 10)) % 10 === check;
}

export function type(code) {
  return { 8: "EAN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14" }[code.length] || "Unknown";
}

export function digitsOnly(s) {
  if (s == null) return null;
  const d = String(s).replace(/\D/g, "");
  return d || null;
}

/** UPC-E (8 digits starting 0 or 1) written out as the 12-digit UPC-A that databases use. */
export function expandUPCE(code) {
  if (!/^[01]\d{7}$/.test(code)) return code;
  const [ns, d1, d2, d3, d4, d5, d6, check] = code;
  let body;
  if ("012".includes(d6)) body = d1 + d2 + d6 + "0000" + d3 + d4 + d5;
  else if (d6 === "3") body = d1 + d2 + d3 + "00000" + d4 + d5;
  else if (d6 === "4") body = d1 + d2 + d3 + d4 + "00000" + d5;
  else body = d1 + d2 + d3 + d4 + d5 + "0000" + d6;
  const full = ns + body + check;
  return isValid(full) ? full : code;
}

/** Decoded bars beat printed digits; check digit and agreement between the two readings move the score. */
export function build({ decoded = null, visual = null, visualConfidence = null, typed = null }) {
  const code = digitsOnly(decoded) || visual || typed || "";
  const checksum = isValid(code);
  const agree = decoded != null && visual != null ? digitsOnly(decoded) === visual : null;
  let score = typed != null ? 70 : 30;
  if (decoded != null) score = 80;
  if (visual != null && decoded == null) score = Math.min(70, visualConfidence ?? 50);
  if (checksum === true) score += 15; else if (checksum === false) score -= 40;
  if (agree === true) score += 10; else if (agree === false) score -= 25;
  const via = decoded != null ? "on-device decoder" : typed != null ? "typed by you" : "read from printed digits";
  return { code, type: type(code), checksum, via, visualDigits: visual, agree, readConfidence: Math.max(5, Math.min(99, score)) };
}

const REGIONS = [
  [0, 19, "USA / Canada"], [30, 39, "USA (restricted)"], [60, 139, "USA / Canada"], [300, 379, "France"], [380, 380, "Bulgaria"],
  [400, 440, "Germany"], [450, 459, "Japan"], [460, 469, "Russia"], [471, 471, "Taiwan"], [480, 480, "Philippines"], [489, 489, "Hong Kong"],
  [490, 499, "Japan"], [500, 509, "United Kingdom"], [520, 521, "Greece"], [540, 549, "Belgium / Luxembourg"], [560, 560, "Portugal"],
  [570, 579, "Denmark"], [590, 590, "Poland"], [600, 601, "South Africa"], [640, 649, "Finland"], [690, 699, "China"], [700, 709, "Norway"],
  [729, 729, "Israel"], [730, 739, "Sweden"], [750, 750, "Mexico"], [760, 769, "Switzerland"], [779, 779, "Argentina"], [789, 790, "Brazil"],
  [800, 839, "Italy"], [840, 849, "Spain"], [858, 858, "Slovakia"], [859, 859, "Czechia"], [868, 869, "Turkey"], [870, 879, "Netherlands"],
  [880, 880, "South Korea"], [885, 885, "Thailand"], [888, 888, "Singapore"], [890, 890, "India"], [893, 893, "Vietnam"], [899, 899, "Indonesia"],
  [900, 919, "Austria"], [930, 939, "Australia"], [940, 949, "New Zealand"], [955, 955, "Malaysia"],
];

/** Rough GS1 prefix → where the company registered its barcodes (not where the product was made). */
export function region(code) {
  const c = code.length === 12 ? "0" + code : code;
  if (c.length !== 13) return null;
  const p = Number(c.slice(0, 3));
  const hit = REGIONS.find(([lo, hi]) => p >= lo && p <= hi);
  return hit ? hit[2] : null;
}
