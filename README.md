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
`zig-out/dist/zig-markdown-viewer-0.2.0.zip` with `manifest.json` at the ZIP
root.

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
  rendered locally as an inert MathML Core subset with literal-source fallback;
  the AMS profile supports matrices, cases, and aligned equations
- bounded custom math macros declared in `math-macros` fences or configured in
  the extension popup, validated once per document without enabling mutable
  definitions inside math expressions
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

See [Highlighting quality](docs/HIGHLIGHTING_QUALITY.md) for the supported-language registry,
admission criteria, and parser/tokenizer policy.

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
node --test tests/math-macros.test.cjs
node --test tests/branding.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/math-macros.js
node --check extension/js/mathml-policy.js
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

## Provenance

The extension is an independent implementation inspired by the local [Markview](https://github.com/markview-app/markview)
extension's user experience. `zig-markdown-parser`, [Zine](https://zine-ssg.io), [SuperHTML](https://github.com/kristoff-it/superhtml), and
Markview retain their own licenses and copyrights.

Changes are recorded in [CHANGELOG.md](CHANGELOG.md). The project is licensed
under the [MIT License](LICENSE).
