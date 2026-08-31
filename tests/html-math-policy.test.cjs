'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const policy = require('../extension/js/html-math-policy.js');

const ns = policy.namespace;

test('accepts only the fixed visual root contract', () => {
  for (const mode of ['zig-math-inline', 'zig-math-display']) {
    assert.equal(policy.allowsElement('span', ns, [
      ['class', `zig-math-html ${mode}`],
      ['aria-hidden', 'true'],
    ], true), true);
  }
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-html zig-math-inline'],
    ['aria-hidden', 'false'],
  ], true), false);
  assert.equal(policy.allowsElement('div', ns, [
    ['class', 'zig-math-html zig-math-inline'],
    ['aria-hidden', 'true'],
  ], true), false);
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-html zig-math-inline attacker'],
    ['aria-hidden', 'true'],
  ], true), false);
});

test('accepts generated box classes and canonical em styles', () => {
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-list zig-math-hlist'],
    ['style', 'width:1.25em;height:2em;vertical-align:-0.5em'],
  ], false), true);
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-shift'],
    ['style', 'margin-left:-0.166666em;top:0em'],
  ], false), true);
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-delimiter zig-math-delimiter-vertical zig-math-assembled'],
    ['style', 'width:1em;height:3em;vertical-align:-1em'],
  ], false), true);
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-scope zig-math-color-purple'],
  ], false), true);
  assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-scope zig-math-list'],
  ], false), false);

  for (const style of [
    'width:1px',
    'width:calc(1em + 1px)',
    'width:1em;background:url(javascript:alert(1))',
    'width:01em',
    'width:1.1234567em',
  ]) assert.equal(policy.allowsElement('span', ns, [
    ['class', 'zig-math-kern'],
    ['style', style],
  ], false), false, style);
});

test('accepts only Plane 15 private-use glyph text', () => {
  assert.equal(policy.allowsGlyphText(String.fromCodePoint(0xF0000, 0xF1234)), true);
  assert.equal(policy.allowsGlyphText('x'), false);
  assert.equal(policy.allowsGlyphText(String.fromCodePoint(0x100000)), false);
  assert.equal(policy.allowsGlyphText(''), false);
});
