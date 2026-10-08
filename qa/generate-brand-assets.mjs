import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';
import sharp from 'sharp';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const brand = path.join(root, 'app/assets/brand');
const sourceBytes = await fs.readFile(path.join(brand, 'readuo-original.svg'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceHash = '898a5c68bcd4edc102e8a1aeef10d8ee1dec56be3f996053994a752865c2d1b9';
assert.equal(hash(sourceBytes), sourceHash, 'The supplied logo source changed. Review it before regenerating.');
const fontPath = process.env.READUO_LOGO_FONT ?? 'C:/Windows/Fonts/ariblk.ttf';
const fontHash = hash(await fs.readFile(fontPath));
assert.equal(fontHash, '10df702864b1f89cb29ba0d6b97c04228338d16807e13e8d8c74b91aba5e5f23', 'Use the verified Arial Black font; never silently substitute typography.');
const font = { fontFiles: [fontPath], loadSystemFonts: false, defaultFontFamily: 'Arial Black' };
const original = sourceBytes.toString('utf8');
const definitions = original.match(/<defs>[\s\S]*?<\/defs>/)[0];
const border = /<rect[^>]*fill="none"[^>]*\/>/g;
const artwork = original
  .replace(/<svg[^>]*>/, '')
  .replace(definitions, '')
  .replace(/<\/svg>\s*$/, '')
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/<rect[^>]*fill="url\(#(?:bgGrad|highlightGrad)\)"[^>]*\/>/g, '')
  .replace(border, '');
const svg = body => `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">${definitions}${body}</svg>`;
const variants = {
  original,
  ios: original.replace('viewBox="0 0 400 400"', 'viewBox="10 10 380 380"').replaceAll('rx="70" ry="70"', 'rx="0" ry="0"').replace(border, ''),
  foreground: svg(`<g transform="translate(72 72) scale(0.64)">${artwork}</g>`),
  background: svg('<rect width="400" height="400" fill="url(#bgGrad)"/><rect width="400" height="400" fill="url(#highlightGrad)"/>'),
};
const outlines = {};
for (const [name, content] of Object.entries(variants)) {
  outlines[name] = new Resvg(content, { font }).toString();
  assert(!outlines[name].includes('<text'), 'Outlined assets must not depend on installed fonts.');
  await fs.writeFile(path.join(brand, `readuo-${name}-outlined.svg`), outlines[name]);
}

const wordmark = original.match(/<text[\s\S]*?<\/text>/)[0];
const textBounds = new Resvg(svg(wordmark), { font }).getBBox();
const criticalBounds = [
  [textBounds.x, textBounds.y, textBounds.x + textBounds.width, textBounds.y + textBounds.height],
  [40, 150, 240, 155],
  [200, 225, 362, 230],
  [264, 100, 308, 144],
];
for (const [left, top, right, bottom] of criticalBounds) {
  for (const horizontal of [left, right]) {
    for (const vertical of [top, bottom]) {
      assert(Math.hypot(horizontal * .64 + 72 - 200, vertical * .64 + 72 - 200) < 400 * 33 / 108, 'Critical branding exceeds the Android 66dp safe circle.');
    }
  }
}

const files = [];
async function writePng(relative, variant, size, opaque = false) {
  assert(Number.isInteger(size) && size > 0);
  const rendered = new Resvg(outlines[variant], {
    fitTo: { mode: 'width', value: size }, font: { loadSystemFonts: false },
  }).render();
  assert.equal(rendered.width, size);
  assert.equal(rendered.height, size);
  if (opaque) {
    const pixels = rendered.pixels;
    for (let offset = 3; offset < pixels.length; offset += 4) assert.equal(pixels[offset], 255, `${relative} contains transparent pixels`);
  }
  const filename = path.join(root, relative);
  await fs.mkdir(path.dirname(filename), { recursive: true });
  const png = opaque
    ? await sharp(rendered.asPng()).removeAlpha().png({ compressionLevel: 9 }).toBuffer()
    : rendered.asPng();
  await fs.writeFile(filename, png);
  const metadata = await sharp(png).metadata();
  assert.equal(metadata.width, size);
  assert.equal(metadata.height, size);
  if (opaque) assert.equal(metadata.hasAlpha, false);
  files.push({ path: relative, width: size, height: size, alpha: metadata.hasAlpha, sha256: hash(png) });
}

for (const size of [32, 48, 64, 96, 128, 192, 256, 400, 512, 1024]) {
  await writePng(`app/assets/brand/exports/readuo-${size}.png`, 'original', size);
}
for (const scale of [1, 2, 3, 4]) {
  await writePng(`app/assets/brand/${scale === 1 ? '' : `${scale}.0x/`}readuo-logo.png`, 'original', 64 * scale);
}
for (const [density, scale] of Object.entries({ mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 })) {
  const directory = `app/android/app/src/main/res/mipmap-${density}`;
  await writePng(`${directory}/ic_launcher.png`, 'original', 48 * scale);
  await writePng(`${directory}/ic_launcher_foreground.png`, 'foreground', 108 * scale);
  await writePng(`${directory}/ic_launcher_background.png`, 'background', 108 * scale, true);
}
const iconDirectory = 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
const catalog = JSON.parse(await fs.readFile(path.join(root, iconDirectory, 'Contents.json'), 'utf8'));
const iosFiles = new Map();
for (const entry of catalog.images) {
  const dimensions = entry.size.split('x').map(Number);
  assert.equal(dimensions[0], dimensions[1]);
  const size = dimensions[0] * Number.parseFloat(entry.scale);
  if (iosFiles.has(entry.filename)) assert.equal(iosFiles.get(entry.filename), size);
  iosFiles.set(entry.filename, size);
}
for (const [filename, size] of iosFiles) await writePng(`${iconDirectory}/${filename}`, 'ios', size, true);
await writePng('app/assets/brand/exports/readuo-ios-1024.png', 'ios', 1024, true);

const combined = svg(`<rect width="400" height="400" fill="url(#bgGrad)"/><rect width="400" height="400" fill="url(#highlightGrad)"/><g transform="translate(72 72) scale(0.64)">${artwork}</g>`);
const combinedPng = new Resvg(combined, { font, fitTo: { mode: 'width', value: 432 } }).render().asPng();
await fs.mkdir(path.join(root, 'app/test/artifacts/brand'), { recursive: true });
for (const [name, mask] of Object.entries({
  circle: '<circle cx="216" cy="216" r="144" fill="white"/>',
  squircle: '<rect x="72" y="72" width="288" height="288" rx="64" fill="white"/>',
})) {
  const maskPng = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432">${mask}</svg>`).render().asPng();
  await sharp(combinedPng).composite([{ input: maskPng, blend: 'dest-in' }]).png().toFile(path.join(root, `app/test/artifacts/brand/android-${name}.png`));
}
const manifest = {
  source: 'C:/Users/realp/Downloads/readuo.svg', sourceSha256: sourceHash,
  font: 'Arial Black', fontSha256: fontHash,
  renderer: '@resvg/resvg-js 2.6.2', pngProcessor: 'sharp 0.35.4',
  androidForegroundTransform: 'translate(72 72) scale(0.64)',
  androidSafeCircleDp: 66,
  iosAdaptation: 'Crop the 10px transparent source margin, extend the same gradients to square corners, remove the baked corner border; OS applies the icon mask.',
  outlines: Object.fromEntries(Object.entries(outlines).map(([name, content]) => [name, hash(content)])),
  files,
};
await fs.writeFile(path.join(brand, 'generation-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify({ generated: files.length, iosFiles: iosFiles.size, sourceSha256: sourceHash, wordmarkBounds: criticalBounds[0] }));
