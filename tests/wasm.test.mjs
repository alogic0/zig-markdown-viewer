import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { Renderer } = require('../extension/js/wasm.js');

const wasmPath = new URL('../zig-out/extension/renderer.wasm', import.meta.url);
const bytes = await readFile(wasmPath);
const module = new WebAssembly.Module(bytes);
const instance = new WebAssembly.Instance(module, {});
const wasm = instance.exports;
const browserRenderer = new Renderer(instance);
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
  assert.equal(WebAssembly.Module.customSections(module, 'name').length, 0);
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

test('renders document-local macros through WebAssembly', () => {
  const source = `\`\`\`math-macros
\\newcommand{\\f}[2]{#1f(#2)}
\`\`\`

~~~math
% \\f is defined as #1f(#2) using the macro
\\f\\relax{x} = \\int_{-\\infty}^\\infty
    \\f\\hat\\xi\\,e^{2 \\pi i \\xi x}
    \\,d\\xi
~~~
`;
  for (const html of [render(source), browserRenderer.render(source)]) {
    assert.match(html, /<math class="zig-math" display="block">/);
    assert.match(html, /<mover>/);
    assert.match(html, /<mi>ξ<\/mi>/);
    assert.doesNotMatch(html, /math-macros|newcommand|language-math/);
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

test('renders inline and fenced display math through WebAssembly', () => {
  const html = render(`Inline $x_1 + \\alpha$.

~~~math
\\frac{x}{\\sqrt[3]{y}}
~~~

Alphabets $\\mathrm{d}\\mathbf{x}\\mathbb{R}\\mathcal{F}$.
`);
  assert.match(html, /<math class="zig-math" display="inline">/);
  assert.match(html, /<msub>/);
  assert.match(html, /<mi>α<\/mi>/);
  assert.match(html, /<math class="zig-math" display="block">/);
  assert.match(html, /<mfrac>/);
  assert.match(html, /<mroot>/);
  assert.match(html, /<mi mathvariant="normal">d<\/mi>/);
  assert.match(html, /<mi>𝐱<\/mi>/);
  assert.match(html, /<mi>ℝ<\/mi>/);
  assert.match(html, /<mi>ℱ<\/mi>/);
});

test('renders AMS table environments through WebAssembly', () => {
  const html = render(`~~~math
\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}
~~~

~~~math
\\begin{cases}x&x>0\\\\-x&x\\le0\\end{cases}
~~~

~~~math
\\begin{aligned}x&=1\\\\y&=2\\end{aligned}
~~~

~~~math
\\begin{smallmatrix}a&b\\\\c&d\\end{smallmatrix}
~~~
`);
  assert.equal((html.match(/<mtable>/g) || []).length, 4);
  assert.match(html, /<mo>\(<\/mo>/);
  assert.match(html, /<mo>\{<\/mo><mtable>/);
  assert.match(html, /<mtd columnalign="right">/);
  assert.match(html, /<mtd columnalign="left">/);
  assert.doesNotMatch(html, /language-math/);
});

test('renders expanded math command families through WebAssembly', () => {
  const html = render(`~~~math
\\forall x\\exists y\\nexists z\\implies x\\iff y
a\\ll b\\cong c\\parallel d\\perp e
\\iint_A+\\oint_C+\\bigcup_i
\\uparrow+\\nearrow+\\hookrightarrow
a\\mp b\\circ c\\sqcup d\\triangleleft e
\\aleph+\\hbar+\\ell+\\Re+\\Im+\\ldots+\\vdots+\\ddots
a\\pmod{n}+\\overbrace{x+y}^{k}+\\underbrace{a+b}_{m}
\\sum_{\\substack{i=0\\\\j<n}}+\\mathfrak{AbRz7}
\\int\\limits_0^1+\\sum\\nolimits_i^n
~~~
`);
  for (const fragment of [
    '<mo>∀</mo>',
    '<mo>≪</mo>',
    '<mo>∬</mo>',
    '<mo>↪</mo>',
    '<mo>⊔</mo>',
    '<mi>ℵ</mi>',
    '<mi mathvariant="normal">mod</mi>',
    '<mo stretchy="true">⏞</mo>',
    '<munder accentunder="true">',
    '<munder><mo>∑</mo><mrow><mtable>',
    '<mi>𝔄</mi>',
    '<munderover><mo>∫</mo><mn>0</mn><mn>1</mn></munderover>',
    '<msubsup><mo>∑</mo><mi>i</mi><mi>n</mi></msubsup>',
  ]) assert.ok(html.includes(fragment), fragment);
});

test('renders extended math structures through WebAssembly', () => {
  const html = render(`~~~math
\\mathbf{\\alpha}+\\mathit{\\vartheta}
\\dfrac{1}{2}+\\tfrac{1}{2}+\\binom{n}{k}
\\left\\langle x\\right\\rangle+\\left\\lfloor y\\right\\rfloor
\\left\\lceil z\\right\\rceil+\\left\\Vert v\\right\\Vert
\\operatorname{rank}_A+\\widehat{xyz}+\\widetilde{ab}
\\displaystyle\\sum_i+\\textstyle{x}+\\scriptstyle{y}+\\scriptscriptstyle{z}
~~~
`);
  for (const fragment of [
    '<mi>𝛂</mi>',
    '<mi>𝜗</mi>',
    '<mfrac displaystyle="true">',
    '<mfrac displaystyle="false">',
    '<mfrac linethickness="0">',
    '<mo>⟨</mo>',
    '<mo>⌊</mo>',
    '<mo>⌈</mo>',
    '<mo>‖</mo>',
    '<mi mathvariant="normal">rank</mi>',
    '<mover accent="true">',
    '<mo stretchy="true">^</mo>',
    '<mstyle displaystyle="true" scriptlevel="0">',
    '<mstyle displaystyle="false" scriptlevel="2">',
  ]) assert.ok(html.includes(fragment), fragment);
});

test('keeps malformed math as escaped literal source', () => {
  assert.equal(
    render('Broken $\\frac{x}$ here.\n'),
    '<p>Broken $\\frac{x}$ here.</p>\n'
  );
  assert.equal(
    render('~~~latex\n\\text{a<&\n~~~\n'),
    '<pre><code class="language-math">\\text{a&lt;&amp;\n</code></pre>\n'
  );
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

~~~gitrebase
pick abc123 render safely
exec echo done
~~~

~~~gettext
msgid "file"
msgstr[0] "Datei"
~~~

~~~ninja
rule cc
  command = cc $in
build app: cc main.c
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
  assert.match(html, /class="language-gitrebase"/);
  assert.match(html, /class="syntax-constant">abc123<\/span>/);
  assert.match(html, /class="language-gettext"/);
  assert.match(html, /class="syntax-keyword">msgstr<\/span>/);
  assert.match(html, /class="language-ninja"/);
  assert.match(html, /class="syntax-type">cc<\/span>/);
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

test('renders newly verified language families through WebAssembly', () => {
  const html = render(`~~~c++
class Widget { void render(int value) {} };
~~~

~~~mlir
func.func @add(%lhs: i32, %rhs: i32) -> i32
~~~

~~~tablegen
def ADD : Instruction { let Pattern = !if(true, $lhs, $rhs); }
~~~

~~~fortran
MODULE Demo
INTEGER :: Count
END MODULE Demo
~~~

~~~vue
<script>function greet(name) { return name; }</script><p>{{ greet(user.name) }}</p>
~~~

~~~astro
---
const title = makeTitle(user.name);
---
<h1>{title}</h1>
~~~
`);

  assert.match(html, /class="language-c\+\+"/);
  assert.match(html, /class="syntax-type">Widget<\/span>/);
  assert.match(html, /class="syntax-parameter">value<\/span>/);
  assert.match(html, /class="language-mlir"/);
  assert.match(html, /class="syntax-function">@add<\/span>/);
  assert.match(html, /class="syntax-variable">%lhs<\/span>/);
  assert.match(html, /class="language-tablegen"/);
  assert.match(html, /class="syntax-constant">ADD<\/span>/);
  assert.match(html, /class="syntax-builtin">!if<\/span>/);
  assert.match(html, /class="language-fortran"/);
  assert.match(html, /class="syntax-keyword">MODULE<\/span>/);
  assert.match(html, /class="language-vue"/);
  assert.match(html, /syntax-embedded syntax-function">greet<\/span>/);
  assert.match(html, /class="language-astro"/);
  assert.match(html, /syntax-embedded syntax-function">makeTitle<\/span>/);
});

test('renders PHP Objective-C Nix and Fish structural roles through WebAssembly', () => {
  const html = render(`~~~php
<main><?php class Greeter { function greet(string $name) { return new Result(); } } ?></main>
~~~

~~~objective-c
@interface Greeter : NSObject
@property(nonatomic, copy) NSString *prefix;
- (NSString *)greet:(NSString *)name;
@end
~~~

~~~nixos
let render = { name }: { service.title = "Hello \${name}"; }; in render
~~~

~~~fish-shell
function greet --argument-names name
    printf '%s' $name | string collect
end
~~~
`);

  assert.match(html, /class="language-php"/);
  assert.match(html, /class="syntax-embedded syntax-tag">main<\/span>/);
  assert.match(html, /syntax-embedded syntax-type syntax-variable">Greeter<\/span>/);
  assert.match(html, /syntax-embedded syntax-parameter syntax-variable">\$name<\/span>/);
  assert.match(html, /syntax-constructor syntax-embedded syntax-function">Result<\/span>/);
  assert.match(html, /class="language-objective-c"/);
  assert.match(html, /class="syntax-keyword">@interface<\/span>/);
  assert.match(html, /class="syntax-property syntax-variable">prefix<\/span>/);
  assert.match(html, /class="syntax-parameter syntax-variable">name<\/span>/);
  assert.match(html, /class="language-nixos"/);
  assert.match(html, /class="syntax-variable">render<\/span>/);
  assert.match(html, /class="syntax-property">service<\/span>/);
  assert.match(html, /syntax-special syntax-string">\$\{<\/span>/);
  assert.match(html, /class="language-fish-shell"/);
  assert.match(html, /class="syntax-function">greet<\/span>/);
  assert.match(html, /class="syntax-parameter">name<\/span>/);
  assert.match(html, /syntax-builtin syntax-function">printf<\/span>/);
});

test('renders GDScript Nushell AWK and Typst structural roles through WebAssembly', () => {
  const html = render(`~~~gdscript
class_name Player
func move(direction: Vector2):
    return direction.normalized()
~~~

~~~nu
def main [input: path] { open $input | lines }
~~~

~~~awk
$1 ~ /^[0-9]+$/ { print normalize($1 / 2) }
~~~

~~~typst
#let badge(body) = box()[#body]
= Report <report>
~~~
`);

  assert.match(html, /class="language-gdscript"/);
  assert.match(html, /class="syntax-type">Player<\/span>/);
  assert.match(html, /class="syntax-parameter">direction<\/span>/);
  assert.match(html, /class="language-nu"/);
  assert.match(html, /class="syntax-function">main<\/span>/);
  assert.match(html, /class="syntax-parameter">input<\/span>/);
  assert.match(html, /class="language-awk"/);
  assert.match(html, /class="syntax-string">\/\^\[0-9\]\+\$\/<\/span>/);
  assert.match(html, /class="syntax-function">normalize<\/span>/);
  assert.match(html, /class="language-typst"/);
  assert.match(html, /class="syntax-embedded syntax-function">badge<\/span>/);
  assert.match(html, /class="syntax-label">&lt;report&gt;<\/span>/);
});

test('renders Elixir Julia Haskell and Perl structural roles through WebAssembly', () => {
  const html = render(`~~~elixir
defmodule Demo.Worker do
  def run(input), do: Regex.match?(~r/foo/, input)
end
~~~

~~~julia
module Geometry
function area(circle::Circle)
    @assert circle.radius > 0
end
end
~~~

~~~haskell
module Demo.Shapes where
data Shape = Circle Double
area shape = 1
~~~

~~~perl
package Demo::Worker;
sub run ($input) { my $pattern = qr/foo/; say $input; }
~~~
`);

  assert.match(html, /class="language-elixir"/);
  assert.match(html, /class="syntax-namespace">Demo<\/span>/);
  assert.match(html, /class="language-julia"/);
  assert.match(html, /syntax-attribute syntax-macro">@assert<\/span>/);
  assert.match(html, /class="language-haskell"/);
  assert.match(html, /class="syntax-constructor">Circle<\/span>/);
  assert.match(html, /class="language-perl"/);
  assert.match(html, /syntax-parameter syntax-variable">\$input<\/span>/);
  assert.match(html, /syntax-special syntax-string">qr<\/span>/);
});

test('renders OCaml and F# structural roles through WebAssembly', () => {
  const html = render(`~~~ocaml
module Geometry = struct
  type shape = Circle of float
  let area radius = radius *. radius
end
~~~

~~~fsharp
namespace Demo.Geometry
type Shape = Circle of radius: float
let area shape = shape
~~~
`);

  assert.match(html, /class="language-ocaml"/);
  assert.match(html, /class="syntax-namespace">Geometry<\/span>/);
  assert.match(html, /class="syntax-function">area<\/span>/);
  assert.match(html, /class="language-fsharp"/);
  assert.match(html, /class="syntax-namespace">Demo<\/span>/);
  assert.match(html, /class="syntax-namespace">Geometry<\/span>/);
  assert.match(html, /class="syntax-property">radius<\/span>/);
  assert.match(html, /class="syntax-parameter">shape<\/span>/);
});

test('renders Gleam structural roles through WebAssembly', () => {
  const html = render(`~~~gleam
import gleam/result
import gleam/string as text
pub fn render(person: Person) -> String {
  let Person(name, enabled) = person
  use suffix <- result.try(Ok("!"))
  let updated = Person(..person, enabled: False)
  <<name:utf8>> |> text.append(suffix)
}
~~~
`);

  assert.match(html, /class="language-gleam"/);
  assert.match(html, /class="syntax-namespace">result<\/span>/);
  assert.match(html, /class="syntax-namespace">text<\/span>/);
  assert.match(html, /class="syntax-function">render<\/span>/);
  assert.match(html, /class="syntax-parameter">suffix<\/span>/);
  assert.match(html, /class="syntax-constructor">Person<\/span>/);
  assert.match(html, /class="syntax-property">enabled<\/span>/);
  assert.match(html, /class="syntax-attribute">utf8<\/span>/);
  assert.match(html, /class="syntax-function">append<\/span>/);
  assert.doesNotMatch(html, /�/);
});

test('renders D structural roles through WebAssembly', () => {
  const html = render(`~~~d
module demo.render;
struct Item {
  string name;
  int total(int delta) { return delta; }
}
Item make_item(string name) { return Item(name); }
~~~
`);

  assert.match(html, /class="language-d"/);
  assert.match(html, /class="syntax-namespace">render<\/span>/);
  assert.match(html, /class="syntax-type">Item<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-function">total<\/span>/);
  assert.match(html, /class="syntax-parameter">delta<\/span>/);
  assert.match(html, /class="syntax-constructor">Item<\/span>/);
});

test('renders V structural roles through WebAssembly', () => {
  const html = render(`~~~v
module main
import time
struct Item { value string }
fn (item Item) total(delta int) int { return item.value.len + delta }
fn make_item(name string) Item { return Item{ value: name } }
~~~
`);

  assert.match(html, /class="language-v"/);
  assert.match(html, /class="syntax-namespace">main<\/span>/);
  assert.match(html, /class="syntax-namespace">time<\/span>/);
  assert.match(html, /class="syntax-type">Item<\/span>/);
  assert.match(html, /class="syntax-property">value<\/span>/);
  assert.match(html, /class="syntax-function">total<\/span>/);
  assert.match(html, /class="syntax-parameter">delta<\/span>/);
  assert.match(html, /class="syntax-constructor">Item<\/span>/);
});

test('renders Odin structural roles through WebAssembly', () => {
  const html = render(`~~~odin
package main
Item :: struct { value: string }
total :: proc(item: Item, delta: int) -> int { return item.value.len + delta }
make_item :: proc(name: string) -> Item { return Item{value = name} }
answer :: 42
~~~
`);

  assert.match(html, /class="language-odin"/);
  assert.match(html, /class="syntax-namespace">main<\/span>/);
  assert.match(html, /class="syntax-type">Item<\/span>/);
  assert.match(html, /class="syntax-property">value<\/span>/);
  assert.match(html, /class="syntax-function">total<\/span>/);
  assert.match(html, /class="syntax-parameter">delta<\/span>/);
  assert.match(html, /class="syntax-constructor">Item<\/span>/);
  assert.match(html, /class="syntax-constant">answer<\/span>/);
});

test('renders C3 structural roles through WebAssembly', () => {
  const html = render(`~~~c3
module demo::render;
import std::io;
struct Item { String value; int count; }
fn int total(Item item, int delta) { return item.count + delta; }
fn Item make_item(String name) { io::printfn(name); return { .value = name }; }
~~~
`);

  assert.match(html, /class="language-c3"/);
  assert.match(html, /class="syntax-namespace">render<\/span>/);
  assert.match(html, /class="syntax-type">Item<\/span>/);
  assert.match(html, /class="syntax-property">value<\/span>/);
  assert.match(html, /class="syntax-function">total<\/span>/);
  assert.match(html, /class="syntax-parameter">delta<\/span>/);
  assert.match(html, /class="syntax-function">printfn<\/span>/);
});

test('renders Elm structural roles through WebAssembly', () => {
  const html = render(`~~~elm
module Demo.Profile exposing (Profile, Status(..), render)
import Html as H
type alias Profile = { name : String, enabled : Bool }
type Status = Ready | Failed String
render : Profile -> String
render profile = H.text profile.name
~~~
`);

  assert.match(html, /class="language-elm"/);
  assert.match(html, /class="syntax-namespace">Demo<\/span>/);
  assert.match(html, /class="syntax-namespace">Profile<\/span>/);
  assert.match(html, /class="syntax-type">Profile<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-constructor">Ready<\/span>/);
  assert.match(html, /class="syntax-function">render<\/span>/);
  assert.match(html, /class="syntax-parameter">profile<\/span>/);
  assert.match(html, /class="syntax-namespace">H<\/span>/);
});

test('renders PureScript structural roles through WebAssembly', () => {
  const html = render(`~~~purescript
module Demo.Profile where
import Data.Maybe as M
type Profile = { name :: String, enabled :: Boolean }
data Status = Ready | Failed String
newtype User = User { name :: String }
render :: Profile -> String
render profile = M.fromMaybe "unknown" (Just profile.name)
~~~
`);

  assert.match(html, /class="language-purescript"/);
  assert.match(html, /class="syntax-namespace">Demo<\/span>/);
  assert.match(html, /class="syntax-type">Profile<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-constructor">Ready<\/span>/);
  assert.match(html, /class="syntax-constructor">User<\/span>/);
  assert.match(html, /class="syntax-function">render<\/span>/);
  assert.match(html, /class="syntax-parameter">profile<\/span>/);
  assert.match(html, /class="syntax-namespace">M<\/span>/);
});

test('renders SystemVerilog structural roles through WebAssembly', () => {
  const html = render(`~~~systemverilog
\`define DEFAULT_WIDTH 8
package demo_pkg;
  typedef enum logic [1:0] { IDLE, RUN } state_t;
endpackage
module demo #(parameter int WIDTH = \`DEFAULT_WIDTH) (input logic clk);
  import demo_pkg::*;
  state_t state;
  function int add(input int lhs, input int rhs); return lhs + rhs; endfunction
  assign ready = state.valid;
  initial $display("ready", ready);
endmodule
~~~
`);

  assert.match(html, /class="language-systemverilog"/);
  assert.match(html, /class="syntax-macro">`define<\/span>/);
  assert.match(html, /class="syntax-namespace">demo_pkg<\/span>/);
  assert.match(html, /class="syntax-type">demo<\/span>/);
  assert.match(html, /class="syntax-constant">WIDTH<\/span>/);
  assert.match(html, /class="syntax-parameter">clk<\/span>/);
  assert.match(html, /class="syntax-type">state_t<\/span>/);
  assert.match(html, /class="syntax-function">add<\/span>/);
  assert.match(html, /class="syntax-property">valid<\/span>/);
  assert.match(html, /class="syntax-function">\$display<\/span>/);
});

test('renders Common Lisp structural roles through WebAssembly', () => {
  const html = render(`~~~commonlisp
(defpackage demo (:use :cl))
(defclass person () ((name :initarg :name)))
(defun greet (person &optional prefix) (format nil "~a" person))
(defmacro withperson ((name value) &body body) \`(let ((,name ,value)) ,@body))
(let ((message "ready")) (greet message))
~~~
`);

  assert.match(html, /class="language-commonlisp"/);
  assert.match(html, /class="syntax-namespace">demo<\/span>/);
  assert.match(html, /class="syntax-type">person<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-function">greet<\/span>/);
  assert.match(html, /class="syntax-parameter">person<\/span>/);
  assert.match(html, /class="syntax-macro">withperson<\/span>/);
  assert.match(html, /class="syntax-variable">message<\/span>/);
});

test('renders Scheme structural roles through WebAssembly', () => {
  const html = render(`~~~scheme
(define-library (demo core)
  (import (scheme base))
  (begin
    (define-record-type person (makeperson name) person? (name personname))
    (define (greet person) (let ((message "ready")) message))
    (define-syntax whenready (syntax-rules () ((_ body) body)))))
~~~
`);

  assert.match(html, /class="language-scheme"/);
  assert.match(html, /class="syntax-namespace">demo<\/span>/);
  assert.match(html, /class="syntax-type">person<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-function">greet<\/span>/);
  assert.match(html, /class="syntax-parameter">person<\/span>/);
  assert.match(html, /class="syntax-variable">message<\/span>/);
  assert.match(html, /class="syntax-macro">whenready<\/span>/);
});

test('renders Nim structural roles through WebAssembly', () => {
  const html = render(`~~~nim
import std/strformat
type
  Person* = object
    name*: string
const Limit* = 42
proc render*(person: Person, prefix: string): string {.inline.} = prefix & person.name
proc makePerson(name: string): Person = Person(name: name)
~~~
`);

  assert.match(html, /class="language-nim"/);
  assert.match(html, /class="syntax-namespace">std<\/span>/);
  assert.match(html, /class="syntax-type">Person<\/span>/);
  assert.match(html, /class="syntax-property">name<\/span>/);
  assert.match(html, /class="syntax-constant">Limit<\/span>/);
  assert.match(html, /class="syntax-function">render<\/span>/);
  assert.match(html, /class="syntax-parameter">person<\/span>/);
  assert.match(html, /class="syntax-constructor">Person<\/span>/);
});

test('renders verified Assembly and NASM roles through WebAssembly', () => {
  const html = render(`~~~asm
.macro save reg
  push \\reg
.endm
.globl start
start:
  mov $42, %rax
  call render
~~~

~~~nasm
%define COUNT 42
section .text
global start
start:
  mov rax, COUNT
  jmp .done
.done:
  ret
~~~
`);

  assert.match(html, /class="language-asm"/);
  assert.match(html, /class="syntax-macro">\.macro<\/span>/);
  assert.match(html, /class="syntax-type">%rax<\/span>/);
  assert.match(html, /class="syntax-label">render<\/span>/);
  assert.match(html, /class="language-nasm"/);
  assert.match(html, /class="syntax-macro">%define<\/span>/);
  assert.match(html, /class="syntax-macro">COUNT<\/span>/);
  assert.match(html, /class="syntax-label">\.done<\/span>/);
});

test('renders OpenSCAD structural roles through WebAssembly', () => {
  const html = render(`~~~openscad
module rounded_box(size = [1, 2, 3], radius = 1) {
  translate([0, 0, radius]) cube(size = size, center = true);
}
function doubled(value) = value * 2;
steps = [for (item = [0:2]) doubled(item)];
let (offset = 2) rounded_box(radius = offset);
~~~
`);

  assert.match(html, /class="language-openscad"/);
  assert.match(html, /class="syntax-function">rounded_box<\/span>/);
  assert.match(html, /class="syntax-parameter">size<\/span>/);
  assert.match(html, /class="syntax-function">cube<\/span>/);
  assert.match(html, /class="syntax-property">center<\/span>/);
  assert.match(html, /class="syntax-function">doubled<\/span>/);
  assert.match(html, /class="syntax-variable">item<\/span>/);
  assert.match(html, /class="syntax-variable">offset<\/span>/);
});

test('renders Hare structural roles through WebAssembly', () => {
  const html = render(`~~~hare
use fmt;
type coords = struct { x: int, y: int };
def DEFAULT_LIMIT: size = 5;
fn translate(point: coords, dx: int) coords = {
  return coords { x = point.x + dx, y = point.y };
};
export fn main() void = {
  const origin = coords { x = 1, y = 2 };
  fmt::printfln("{}", translate(origin, DEFAULT_LIMIT))!;
};
~~~
`);

  assert.match(html, /class="language-hare"/);
  assert.match(html, /class="syntax-namespace">fmt<\/span>/);
  assert.match(html, /class="syntax-type">coords<\/span>/);
  assert.match(html, /class="syntax-property">x<\/span>/);
  assert.match(html, /class="syntax-constant">DEFAULT_LIMIT<\/span>/);
  assert.match(html, /class="syntax-function">translate<\/span>/);
  assert.match(html, /class="syntax-parameter">point<\/span>/);
  assert.match(html, /class="syntax-constructor">coords<\/span>/);
  assert.match(html, /class="syntax-variable">origin<\/span>/);
  assert.match(html, /class="syntax-function">printfln<\/span>/);
});

test('renders Nickel structural roles through WebAssembly', () => {
  const html = render(`~~~nickel
let make_item = fun name enabled => {
  name | String = name,
  nested.count = 42,
  message = "hello %{name}",
} in let item = make_item "demo" true in item.name
~~~
`);
  assert.match(html, /class="language-nickel"/);
  assert.match(html, /class="syntax-function">make_item<\/span>/);
  assert.match(html, /class="syntax-parameter">name<\/span>/);
  assert.match(html, /class="syntax-property">count<\/span>/);
  assert.match(html, /syntax-embedded syntax-string">%\{name\}<\/span>/);
  assert.match(html, /class="syntax-variable">item<\/span>/);
});

test('renders Agda structural roles through WebAssembly', () => {
  const html = render(`~~~agda
module Demo.Core where
open import Data.Nat
data Item : Set where
  item : Item
record Point : Set where
  field
    x : Set
select : Item → Item
select value = value
~~~
`);
  assert.match(html, /class="language-agda"/);
  assert.match(html, /class="syntax-namespace">Demo<\/span>/);
  assert.match(html, /class="syntax-namespace">Core<\/span>/);
  assert.match(html, /class="syntax-namespace">Data<\/span>/);
  assert.match(html, /class="syntax-namespace">Nat<\/span>/);
  assert.match(html, /class="syntax-type">Item<\/span>/);
  assert.match(html, /class="syntax-constructor">item<\/span>/);
  assert.match(html, /class="syntax-property">x<\/span>/);
  assert.match(html, /class="syntax-function">select<\/span>/);
  assert.match(html, /class="syntax-parameter">value<\/span>/);
  assert.match(html, /→/);
  assert.doesNotMatch(html, /�/);
});

test('renders Vimscript structural roles through WebAssembly', () => {
  const html = render(`~~~vim
vim9script
import autoload './util.vim' as util
def Render(name: string): string
  const message = util.Format(name)
  return message
enddef
function! s:Legacy(value)
  let l:item = a:value
  return s:Render(l:item)
endfunction
command! -nargs=1 Show call s:Render(<args>)
~~~
`);
  assert.match(html, /class="language-vim"/);
  assert.match(html, /class="syntax-namespace">util<\/span>/);
  assert.match(html, /class="syntax-function">Render<\/span>/);
  assert.match(html, /class="syntax-parameter">name<\/span>/);
  assert.match(html, /class="syntax-variable">message<\/span>/);
  assert.match(html, /class="syntax-function">Format<\/span>/);
  assert.match(html, /class="syntax-function">Legacy<\/span>/);
  assert.match(html, /class="syntax-variable">item<\/span>/);
  assert.match(html, /class="syntax-macro">Show<\/span>/);
});

test('renders Uxntal lexical roles through WebAssembly', () => {
  const html = render(`~~~uxntal
|0100
%emit-byte ( value -- ) { #18 DEO }
@main
  &loop
  #2a #01 ADD2k
  ,&loop JCN
  ;Screen/width DEI2
  "hello
  BRK
( outer ( nested ) comment )
~~~
`);
  assert.match(html, /class="language-uxntal"/);
  assert.match(html, /class="syntax-number">\|0100<\/span>/);
  assert.match(html, /class="syntax-macro">%emit-byte<\/span>/);
  assert.match(html, /class="syntax-label">@main<\/span>/);
  assert.match(html, /class="syntax-keyword">ADD2k<\/span>/);
  assert.match(html, /class="syntax-label">;Screen\/width<\/span>/);
  assert.match(html, /class="syntax-string">&quot;hello<\/span>/);
  assert.match(html, /class="syntax-comment">\( outer \( nested \) comment \)<\/span>/);
});

test('renders verified comment-tag roles through WebAssembly', () => {
  const html = render(`~~~comment
TODO(alice): preserve source for #123
NOTE: see https://example.test/docs
FIXME: escape <unsafe>& bytes
~~~
`);
  assert.match(html, /class="language-comment"/);
  assert.match(html, /class="syntax-special">TODO<\/span>/);
  assert.match(html, /class="syntax-constant">alice<\/span>/);
  assert.match(html, /class="syntax-number">#123<\/span>/);
  assert.match(html, /syntax-markup-link/);
  assert.match(html, /https:\/\/example\.test\/docs/);
  assert.match(html, /&lt;unsafe&gt;&amp;/);
});

test('renders verified DTD declaration roles through WebAssembly', () => {
  const html = render(`~~~dtd
<!ELEMENT note (to,from,heading,body)>
<!ATTLIST note id ID #REQUIRED status (draft|final) "draft">
<!ENTITY % shared "INCLUDE">
%shared;
<!ENTITY writer "Oleg &amp; Co.">
<!NOTATION gif SYSTEM "image/gif">
<![IGNORE[ <!ELEMENT ignored ANY> ]]>
<!-- comment -->
<?audit source?>
~~~
`);
  assert.match(html, /class="language-dtd"/);
  assert.match(html, /class="syntax-keyword">ELEMENT<\/span>/);
  assert.match(html, /class="syntax-tag">note<\/span>/);
  assert.match(html, /class="syntax-attribute">id<\/span>/);
  assert.match(html, /class="syntax-type">ID<\/span>/);
  assert.match(html, /class="syntax-constant">draft<\/span>/);
  assert.match(html, /syntax-escape/);
  assert.match(html, /class="syntax-comment">&lt;!\[<\/span>/);
  assert.match(html, /syntax-comment syntax-keyword">IGNORE<\/span>/);
  assert.match(html, /class="syntax-special">&lt;\?audit source\?&gt;<\/span>/);
});

test('renders structural CMake roles through WebAssembly', () => {
  const html = render(`~~~cmake
#[=[ structural example ]=]
function(build_target source)
  set(NAME "$ENV{HOME}")
  add_executable(app \${source})
  set_property(TARGET app PROPERTY CXX_STANDARD 23)
  target_compile_definitions(app PRIVATE "$<$<CONFIG:Debug>:DEBUG_BUILD>")
endfunction()
macro(enable_warnings target)
endmacro()
~~~
`);
  assert.match(html, /class="language-cmake"/);
  assert.match(html, /class="syntax-function">build_target<\/span>/);
  assert.match(html, /class="syntax-parameter">source<\/span>/);
  assert.match(html, /class="syntax-macro">enable_warnings<\/span>/);
  assert.match(html, /class="syntax-variable">NAME<\/span>/);
  assert.match(html, /syntax-variable">\$ENV\{HOME\}<\/span>/);
  assert.match(html, /class="syntax-type">app<\/span>/);
  assert.match(html, /class="syntax-property">CXX_STANDARD<\/span>/);
  assert.match(html, /syntax-embedded/);
  assert.match(html, /syntax-comment">#\[=\[ structural example \]=\]<\/span>/);
});

test('renders Fortran free and fixed form lexical syntax through WebAssembly', () => {
  const html = render(`~~~fortran
C fixed-form comment
  100 CONTINUE
     1 VALUE = Z'2A' + 1.25_real64
name = 'don''t'
if (.TRUE. .and. VALUE >= 0) VALUE = VALUE &
  & + 1
~~~
`);
  assert.match(html, /class="language-fortran"/);
  assert.match(html, /syntax-comment">C fixed-form comment<\/span>/);
  assert.match(html, /class="syntax-label">100<\/span>/);
  assert.match(html, /class="syntax-number">Z&#39;2A&#39;<\/span>/);
  assert.match(html, /class="syntax-number">1\.25_real64<\/span>/);
  assert.match(html, /syntax-escape syntax-string">&#39;&#39;<\/span>/);
  assert.match(html, /class="syntax-boolean">\.TRUE\.<\/span>/);
  assert.match(html, /class="syntax-operator">\.and\.<\/span>/);
});

test('renders structural Fortran roles through WebAssembly', () => {
  const html = render(`~~~fortran
module Geometry
  use, intrinsic :: iso_fortran_env
  type, extends(shape) :: Circle
    real :: radius
  contains
    procedure :: area => circle_area
  end type Circle
contains
  pure function circle_area(self, scale) result(total)
    type(Circle), intent(in) :: self
    total = self%radius * scale
    call report(total)
  end function circle_area
end module Geometry
~~~
`);
  assert.match(html, /class="syntax-namespace">Geometry<\/span>/);
  assert.match(html, /class="syntax-namespace">iso_fortran_env<\/span>/);
  assert.match(html, /class="syntax-type">shape<\/span>/);
  assert.match(html, /class="syntax-type">Circle<\/span>/);
  assert.match(html, /class="syntax-property">radius<\/span>/);
  assert.match(html, /class="syntax-property">area<\/span>/);
  assert.match(html, /class="syntax-function">circle_area<\/span>/);
  assert.match(html, /class="syntax-parameter">self<\/span>/);
  assert.match(html, /class="syntax-parameter">scale<\/span>/);
  assert.match(html, /class="syntax-function">report<\/span>/);
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
