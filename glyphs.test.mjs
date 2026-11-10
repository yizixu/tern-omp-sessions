import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { Font, Glyph, Path } from './vendor/opentype-2.0.0.min.mjs';
import { measure } from './glyphs.mjs';

test('fractionally scaled glyphs retain a complete, centered SVG outline', t => {
  const directory = mkdtempSync(path.join(tmpdir(), 'omp-glyph-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));

  // An asymmetric outline puts several vertices within floating-point noise of y = 8.
  const shape = new Path();
  shape.moveTo(208, 151);
  shape.lineTo(624, 151);
  shape.lineTo(624, 360);
  shape.lineTo(832, 360);
  shape.lineTo(832, 569);
  shape.lineTo(0, 569);
  shape.lineTo(0, 360);
  shape.lineTo(208, 360);
  shape.close();
  const font = new Font({
    familyName: 'Glyph regression', styleName: 'Regular', unitsPerEm: 1000,
    ascender: 800, descender: -200,
    glyphs: [
      new Glyph({ name: '.notdef', advanceWidth: 1000, path: new Path() }),
      new Glyph({ name: 'pane', unicode: 0xe000, advanceWidth: 1000, path: shape }),
    ],
  });
  const file = path.join(directory, 'outline.ttf');
  writeFileSync(file, Buffer.from(font.toArrayBuffer()));

  const data = measure(file, [0xe000]).paths.E000;
  assert.equal(typeof data, 'string');
  assert.doesNotMatch(data, /NaN|Infinity/);
  const rendered = new Path();
  rendered.fromSVG(data, { flipY: false });
  const bounds = rendered.getBoundingBox();
  assert.deepEqual([bounds.x1, bounds.y1, bounds.x2, bounds.y2], [2, 4.99, 14, 11.01]);
  const vertices = rendered.commands.filter(command => command.type === 'L');
  assert.ok(vertices.some(command => command.x === 2 && command.y === 8), 'left step survives export');
  assert.ok(vertices.some(command => command.x === 14 && command.y === 8), 'right step survives export');
});
