# Zig Markdown Viewer

A local-first Chrome/Chromium extension that renders `.md`, `.markdown`,
`.mkd`, and `.mdx` documents with a small Zig WebAssembly core.

The renderer uses the sibling `zig-markdown-parser` and `zig-native-syntax`
packages. Markdown parsing and all source highlighting run in the same WebAssembly
module without a JavaScript highlighting library or runtime network dependency.

## Build and load

```sh
./build.sh --release=small
```

Then open `chrome://extensions`, enable Developer mode, choose **Load
unpacked**, and select `zig-out/extension`. Enable **Allow access to file
URLs** on the extension's details page to render local files.

No npm install, remote script, or CDN is required. Zig package dependencies used
by optional highlighting backends are pinned by `zig-native-syntax`.

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

Mermaid and KaTeX rendering from Markview are not bundled.

See [Highlighting quality](docs/HIGHLIGHTING_QUALITY.md) for the supported-language registry,
admission criteria, and parser/tokenizer policy.

## Verification

```sh
./build.sh test
./build.sh check-wasm-size
node --test tests/wasm.test.mjs
node --test tests/standalone.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/popup.js
node --check extension/js/standalone.js
node --check extension/js/wasm.js
```

The normal test step rebuilds the release-small renderer used by the Node test
and enforces its 640,000-byte size budget. Raising that budget requires an
explicit reviewed change.

## Provenance

The extension is an independent implementation inspired by the local Markview
extension's user experience. `zig-markdown-parser`, Zine, SuperHTML, and
Markview retain their own licenses and copyrights.
