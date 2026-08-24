import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const wasmPath = new URL('../zig-out/extension/renderer.wasm', import.meta.url);
const bytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const wasm = instance.exports;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function render(source) {
  const sourceBytes = encoder.encode(source);
  const sourcePointer = wasm.allocateSource(sourceBytes.length);
  new Uint8Array(wasm.memory.buffer, sourcePointer, sourceBytes.length).set(sourceBytes);
  const outputPointer = wasm.renderMarkdown(sourceBytes.length);
  assert.equal(wasm.errorCode(), 0);
  const html = decoder.decode(
    new Uint8Array(wasm.memory.buffer, outputPointer, wasm.renderedLength())
  );
  wasm.releaseSource();
  return html;
}

test('exports the browser ABI', () => {
  for (const name of [
    'memory',
    'allocateSource',
    'renderMarkdown',
    'renderedLength',
    'errorCode',
    'releaseSource',
    'releaseOutput',
  ]) {
    assert.ok(name in wasm, `missing WebAssembly export: ${name}`);
  }
});

test('renders GFM-style features through WebAssembly', () => {
  const html = render(`# Hello

| Name | Value |
| --- | ---: |
| Zig | 42 |

- [x] WebAssembly

~~~zig
const answer = 42;
~~~
`);
  assert.match(html, /<h1>Hello<\/h1>/);
  assert.match(html, /<table>/);
  assert.match(html, /type="checkbox" checked="" disabled=""/);
  assert.match(html, /<li class="zig-md-task-item">/);
  assert.match(html, /class="language-zig"/);
});

test('reuses the renderer and replaces invalid UTF-8', () => {
  assert.equal(render('first'), '<p>first</p>\n');

  const sourcePointer = wasm.allocateSource(2);
  new Uint8Array(wasm.memory.buffer, sourcePointer, 2).set([0xe2, 0x82]);
  const outputPointer = wasm.renderMarkdown(2);
  assert.equal(wasm.errorCode(), 0);
  const html = decoder.decode(
    new Uint8Array(wasm.memory.buffer, outputPointer, wasm.renderedLength())
  );
  assert.equal(html, '<p>�</p>\n');
  wasm.releaseSource();
});
