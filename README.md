# Zig Markdown Viewer

A local-first Chrome/Chromium extension that renders `.md`, `.markdown`,
`.mkd`, and `.mdx` documents with a small Zig WebAssembly core.

The renderer uses revision-pinned `zig-markdown-parser`,
`zig-math-typesetter`, and `zig-native-syntax` packages. Markdown parsing,
TeX-like math typesetting, and all source highlighting run in the same
WebAssembly module without a JavaScript rendering library or runtime network
dependency.

## Build and load

```sh
./build.sh --release=small
```

Then open `chrome://extensions`, enable Developer mode, choose **Load
unpacked**, and select `zig-out/extension`. Enable **Allow access to file
URLs** on the extension's details page to render local files.

Build the deterministic Chrome Web Store/GitHub release archive with:

```sh
./build.sh package-extension
```

The validated package is written to
`zig-out/dist/zig-markdown-viewer-0.3.5.zip` with `manifest.json` at the ZIP
root.

Read the package version or update every viewer-version location with:

```sh
./build.sh version
./build.sh version set 0.3.2
```

`./build.sh version get` is the explicit form of the default read command. The
setter accepts a canonical numeric `MAJOR.MINOR.PATCH` compatible with the Zig
package and Chrome manifest. The reader treats `build.zig.zon` as authoritative
and reports one short error for every tracked file whose version differs.

No npm install, remote script, or CDN is required. Zig package dependencies used
by optional highlighting backends are pinned by `zig-native-syntax`.

Regenerate the SVG logo from the default `$M^{\,z}$` formula with:

```sh
./build.sh update-logo
```

The generator renders through `zig-math-typesetter` and updates
`extension/icons`, rasterizing the four Chrome icon sizes with Chrome or
Chromium. A subsequent normal `./build.sh` copies those source assets into
`zig-out/extension/icons`. Set `CHROME_EXE` when the browser executable is not
on `PATH`. Formula and six-digit hex colors can be overridden with
`-Dlogo-formula`, `-Dlogo-background`, and `-Dlogo-foreground`.

```sh
./build.sh \
  -Dlogo-formula='$M^{\,z}$' \
  -Dlogo-background='#2563eb' \
  -Dlogo-foreground='#f8fafc' \
  update-logo
```

## Native standalone HTML tool

Render Markdown directly with the native Zig parser and syntax backends:

```sh
./build.sh render-html -- document.md -o document.html
```

The installed executable is also available as `zig-out/bin/zig-md-render` after
a normal build. If `-o` is omitted, the tool replaces a Markdown extension with
`.html`. The output embeds the viewer CSS and JavaScript, table of contents,
theme switch, and code-copy controls in one file. Raw HTML is escaped and unsafe
link and image URL schemes are removed.

Use `./build.sh render-html --help` for theme, wide-screen, wrapping, and
table-of-contents options. This native tool imports the same Zig rendering core
as the extension; it does not instantiate the WebAssembly renderer.

## Included behavior

- Common Markdown plus tables, task lists, footnotes, strikethrough,
  autolinks, smart punctuation, and highlighted fenced code
- inline `$...$` math and display math in `math`, `tex`, or `latex` fences,
  rendered locally as inert MathML Core by default or as optional fixed-vocabulary
  visual HTML/CSS paired with MathML accessibility, with literal-source fallback;
  the AMS profile supports bounded `array` columns and vertical separators,
  matrices, compact matrices,
  cases, `aligned`, `alignedat`, `split`, `gathered`, and `multline` equations,
  while
  `\mathrm`, `\mathbf`, `\mathit`, `\mathsf`, `\mathtt`, `\mathbb`,
  `\mathcal`, and `\mathfrak` provide scoped mathematical alphabets; styled
  fractions, binomials, extended fences, custom side- and display-limit
  operators through `\operatorname`, `\operatorname*`, and `\mathop`, narrow
  diacritic, wide-arrow, and harpoon accents, braces, multi-line limits,
  explicit limit placement, math styles, fixed scoped sizes, fixed named
  colors, and an expanded set of symbols and operators are also supported
- bounded custom math macros declared in `math-macros` fences, validated once
  per document without enabling mutable definitions inside math expressions
- document-local math backend and block-math alignment through an atomic
  `markdown-viewer` settings fence
- a curated set of quality-verified `zig-native-syntax` backends, with escaped
  plain-text fallback for experimental, unsupported, or unknown fence languages
- local and remote Markdown URLs
- safe handling of raw HTML before DOM insertion
- relative link and image resolution
- automatic heading anchors and responsive table of contents
- light, dark, and system themes
- raw/rendered toggle, print, touch-accessible code-copy buttons, scroll-to-top
- one-click standalone HTML export with embedded viewer CSS, Contents and theme controls
- optional auto-refresh and a recent-document list
- a Manifest V3 service worker and settings popup

Mermaid diagrams are not currently supported.

### Math macros

Declare portable, document-wide math macros in a fenced block. Backtick and
tilde fences are equivalent, and valid declaration blocks are omitted from the
rendered document:

~~~markdown
```math-macros
\newcommand{\R}{R}
\newcommand{\f}[2]{#1f(#2)}
```

$\f{x}{y} \in \R$
~~~

Only the restricted `\newcommand{\name}[N]{replacement}` form is accepted.
Arbitrary `\def`, `\gdef`, and mutation commands remain unsupported. If any
declaration is malformed or invalid, the document-local table is rejected
atomically and its fences remain visible as code.

### Document settings

Display math is centered by default. A document can align every display formula
to the start of its text direction with one settings fence:

```markdown
~~~markdown-viewer
math-block-alignment = start
~~~
```

Select the optional visual HTML/CSS backend in the same document-local fence:

```markdown
~~~markdown-viewer
math-backend = html
math-block-alignment = start
~~~
```

`math-backend` accepts `mathml` (the default) or `html`.
`math-block-alignment` accepts `center` or `start`. Exactly one complete
settings fence is allowed. Unknown or duplicate keys, invalid values,
duplicate fences, and oversized settings leave the fences visible as ordinary
code and preserve the defaults. Inline math is unaffected by block alignment.

See [Highlighting quality](docs/HIGHLIGHTING_QUALITY.md) for the
supported-language registry, admission criteria, and parser/tokenizer policy.

The [privacy policy](PRIVACY.md) describes local document processing, stored
settings, recent-document metadata, and permission use. Release maintainers
should follow the [release checklist](docs/RELEASING.md) and use the canonical
[Chrome Web Store submission text](docs/CHROME_WEB_STORE.md).

## Verification

```sh
./build.sh test
./build.sh check-wasm-size
node --test tests/wasm.test.mjs
node --test tests/standalone.test.cjs
node --test tests/mathml-policy.test.cjs
node --test tests/html-math-policy.test.cjs
node --test tests/settings.test.cjs
node --test tests/branding.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/mathml-policy.js
node --check extension/js/html-math-policy.js
node --check extension/js/popup.js
node --check extension/js/standalone.js
node --check extension/js/wasm.js
```

The normal test step rebuilds the release-small renderer used by the Node test
and compares its exact byte size with
[`tools/renderer_wasm_size.txt`](tools/renderer_wasm_size.txt). The check prints
a signed difference and rejects unreviewed growth or shrinkage. Binary-size
checks prevent accidental growth; they do not prohibit justified growth.
Intentional changes are accepted after reviewing `./build.sh wasm-size-report`
and running `./build.sh update-wasm-size-baseline` to record the new size.

## Local math-typesetter development

Use the sibling `zig-math-typesetter` checkout without changing the committed
GitHub dependency. This is the default workflow for ongoing math development:

```sh
./build.sh math-dev test
./build.sh math-dev chromium-math-e2e
```

`math-dev` accepts the same build step and options as the normal wrapper and
adds Zig's `--fork ../zig-math-typesetter` package override. Use it for test,
build, packaging, size review, and focused development steps while the sibling
checkout is advancing. Do not refresh the committed dependency during normal
iteration.

Only at the pre-push boundary for a viewer change that depends on a new
typesetter revision, push the typesetter and refresh the viewer's exact GitHub
revision and package hash with:

```sh
./build.sh pin-math
./build.sh test
```

`pin-math` refuses a dirty typesetter worktree or a HEAD commit that is not
present on an `origin` branch or tag.

Chromium is the current browser target for visual-math development and
regression review. Firefox coverage is deferred and is not part of the current
development gate. The Chromium step loads the release-small Wasm renderer and
production content scripts, sanitizer policies, CSS, and WOFF2 asset; it also
checks rendered geometry and the standalone-export font embedding path. Set
`CHROME_EXE` if Chrome or Chromium is not discoverable on `PATH`.

## Provenance

The extension is an independent implementation inspired by the local [Markview](https://github.com/markview-app/markview)
extension's user experience. `zig-markdown-parser`, [Zine](https://zine-ssg.io), [SuperHTML](https://github.com/kristoff-it/superhtml), and
Markview retain their own licenses and copyrights. The visual math backend
packages a modified STIX Two Math font under the adjacent SIL Open Font License
in `extension/css/fonts/OFL.txt`.

Changes are recorded in [CHANGELOG.md](CHANGELOG.md). The project is licensed
under the [MIT License](LICENSE).
