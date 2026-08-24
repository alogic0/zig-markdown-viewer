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
        v
HTML sanitizer -> relative URL resolution -> document UI
```

## Local project boundaries

- `zig-markdown-parser` is the only compile-time dependency. It owns syntax,
  source spans, and deterministic HTML rendering.
- Zine is the parser's upstream integration and behavior reference. Zine page
  metadata, directives, templates, and asset pipelines do not belong in a
  document-viewer extension.
- SuperHTML already provides native HTML and CSS tokenizers. Those can be
  compiled into a later highlighting ABI without introducing application
  semantics into the parser.

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

