// Prompts carried over from the Washtag prototype, adjusted for the native app.
// Product identity comes from free barcode databases (looked up in the app), so the
// enrich prompt only adds care guidance on top of that catalogue data.

export const LABEL_PROMPT = `You are an expert textile care-label reader (ISO 3758 / GINETEX, ASTM D5489, Japanese JIS L 0001, and text-only labels in any language).
Look at the attached photo. It may show a garment care label, a hang tag, or packaging where care symbols sit beside a barcode.
Read ONLY what is visible. Never invent a symbol. If a symbol is blurry, cut off or ambiguous, include it with low confidence and add a recheck note.
Also read any printed text (fibre content, "wash inside out", country, RN/CA numbers, brand) and translate non-English text into English.
If a barcode is visible, read its digits carefully from the human-readable numbers under the bars.

Reply with ONLY one JSON object in exactly this shape:
{
 "symbolsFound": true,
 "overallConfidence": 0-100,
 "imageQuality": "good" | "fair" | "poor",
 "qualityNotes": "short note about focus, glare, cropping",
 "symbols": [ { "category": "wash"|"bleach"|"dry"|"iron"|"dryclean"|"other",
                "code": "snake_case id e.g. wash_40, wash_30_gentle, wash_hand, do_not_wash, bleach_any, bleach_non_chlorine, do_not_bleach, tumble_low, tumble_normal, do_not_tumble, line_dry, dry_flat, drip_dry, dry_in_shade, iron_low, iron_medium, iron_high, do_not_iron, do_not_steam, dryclean_p, dryclean_f, dryclean_w, do_not_dryclean, do_not_wring",
                "prohibited": true|false,
                "tempC": number or null,
                "meaning": "plain English meaning",
                "confidence": 0-100 } ],
 "sections": {
   "wash": ["clear instruction sentences for washing, including temperature and cycle"],
   "dry": ["clear instruction sentences for drying"],
   "care": ["bleach, ironing, dry cleaning and other care that IS allowed"],
   "doNot": ["each thing the user must not do, short and direct"]
 },
 "structured": { "maxWashTempC": number|null, "washCycle": "normal"|"permanent_press"|"gentle"|"hand"|"do_not_wash"|null,
   "bleach": "any"|"non_chlorine"|"none"|null, "tumble": "normal"|"low"|"none"|null,
   "naturalDry": "line"|"flat"|"drip"|"shade"|null, "iron": "low"|"medium"|"high"|"none"|null,
   "dryClean": "allowed"|"only"|"none"|null },
 "labelText": { "fibres": "e.g. 60% cotton, 40% polyester or null", "other": "other printed text, translated, or null", "language": "original language(s)" },
 "barcode": { "present": true|false, "digits": "digits only or null", "confidence": 0-100 },
 "product": { "brand": null or string, "name": null or string, "type": "e.g. t-shirt, jeans, wool jumper, detergent, unknown" },
 "suggestedName": "a short friendly name for this item, e.g. 'Navy wool jumper'",
 "recheck": ["specific things the user should double-check on the physical label"]
}
If no care symbols or care text are visible, set symbolsFound to false, explain why in qualityNotes, and leave arrays empty.`;

export const DIGITS_PROMPT = `Read the barcode digits in this photo from the human-readable numbers printed under the bars. Reply with ONLY JSON: {"digits": "digits only or null", "confidence": 0-100, "note": "short"}`;

export function enrichPrompt(product: Record<string, unknown>, labelContext: string | null): string {
  return `You add laundry care guidance to a product record that came from a barcode database.
Product record: ${JSON.stringify(product)}
${labelContext ? "Context from the scanned care label: " + labelContext : ""}
Only use what the record says. If it is not a garment, textile or laundry product, return empty arrays.

Reply with ONLY one JSON object:
{
 "category": "garment"|"footwear"|"home textile"|"laundry detergent"|"fabric softener"|"stain remover"|"other",
 "careNotes": ["general care guidance for this product type, at most 4"],
 "detergentUse": { "isLaundryProduct": true|false, "typicalDoseNote": "how this product is usually dosed, if the record says or it is well known, else null" }
}`;
}

export function suggestPrompt(structured: unknown, needs: string[], fibres: string | null, typeName: string | null): string {
  return `You are a practical laundry advisor. Recommend laundry products for this item/load.
Care constraints: ${JSON.stringify(structured ?? {})}
Fibres/type: ${fibres || "unknown"}; ${typeName || ""}
User needs: ${needs.length ? needs.join(", ") : "none stated"}
Give product TYPES first; you may name 1-3 widely available example brands per type as examples only.
Respect the care label strictly (e.g. no enzyme detergent on wool/silk, no chlorine bleach if bleach is limited, no softener on activewear or towels when absorbency matters).
Reply with ONLY a JSON object:
{ "suggestions": [ { "type": "product type", "why": "one sentence tied to the label or need", "examples": ["brand examples"], "howMuch": "short dosing tip" } ],
  "avoid": [ { "what": "product or practice", "why": "one sentence" } ] }
Up to 4 suggestions and up to 3 avoid entries.`;
}
