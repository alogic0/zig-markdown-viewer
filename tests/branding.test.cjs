'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const projectRoot = path.join(__dirname, '..');

test('uses the M superscript z formula mark in vector and popup branding', () => {
  const favicon = readFileSync(path.join(projectRoot, 'extension/icons/favicon.svg'), 'utf8');
  const popup = readFileSync(path.join(projectRoot, 'extension/popup.html'), 'utf8');

  assert.match(favicon, /<text[^>]*>M<\/text>/);
  assert.match(favicon, /<text[^>]*>z<\/text>/);
  assert.match(popup, /<msup><mi>M<\/mi>/);
  assert.match(popup, /<mspace width="0\.2778em"><\/mspace><mi>z<\/mi>/);
});

test('ships square formula icons at every manifest size', () => {
  for (const size of [16, 32, 48, 128]) {
    const png = readFileSync(path.join(projectRoot, `extension/icons/icon${size}.png`));
    assert.equal(png.toString('ascii', 1, 4), 'PNG');
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
  }
});
