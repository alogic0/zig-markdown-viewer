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

## Included behavior

- Common Markdown plus tables, task lists, footnotes, strikethrough,
  autolinks, smart punctuation, and highlighted fenced code
- a curated set of quality-verified `zig-native-syntax` backends, with escaped
  plain-text fallback for experimental, unsupported, or unknown fence languages
- local and remote Markdown URLs
- safe handling of raw HTML before DOM insertion
- relative link and image resolution
- automatic heading anchors and table of contents
- light, dark, and system themes
- raw/rendered toggle, print, code-copy buttons, scroll-to-top
- one-click standalone HTML export with embedded viewer CSS and JavaScript
- optional auto-refresh and a recent-document list
- a Manifest V3 service worker and settings popup

Mermaid and KaTeX rendering from Markview are not bundled.

See [Highlighting quality](docs/HIGHLIGHTING_QUALITY.md) for the supported-language registry,
admission criteria, and parser/tokenizer policy.

## Verification

```sh
./build.sh test
node --test tests/wasm.test.mjs
node --test tests/standalone.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/popup.js
node --check extension/js/standalone.js
node --check extension/js/wasm.js
```

## Provenance

The extension is an independent implementation inspired by the local Markview
extension's user experience. `zig-markdown-parser`, Zine, SuperHTML, and
Markview retain their own licenses and copyrights.
