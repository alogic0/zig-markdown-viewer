'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

function read(relativePath) {
  return readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('extension settings exclude math macros and clear legacy definitions', () => {
  const manifest = read('extension/manifest.json');
  const popup = read('extension/popup.html');
  const popupScript = read('extension/js/popup.js');
  const contentScript = read('extension/js/content.js');
  const wasmBridge = read('extension/js/wasm.js');
  const background = read('extension/js/background.js');

  assert.doesNotMatch(manifest, /math-macros\.js/);
  assert.doesNotMatch(popup, /math-macro|Custom math macros/);
  assert.doesNotMatch(popupScript, /mathMacros|configureMathMacros/);
  assert.doesNotMatch(contentScript, /mathMacros|configureMathMacros/);
  assert.doesNotMatch(wasmBridge, /configureMathMacros|allocateMacroConfig/);
  assert.match(background, /chrome\.storage\.local\.remove\('mathMacros'\)/);
});
