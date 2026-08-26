# Architecture

```text
Chrome text document
        |
        v
content script ---- settings/history ---- chrome.storage.local
        |
        v
renderer.wasm ---- zig-markdown-parser
        |
        +-------- zig-native-syntax ---- optional native tokenizers/parsers
        |
        v
HTML sanitizer -> relative URL resolution -> document UI
```

## Local project boundaries

- `zig-markdown-parser` owns Markdown syntax, source spans, and deterministic
  document rendering.
- `zig-native-syntax` supplies core and optional backends plus independent quality
  metadata. The viewer owns an explicit allowlist of verified backends rather than
  registering every available scanner. Its safe HTML renderer emits only escaped
  source and stable `syntax-*` span classes; experimental, unsupported, and unknown
  languages remain escaped plain text.
- Zine is the parser's upstream integration and behavior reference. Zine page
  metadata, directives, templates, and asset pipelines do not belong in a
  document-viewer extension.
- SuperHTML provides the HTML, XML, and CSS tokenizers selected by the optional
  native-syntax backends and is compiled into the same WebAssembly module.

The registry and promotion requirements are defined in
[Highlighting quality](HIGHLIGHTING_QUALITY.md).

## WebAssembly ABI

The content script allocates UTF-8 source with `allocateSource`, writes into
exported memory, calls `renderMarkdown`, reads `renderedLength` bytes, and then
calls `releaseSource`. The renderer owns its output until the next render or
`releaseOutput`.

Raw HTML is preserved by the syntax renderer for source fidelity, then filtered
in the content script before any nodes enter the live page. Scripts, embedded
documents, active media, forms, unsafe URL schemes, event handlers, and active
attributes are removed. Relative links and images are resolved against the
Markdown document URL after validation.

Standalone export runs the source through the same renderer and sanitizer. The
content script then serializes the safe document, current layout settings, table
of contents, viewer stylesheet, and a small interaction script into one HTML
file. Images remain resolved links; extension code and WebAssembly are not
included in the exported page.
