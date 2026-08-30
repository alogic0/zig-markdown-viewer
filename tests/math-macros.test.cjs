'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const macros = require('../extension/js/math-macros.js');

test('normalizes valid stored and edited macro definitions', () => {
  assert.deepEqual(macros.validate([{
    name: '\\f',
    replacement: '#1f(#2)',
    argumentCount: 2,
  }]), [{
    name: 'f',
    replacement: '#1f(#2)',
    argumentCount: 2,
  }]);
  assert.deepEqual(macros.validate([]), []);
});

test('rejects malformed duplicate and over-limit macro definitions', () => {
  assert.throws(() => macros.validate(null), /must be a list/);
  assert.throws(() => macros.validate([{
    name: '\\bad-name',
    replacement: 'x',
    argumentCount: 0,
  }]), /ASCII letter name/);
  assert.throws(() => macros.validate([
    { name: 'f', replacement: 'x', argumentCount: 0 },
    { name: '\\f', replacement: 'y', argumentCount: 0 },
  ]), /defined more than once/);
  assert.throws(() => macros.validate([{
    name: 'f',
    replacement: 'x',
    argumentCount: 10,
  }]), /between 0 and 9 arguments/);
  assert.throws(() => macros.validate([{
    name: 'f',
    replacement: 'x',
    argumentCount: '2',
  }]), /between 0 and 9 arguments/);
  assert.throws(() => macros.validate(Array.from(
    { length: macros.MAX_DEFINITIONS + 1 },
    (_, index) => ({ name: `m${index}`, replacement: 'x', argumentCount: 0 })
  )), /At most 256/);
  assert.throws(() => macros.validate([{
    name: 'large',
    replacement: 'x'.repeat(macros.MAX_CONFIG_BYTES),
    argumentCount: 0,
  }]), /exceeds 1 MiB/);
});

test('popup exposes add edit remove controls for custom macros', () => {
  const html = readFileSync(path.join(__dirname, '../extension/popup.html'), 'utf8');
  const script = readFileSync(path.join(__dirname, '../extension/js/popup.js'), 'utf8');
  const contentScript = readFileSync(path.join(__dirname, '../extension/js/content.js'), 'utf8');

  for (const id of [
    'add-math-macro',
    'math-macro-list',
    'math-macro-editor',
    'math-macro-name',
    'math-macro-arguments',
    'math-macro-replacement',
    'cancel-math-macro',
  ]) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
  assert.match(script, /storageSet\(\{ mathMacros: normalized \}\)/);
  assert.match(script, /edit\.addEventListener\('click'/);
  assert.match(script, /remove\.addEventListener\('click'/);
  assert.match(contentScript, /configureMathMacros\(nextMacros\)/);
  assert.match(contentScript, /renderCurrent\(\)/);
});
