// Reads only the title icons currently in use as font-independent SVG outlines.
// Tern's SVG renderer does not render font text.
// Usage: node glyphs.mjs "<font family>" F0566 EA64
import { closeSync, openSync, readFileSync, readSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseFont } from './vendor/opentype-2.0.0.min.mjs';

const PRIVATE_USE = [[0xe000, 0xf8ff], [0xf0000, 0xffffd], [0x100000, 0x10fffd]];

function fontDirectories() {
  const home = homedir();
  if (process.platform === 'win32') {
    return [path.join(process.env.WINDIR ?? 'C:\\Windows', 'Fonts'),
      path.join(process.env.LOCALAPPDATA ?? path.join(home, 'AppData', 'Local'), 'Microsoft', 'Windows', 'Fonts')];
  }
  if (process.platform === 'darwin') return [path.join(home, 'Library', 'Fonts'), '/Library/Fonts', '/System/Library/Fonts'];
  return [path.join(home, '.local', 'share', 'fonts'), path.join(home, '.fonts'), '/usr/local/share/fonts', '/usr/share/fonts'];
}

function fontFiles(directory, depth = 0, out = []) {
  let entries;
  try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return out; }
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory() && depth < 3) fontFiles(file, depth + 1, out);
    else if (/\.(ttf|otf)$/i.test(entry.name)) out.push(file);
  }
  return out;
}

function tables(read) {
  const head = read(0, 12);
  const count = head.readUInt16BE(4);
  const records = read(12, count * 16);
  const result = new Map();
  for (let i = 0; i < count; i++) {
    result.set(records.toString('latin1', i * 16, i * 16 + 4), { offset: records.readUInt32BE(i * 16 + 8), length: records.readUInt32BE(i * 16 + 12) });
  }
  return result;
}

function names(read, table) {
  const data = read(table.offset, table.length);
  const count = data.readUInt16BE(2), strings = data.readUInt16BE(4);
  const out = {};
  for (let i = 0; i < count; i++) {
    const at = 6 + i * 12;
    const platform = data.readUInt16BE(at), id = data.readUInt16BE(at + 6);
    const length = data.readUInt16BE(at + 8), start = strings + data.readUInt16BE(at + 10);
    if (![1, 2, 16, 17].includes(id) || (platform !== 3 && platform !== 0)) continue;
    const bytes = Buffer.from(data.subarray(start, start + length));
    out[id] ??= bytes.swap16().toString('utf16le');
  }
  return { family: out[16] ?? out[1], style: out[17] ?? out[2] };
}

function headerReader(file) {
  const fd = openSync(file, 'r');
  return {
    read(offset, length) { const buffer = Buffer.alloc(length); readSync(fd, buffer, 0, length, offset); return buffer; },
    close() { closeSync(fd); },
  };
}

export function findFont(family) {
  const wanted = family.trim().toLowerCase();
  let best;
  for (const file of fontDirectories().flatMap(directory => fontFiles(directory))) {
    let reader;
    try {
      reader = headerReader(file);
      const table = tables(reader.read).get('name');
      if (!table) continue;
      const { family: name, style } = names(reader.read, table);
      if (name?.trim().toLowerCase() !== wanted) continue;
      const score = /^regular$/i.test(style ?? '') ? 2 : /^(normal|book)$/i.test(style ?? '') ? 1 : 0;
      if (!best || score > best.score) best = { file, score };
    } catch {
      // Unreadable or non-sfnt files cannot be the configured font.
    } finally {
      reader?.close();
    }
  }
  return best?.file;
}

export function measure(file, codepoints) {
  const bytes = readFileSync(file);
  const buffer = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
    ? bytes.buffer : bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const font = parseFont(buffer, { lowMemory: true });
  const paths = {};
  for (const cp of new Set(codepoints)) {
    if (!PRIVATE_USE.some(([lo, hi]) => cp >= lo && cp <= hi)) continue;
    const key = cp.toString(16).toUpperCase();
    const index = font.charToGlyphIndex(String.fromCodePoint(cp));
    paths[key] = false;
    if (!index) continue;
    const glyph = font.glyphs.get(index);
    const box = glyph.getPath(0, 0, 1, undefined, font).getBoundingBox();
    const size = Math.max(box.x2 - box.x1, box.y2 - box.y1);
    if (size <= 0) continue;
    const scale = 12 / size;
    const x = 8 - (box.x1 + box.x2) / 2 * scale;
    const y = 8 - (box.y1 + box.y2) / 2 * scale;
    const outline = glyph.getPath(x, y, scale, undefined, font);
    // opentype.js 2.0.0 can serialize floating-point noise as NaN. Quantize to SVG precision first.
    for (const command of outline.commands) {
      for (const key in command) {
        if (typeof command[key] === 'number') command[key] = Math.round(command[key] * 100) / 100;
      }
    }
    paths[key] = outline.toPathData({ decimalPlaces: 2, flipY: false });
  }
  return { paths };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const family = process.argv[2];
  if (!family) { process.stderr.write('Usage: glyphs.mjs <font family> [hex codepoints...]\n'); process.exit(1); }
  const codepoints = process.argv.slice(3).map(cp => Number.parseInt(cp, 16));
  const font = findFont(family);
  const metrics = font ? measure(font, codepoints) : { paths: Object.fromEntries(codepoints.map(cp => [cp.toString(16).toUpperCase(), false])) };
  process.stdout.write(JSON.stringify({ font, ...metrics }) + '\n');
}
