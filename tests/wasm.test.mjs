import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const wasmPath = new URL('../zig-out/extension/renderer.wasm', import.meta.url);
const bytes = await readFile(wasmPath);
const module = new WebAssembly.Module(bytes);
const instance = new WebAssembly.Instance(module, {});
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
