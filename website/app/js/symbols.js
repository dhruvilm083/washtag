// Generic ISO-style care pictograms as inline SVG, on the same 40×42 grid as CareSymbolView.swift.

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function dots(n, cx, cy) {
  const x0 = cx - (n - 1) * 5 / 2;
  return Array.from({ length: n }, (_, i) => `<circle cx="${x0 + i * 5}" cy="${cy}" r="1.6" fill="currentColor" stroke="none"/>`).join("");
}
const text = (t, x, y, fs) => `<text x="${x}" y="${y}" font-size="${fs}" font-weight="700" text-anchor="middle" dominant-baseline="central" fill="currentColor" stroke="none" font-family="system-ui, sans-serif">${esc(t)}</text>`;

export function careSymbol({ category = "other", code = "", prohibited = false, tempC = null, tempLabel = null } = {}) {
  const c = String(code).toLowerCase();
  let body = "";
  switch (category) {
    case "wash": {
      body += `<path d="M5 12 L35 12 L31.5 31 L8.5 31 Z"/><path d="M5 12 C8 15 11.5 15 15 12 C18.5 9 22 9 25 12 C28 15 31.5 15 35 12"/>`;
      if (c.includes("hand")) body += `<path stroke-width="2" d="M15 25 C17 21 20 19 24 19 M13 27 L23 27"/>`;
      else {
        const label = tempLabel ?? (tempC != null ? String(Math.round(tempC)) : null);
        if (label) body += text(label, 20, 23.5, 9);
      }
      const bars = c.includes("permanent") || c.includes("press") ? 1 : c.includes("gentle") || c.includes("delicate") || c.includes("wool") ? 2 : 0;
      for (let i = 0; i < bars; i++) body += `<path stroke-width="1.8" d="M8 ${35 + i * 3} L32 ${35 + i * 3}"/>`;
      break;
    }
    case "bleach":
      body += `<path d="M20 6 L35 33 L5 33 Z"/>`;
      if (c.includes("non_chlorine") || c.includes("oxygen")) body += `<path stroke-width="1.8" d="M16 30 L22 14 M21 30 L27 14"/>`;
      break;
    case "dry":
      body += `<rect x="6" y="6" width="28" height="28"/>`;
      if (c.includes("tumble")) {
        body += `<circle cx="20" cy="20" r="10"/>`;
        if (c.includes("low")) body += dots(1, 20, 20); else if (c.includes("high")) body += dots(3, 20, 20); else if (c.includes("medium") || c.includes("normal")) body += dots(2, 20, 20);
      } else if (c.includes("line")) body += `<path stroke-width="2" d="M9 10 C15 15 25 15 31 10"/>`;
      else if (c.includes("flat")) body += `<path d="M11 20 L29 20"/>`;
      else if (c.includes("drip")) body += `<path stroke-width="2" d="M14 11 L14 29 M20 11 L20 29 M26 11 L26 29"/>`;
      if (c.includes("shade")) body += `<path stroke-width="2" d="M6 16 L16 6"/>`;
      break;
    case "iron":
      body += `<path d="M6 30 L34 30 C34 21 31 15 23 15 L16 15 C13 15 12 17 12 19 L12 20"/>`;
      if (c.includes("low")) body += dots(1, 20, 25); else if (c.includes("high")) body += dots(3, 20, 25); else if (c.includes("medium")) body += dots(2, 20, 25);
      break;
    case "dryclean": {
      body += `<circle cx="20" cy="20" r="13"/>`;
      const m = c.match(/_(p|f|w|a)\b/);
      if (m) body += text(m[1].toUpperCase(), 20, 20.5, 12);
      break;
    }
    default:
      body += `<circle cx="20" cy="20" r="13" stroke-width="2" stroke-dasharray="3 3"/>` + text("?", 20, 20.5, 13);
  }
  if (prohibited) body += `<path stroke-width="2.4" d="M6 6 L34 34 M34 6 L6 34"/>`;
  return `<svg class="sym" viewBox="0 0 40 42" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}

export const symbolFor = (s) => careSymbol({ category: s.category || "other", code: s.code || "", prohibited: !!s.prohibited, tempC: s.tempC });
