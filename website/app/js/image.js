// Turns a picked or captured photo into what the scanners need.

/** Loads a File into an <img>, which applies the photo's EXIF rotation. */
export function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That photo couldn't be opened. Try a JPEG or PNG.")); };
    img.src = url;
  });
}

/** Draws the image into a canvas no bigger than maxSide on its long edge. */
export function toCanvas(img, maxSide) {
  const w = img.naturalWidth || img.videoWidth || img.width, h = img.naturalHeight || img.videoHeight || img.height;
  const scale = Math.min(1, maxSide / Math.max(w, h));
  const c = document.createElement("canvas");
  c.width = Math.round(w * scale);
  c.height = Math.round(h * scale);
  c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
  return c;
}

/** JPEG base64 (no data: prefix) for the AI, sized like the iPhone app sends it. */
export function jpegBase64(img) {
  return toCanvas(img, 1600).toDataURL("image/jpeg", 0.85).split(",")[1];
}

/** Small JPEG data URL kept with a saved item. */
export function thumbnail(img) {
  return toCanvas(img, 220).toDataURL("image/jpeg", 0.7);
}
