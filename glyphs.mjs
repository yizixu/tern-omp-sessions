// Measures how far each private-use icon's ink sits from the centre of its advance in the
// installed font of a family. Nerd Font "NF" (non-Mono) builds give icons a one-cell advance but
// draw past it, so text centring shifts the icon right; the sidebar translates it back.
// Usage: node glyphs.mjs "<font family>"  ->  {"font": path, "offsets": {"F0566": -0.2, ...}}
import { closeSync, openSync, readFileSync, readSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

function* privateUseGlyphs(font, cmap) {
  const subtables = [];
  for (let i = 0, count = font.readUInt16BE(cmap + 2); i < count; i++) {
    const at = cmap + 4 + i * 8;
    subtables.push({ platform: font.readUInt16BE(at), encoding: font.readUInt16BE(at + 2), offset: cmap + font.readUInt32BE(at + 4) });
  }
  const full = subtables.find(t => t.platform === 3 && t.encoding === 10 && font.readUInt16BE(t.offset) === 12)
    ?? subtables.find(t => t.platform === 0 && font.readUInt16BE(t.offset) === 12);
  const inPrivateUse = cp => PRIVATE_USE.some(([lo, hi]) => cp >= lo && cp <= hi);
  if (full) {
    for (let i = 0, groups = font.readUInt32BE(full.offset + 12); i < groups; i++) {
      const at = full.offset + 16 + i * 12;
      const start = font.readUInt32BE(at), end = font.readUInt32BE(at + 4), glyph = font.readUInt32BE(at + 8);
      for (let cp = start; cp <= end; cp++) if (inPrivateUse(cp)) yield [cp, glyph + cp - start];
    }
    return;
  }
  const bmp = subtables.find(t => t.platform === 3 && t.encoding === 1 && font.readUInt16BE(t.offset) === 4);
  if (!bmp) return;
  const segments = font.readUInt16BE(bmp.offset + 6) / 2;
  const ends = bmp.offset + 14, starts = ends + segments * 2 + 2, deltas = starts + segments * 2, ranges = deltas + segments * 2;
  for (let s = 0; s < segments; s++) {
    const start = font.readUInt16BE(starts + s * 2), end = font.readUInt16BE(ends + s * 2);
    const delta = font.readInt16BE(deltas + s * 2), range = font.readUInt16BE(ranges + s * 2);
    for (let cp = start; cp <= end && cp !== 0xffff; cp++) {
      if (!inPrivateUse(cp)) continue;
      let glyph;
      if (range === 0) glyph = (cp + delta) & 0xffff;
      else {
        const raw = font.readUInt16BE(ranges + s * 2 + range + (cp - start) * 2);
        glyph = raw === 0 ? 0 : (raw + delta) & 0xffff;
      }
      if (glyph) yield [cp, glyph];
    }
  }
}

export function measure(file) {
  const font = readFileSync(file);
  const map = tables((offset, length) => font.subarray(offset, offset + length));
  for (const tag of ['head', 'hhea', 'hmtx', 'maxp', 'cmap', 'loca', 'glyf']) {
    if (!map.has(tag)) throw new Error(`${path.basename(file)} has no ${tag} table (CFF fonts are not supported)`);
  }
  const head = map.get('head').offset;
  const unitsPerEm = font.readUInt16BE(head + 18);
  const longLoca = font.readInt16BE(head + 50) === 1;
  const metrics = font.readUInt16BE(map.get('hhea').offset + 34);
  const hmtx = map.get('hmtx').offset, loca = map.get('loca').offset, glyf = map.get('glyf').offset;
  const glyphs = font.readUInt16BE(map.get('maxp').offset + 4);
  const location = gid => longLoca ? font.readUInt32BE(loca + gid * 4) : font.readUInt16BE(loca + gid * 2) * 2;
  const offsets = {};
  for (const [cp, gid] of privateUseGlyphs(font, map.get('cmap').offset)) {
    if (gid >= glyphs || location(gid) === location(gid + 1)) continue;
    const advance = font.readUInt16BE(hmtx + Math.min(gid, metrics - 1) * 4);
    const at = glyf + location(gid);
    const ink = (font.readInt16BE(at + 2) + font.readInt16BE(at + 6)) / 2;
    const shift = Math.round(((advance / 2 - ink) / unitsPerEm) * 1000) / 1000;
    if (Math.abs(shift) >= 0.02) offsets[cp.toString(16).toUpperCase()] = shift;
  }
  return offsets;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const family = process.argv[2];
  if (!family) { process.stderr.write('Usage: glyphs.mjs <font family>\n'); process.exit(1); }
  const font = findFont(family);
  process.stdout.write(JSON.stringify(font ? { font, offsets: measure(font) } : { font: null, offsets: {} }) + '\n');
}
