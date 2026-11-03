// On-device barcode decoding: the browser's own BarcodeDetector where there is one
// (Chrome, Android), otherwise ZXing (Safari on iPhone). Nothing leaves the device.

import { toCanvas } from "./image.js";
import { canonical, isGood } from "./gtin.js";

const FORMATS = ["ean_13", "ean_8", "upc_a", "upc_e"];
let detector;
let zxing;

async function nativeDetector() {
  if (detector !== undefined) return detector;
  detector = null;
  try {
    if ("BarcodeDetector" in window) {
      const supported = await window.BarcodeDetector.getSupportedFormats();
      const formats = FORMATS.filter((f) => supported.includes(f));
      if (formats.length) detector = new window.BarcodeDetector({ formats });
    }
  } catch { detector = null; }
  return detector;
}

function loadZXing() {
  if (zxing) return zxing;
  zxing = new Promise((resolve, reject) => {
    if (window.ZXing) return resolve(window.ZXing);
    const s = document.createElement("script");
    s.src = new URL("../vendor/zxing.min.js", import.meta.url).href;
    s.onload = () => resolve(window.ZXing);
    s.onerror = () => { zxing = null; reject(new Error("The barcode reader couldn't load.")); };
    document.head.appendChild(s);
  });
  return zxing;
}

let zreader;
async function zxingDecode(canvas) {
  const Z = await loadZXing();
  if (!zreader) {
    const hints = new Map();
    hints.set(Z.DecodeHintType.POSSIBLE_FORMATS, [Z.BarcodeFormat.EAN_13, Z.BarcodeFormat.EAN_8, Z.BarcodeFormat.UPC_A, Z.BarcodeFormat.UPC_E]);
    hints.set(Z.DecodeHintType.TRY_HARDER, true);
    zreader = new Z.MultiFormatReader();
    zreader.setHints(hints);
  }
  const { width, height } = canvas;
  const rgba = canvas.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, width, height).data;
  const lum = new Uint8ClampedArray(width * height);
  for (let i = 0, j = 0; j < lum.length; i += 4, j++) lum[j] = (rgba[i] * 306 + rgba[i + 1] * 601 + rgba[i + 2] * 117) >> 10;
  const bitmap = new Z.BinaryBitmap(new Z.HybridBinarizer(new Z.RGBLuminanceSource(lum, width, height)));
  try {
    return zreader.decodeWithState(bitmap).getText();
  } catch {
    return null;
  } finally {
    zreader.reset();
  }
}

/** A decoded payload in canonical form, or null when it isn't a retail code with a valid check digit. */
const clean = (text) => {
  const d = String(text || "").replace(/\D/g, "");
  if (!d) return null;
  const c = canonical(d);
  return isGood(c) ? c : null;
};

/** Reads a barcode from a still photo, or null. Only codes with a valid check digit count. */
export async function decodeImage(img) {
  const det = await nativeDetector();
  if (det) {
    try {
      const found = await det.detect(img);
      for (const f of found) { const c = clean(f.rawValue); if (c) return c; }
    } catch { /* fall through to ZXing */ }
  }
  try {
    for (const side of [1400, 900, 2000]) {
      const hit = clean(await zxingDecode(toCanvas(img, side)));
      if (hit) return hit;
    }
  } catch { /* reader unavailable */ }
  return null;
}

/** Reads needed of the same code before live scanning accepts it, and how far ahead of any other code it must be. */
const NEEDED = 3;
const LEAD = 2;

/**
 * Live camera scanning. Calls onCode once, when the same valid barcode has been read several times
 * (one glimpse is often misread). Returns { stop, capture }, where capture() resolves to a still photo.
 */
export async function startLive(video, onCode) {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false,
  });
  video.srcObject = stream;
  video.setAttribute("playsinline", "");
  video.muted = true;
  await video.play();

  let stopped = false;
  const stop = () => { stopped = true; stream.getTracks().forEach((t) => t.stop()); video.srcObject = null; };
  const det = await nativeDetector();
  const canvas = document.createElement("canvas");
  const votes = new Map();

  const tick = async () => {
    if (stopped) return;
    const seen = [];
    try {
      if (det) {
        for (const f of await det.detect(video)) { const c = clean(f.rawValue); if (c) seen.push(c); }
      } else if (video.videoWidth) {
        // Read the middle band of the frame, where the guide box is.
        const w = video.videoWidth, h = video.videoHeight;
        const cw = Math.min(w, 1280), ch = Math.round(cw * 0.5);
        const sx = (w - cw) / 2, sy = Math.max(0, (h - ch) / 2);
        canvas.width = cw; canvas.height = Math.min(ch, h);
        canvas.getContext("2d", { willReadFrequently: true }).drawImage(video, sx, sy, cw, canvas.height, 0, 0, cw, canvas.height);
        const c = clean(await zxingDecode(canvas));
        if (c) seen.push(c);
      }
    } catch { /* keep trying */ }
    if (stopped) return;
    for (const c of new Set(seen)) votes.set(c, (votes.get(c) || 0) + 1);
    const ranked = [...votes.entries()].sort((a, b) => b[1] - a[1]);
    if (ranked.length && ranked[0][1] >= NEEDED && (ranked.length < 2 || ranked[0][1] - ranked[1][1] >= LEAD)) {
      stop(); onCode(ranked[0][0]); return;
    }
    setTimeout(tick, det ? 120 : 200);
  };
  if (!det) await loadZXing();
  tick();

  /** Grabs the current frame as an image, for care labels and products. */
  const capture = () => new Promise((resolve, reject) => {
    if (!video.videoWidth) return reject(new Error("The camera isn't ready yet."));
    const c = document.createElement("canvas");
    c.width = video.videoWidth; c.height = video.videoHeight;
    c.getContext("2d").drawImage(video, 0, 0);
    c.toBlob((blob) => {
      if (!blob) return reject(new Error("Couldn't take the photo."));
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("Couldn't take the photo."));
      img.src = URL.createObjectURL(blob);
    }, "image/jpeg", 0.92);
  });
  return { stop, capture };
}

export const liveAvailable = () => !!navigator.mediaDevices?.getUserMedia && window.isSecureContext;
