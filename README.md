# Zig Markdown Viewer

A local-first Chrome/Chromium extension that renders `.md`, `.markdown`,
`.mkd`, and `.mdx` documents with a small Zig WebAssembly core.

The renderer uses the sibling `zig-markdown-parser` package. That parser was
extracted from Zine's Markdown work, so syntax fixes can flow into the browser
without bringing Zine's site-generation semantics into the extension.
SuperHTML is intentionally not a runtime dependency yet; it is the natural
source for a future native HTML/CSS syntax-highlighting layer.

## Build and load

```sh
./build.sh --release=small
```

Then open `chrome://extensions`, enable Developer mode, choose **Load
unpacked**, and select `zig-out/extension`. Enable **Allow access to file
URLs** on the extension's details page to render local files.

No npm install, remote script, CDN, or build-time network access is required.

## Included behavior

- Common Markdown plus tables, task lists, footnotes, strikethrough,
  autolinks, smart punctuation, and fenced-code language labels
- local and remote Markdown URLs
- safe handling of raw HTML before DOM insertion
- relative link and image resolution
- automatic heading anchors and table of contents
- light, dark, and system themes
- raw/rendered toggle, print, code-copy buttons, scroll-to-top
- optional auto-refresh and a recent-document list
- a Manifest V3 service worker and settings popup

Mermaid, KaTeX, and broad token-level source highlighting from Markview are
not bundled in this first version. Fenced blocks retain their language class,
which gives us a stable hook for adding Zine/SuperHTML-backed highlighting.

## Verification

```sh
./build.sh test
node --test tests/wasm.test.mjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/popup.js
node --check extension/js/wasm.js
```

## Provenance

The extension is an independent implementation inspired by the local Markview
extension's user experience. `zig-markdown-parser`, Zine, SuperHTML, and
Markview retain their own licenses and copyrights.
