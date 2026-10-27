// On-device barcode decoding: the browser's own BarcodeDetector where there is one
// (Chrome, Android), otherwise ZXing (Safari on iPhone). Nothing leaves the device.

import { toCanvas } from "./image.js";
import { expandUPCE } from "./gtin.js";

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

const clean = (text) => {
  const d = String(text || "").replace(/\D/g, "");
  return d ? expandUPCE(d) : null;
};

/** Reads a barcode from a still photo, or null. */
export async function decodeImage(img) {
  const det = await nativeDetector();
  if (det) {
    try {
      const found = await det.detect(img);
      if (found.length) return clean(found[0].rawValue);
    } catch { /* fall through to ZXing */ }
  }
  try {
    for (const side of [1400, 900]) {
      const hit = await zxingDecode(toCanvas(img, side));
      if (hit) return clean(hit);
    }
  } catch { /* reader unavailable */ }
  return null;
}

/** Live camera scanning. Calls onCode once with the first barcode it reads. Returns a stop function. */
export async function startLive(video, onCode) {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false,
  });
  video.srcObject = stream;
  video.setAttribute("playsinline", "");
  video.muted = true;
  await video.play();

  let stopped = false;
  const stop = () => { stopped = true; stream.getTracks().forEach((t) => t.stop()); video.srcObject = null; };
  const det = await nativeDetector();
  const canvas = document.createElement("canvas");

  const tick = async () => {
    if (stopped) return;
    let code = null;
    try {
      if (det) {
        const found = await det.detect(video);
        if (found.length) code = clean(found[0].rawValue);
      } else if (video.videoWidth) {
        // Read the middle band of the frame, where the guide box is.
        const w = video.videoWidth, h = video.videoHeight;
        const cw = Math.min(w, 960), ch = Math.round(cw * 0.5);
        const sx = (w - cw) / 2, sy = Math.max(0, (h - ch) / 2);
        canvas.width = cw; canvas.height = Math.min(ch, h);
        canvas.getContext("2d", { willReadFrequently: true }).drawImage(video, sx, sy, cw, canvas.height, 0, 0, cw, canvas.height);
        code = clean(await zxingDecode(canvas));
      }
    } catch { /* keep trying */ }
    if (stopped) return;
    if (code && code.length >= 8) { stop(); onCode(code); return; }
    setTimeout(tick, det ? 150 : 250);
  };
  if (!det) await loadZXing();
  tick();
  return stop;
}

export const liveAvailable = () => !!navigator.mediaDevices?.getUserMedia && window.isSecureContext;
