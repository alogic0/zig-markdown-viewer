'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const policy = require('../extension/js/mathml-policy.js');

const ns = policy.namespace;

test('accepts only the generated MathML root contract', () => {
  assert.equal(policy.allowsElement('math', ns, [
    ['class', 'zig-math'],
    ['display', 'inline'],
  ], true), true);
  assert.equal(policy.allowsElement('math', ns, [
    ['display', 'block'],
    ['class', 'zig-math'],
  ], true), true);

  assert.equal(policy.allowsElement('math', ns, [['class', 'zig-math']], true), false);
  assert.equal(policy.allowsElement('math', ns, [
    ['class', 'zig-math'],
    ['display', 'inline'],
    ['onclick', 'alert(1)'],
  ], true), false);
  assert.equal(policy.allowsElement('math', 'http://www.w3.org/2000/svg', [
    ['class', 'zig-math'],
    ['display', 'inline'],
  ], true), false);
});

test('accepts only inert descendants and fixed spacing widths', () => {
  for (const name of [
    'mrow', 'mi', 'mn', 'mo', 'mtext', 'mfrac', 'msqrt', 'mroot', 'msub',
    'msup', 'msubsup', 'munder', 'mover', 'munderover', 'mtable', 'mtr', 'mtd',
  ]) {
    assert.equal(policy.allowsElement(name, ns, [], false), true, name);
  }
  for (const width of [
    '-0.1667em', '0.1667em', '0.2222em', '0.2778em', '0.3333em', '1em', '2em',
  ]) {
    assert.equal(policy.allowsElement('mspace', ns, [['width', width]], false), true, width);
  }

  assert.equal(policy.allowsElement('annotation-xml', ns, [], false), false);
  assert.equal(policy.allowsElement('script', ns, [], false), false);
  assert.equal(policy.allowsElement('mi', ns, [['href', 'javascript:alert(1)']], false), false);
  assert.equal(policy.allowsElement('mspace', ns, [['width', '100vw']], false), false);
  assert.equal(policy.allowsElement('mtd', ns, [['columnalign', 'right']], false), true);
  assert.equal(policy.allowsElement('mtd', ns, [['columnalign', 'left']], false), true);
  assert.equal(policy.allowsElement('mtd', ns, [['columnalign', 'center']], false), false);
  assert.equal(policy.allowsElement('mtr', ns, [['columnalign', 'right']], false), false);
});
