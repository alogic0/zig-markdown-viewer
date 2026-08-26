import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const wasmPath = new URL('../zig-out/extension/renderer.wasm', import.meta.url);
const bytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const wasm = instance.exports;
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });

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
  assert.match(html, /<h1 id="hello"><a class="zig-md-heading-anchor" href="#hello"/);
  assert.match(html, /<table>/);
  assert.match(html, /type="checkbox" checked="" disabled=""/);
  assert.match(html, /<li class="zig-md-task-item">/);
  assert.match(html, /class="language-zig"/);
  assert.match(html, /class="syntax-keyword">const<\/span>/);
});

test('highlights core and optional languages through WebAssembly', () => {
  const html = render(`~~~js
const answer = 42;
~~~

~~~html
<main class="page">Hello</main>
~~~

~~~css
.page { color: red; }
~~~

~~~ziggy
answer = 42
~~~

~~~toml
title = "demo"
~~~

~~~yml
name: "demo"
enabled: true
~~~

~~~py
def greet(name: str):
    return name.upper()
~~~

~~~sql
SELECT count("user_id") WHERE id = :id;
~~~

~~~terraform
enabled = true
name = format("app")
~~~

~~~makefile
app:
	echo hi
~~~

~~~cmake
if(ON)
  message("ready")
endif()
~~~

~~~kdl
service image="demo" enabled=true
~~~

~~~sshconfig
Host demo
  Port 2222
~~~

~~~git-commit
feat: render safely
~~~

~~~docker
RUN echo "$HOME"
~~~
`);
  assert.match(html, /class="syntax-keyword">const<\/span>/);
  assert.match(html, /syntax-tag/);
  assert.match(html, /syntax-property/);
  assert.match(html, /class="language-toml"/);
  assert.match(html, /class="syntax-property">title<\/span>/);
  assert.match(html, /class="language-yml"/);
  assert.match(html, /class="syntax-property">enabled<\/span>/);
  assert.match(html, /class="syntax-boolean">true<\/span>/);
  assert.match(html, /class="language-py"/);
  assert.match(html, /class="syntax-parameter">name<\/span>/);
  assert.match(html, /class="syntax-function syntax-property">upper<\/span>/);
  assert.match(html, /class="language-sql"/);
  assert.match(html, /class="syntax-parameter">:id<\/span>/);
  assert.match(html, /class="language-terraform"/);
  assert.match(html, /class="syntax-function">format<\/span>/);
  assert.match(html, /class="language-makefile"/);
  assert.match(html, /syntax-builtin syntax-embedded syntax-function">echo<\/span>/);
  assert.match(html, /class="language-cmake"/);
  assert.match(html, /class="syntax-function">message<\/span>/);
  assert.match(html, /class="language-kdl"/);
  assert.match(html, /class="syntax-tag">service<\/span>/);
  assert.match(html, /class="language-sshconfig"/);
  assert.match(html, /class="syntax-property">Port<\/span>/);
  assert.match(html, /class="language-git-commit"/);
  assert.match(html, /syntax-keyword syntax-markup-heading">feat<\/span>/);
  assert.match(html, /class="language-docker"/);
  assert.match(html, /syntax-builtin syntax-embedded syntax-function">echo<\/span>/);
});

test('preserves exact structural highlighting through WebAssembly', () => {
  assert.equal(
    render(`~~~javascript
const answer = thing.value();
~~~
`),
    '<pre data-language="javascript"><code class="language-javascript">' +
      '<span class="syntax-keyword">const</span> ' +
      '<span class="syntax-variable">answer</span> ' +
      '<span class="syntax-operator">=</span> ' +
      '<span class="syntax-variable">thing</span>' +
      '<span class="syntax-punctuation">.</span>' +
      '<span class="syntax-function syntax-property">value</span>' +
      '<span class="syntax-punctuation">(</span>' +
      '<span class="syntax-punctuation">)</span>' +
      '<span class="syntax-punctuation">;</span>\n' +
      '</code></pre>\n'
  );
});

test('keeps Unicode Bash source intact through highlighting', () => {
  const html = render(`~~~bash
├── Builds Docker image
~~~
`);
  assert.match(html, /<code class="language-bash">├── /);
  assert.doesNotMatch(html, /�/);
});

test('leaves experimental and unsupported dialect fences plain', () => {
  const html = render(`~~~jsx
const node = <main />;
~~~
`);
  assert.match(html, /class="language-jsx">const node = &lt;main \/&gt;;/);
  assert.doesNotMatch(html, /syntax-/);
});

test('generates stable heading ids and anchors in WebAssembly', () => {
  const html = render(`# 2.1 Core Directories and Purposes
# Café déjà
# Café *déjà*
# ПРИВЕТ
# مرحبا، ١٢٣ 😀
`);
  assert.match(html, /id="21-core-directories-and-purposes"/);
  assert.match(html, /id="cafe-deja"/);
  assert.match(html, /id="cafe-deja-2"/);
  assert.match(html, /id="привет"/);
  assert.match(html, /id="مرحبا-١٢٣"/);
  assert.match(html, /aria-label="Link to Café déjà"/);
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
