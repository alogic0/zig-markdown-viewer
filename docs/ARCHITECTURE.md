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
        +-------- zig-math-typesetter ---- safe MathML or visual HTML + MathML
        |
        +-------- zig-native-syntax ---- optional native tokenizers/parsers
        |
        v
HTML sanitizer -> relative URL resolution -> document UI
```

## Local project boundaries

- `zig-markdown-parser` owns Markdown syntax, source spans, and deterministic
  document rendering, including source-preserving inline and block math nodes.
- `zig-math-typesetter` parses the supported delimiter-free TeX-like subset,
  normalizes its semantic tree, and emits one complete inert MathML fragment
  by default. An explicit document-local backend can instead emit its bounded,
  fixed-vocabulary visual HTML paired with the same MathML for accessibility.
  Diagnostics produce escaped literal source instead of partial MathML. Native
  renderer integrations may pass caller-owned definitions through
  `RenderOptions.math_macros`; the renderer validates and compiles that table
  once per document. The viewer also collects restricted `math-macros` fenced
  declarations before rendering and treats a valid document-local table as
  authoritative for that document. It does not accept mutable definitions
  inside math expressions.
- The Markdown renderer accepts at most one atomic `markdown-viewer` settings
  fence. Its fixed keys select MathML or visual HTML output and center or start
  alignment for display math. Valid settings compile to enum choices and fixed
  HTML wrapper classes; invalid settings remain visible and cannot add CSS,
  HTML, or MathML attributes.
- `zig-native-syntax` supplies core and optional backends, quality metadata, aliases,
  and a configured registry of verified enabled backends. The viewer consumes that
  registry without maintaining a second allowlist. Its safe HTML renderer emits only
  escaped source and stable `syntax-*` span classes; experimental, unsupported, and
  unknown languages remain escaped plain text.
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

Document-local declarations use only
`\newcommand{\name}[N]{replacement}` syntax. The viewer collects their fenced
contents, while `zig-math-typesetter` owns declaration parsing, byte-spanned
diagnostics, source lifetime, and the existing name, replacement, collision,
and resource-limit validation. All declaration fences are hidden only when the
complete table is valid; otherwise the table is disabled and the fences render
as ordinary code.

Raw HTML is preserved by the syntax renderer for source fidelity, then filtered
in the content script before any nodes enter the live page. Scripts, embedded
documents, active media, forms, unsafe URL schemes, event handlers, and active
attributes are removed. MathML is accepted only when its namespace, element
tree, root metadata, and the exact fixed attribute values emitted for spacing,
table alignment, bounded solid/none column lines, roman identifiers, styled and
binomial fractions, accents, stretchable annotations, explicit math styles,
scoped sizes, and named colors match the typesetter's strict allowlist. Relative
links and images are resolved against the Markdown document URL after
validation. Visual math is accepted only as an exact two-child composite: a
hidden fixed-class span tree followed by valid MathML. Its sanitizer permits
only the typesetter's class vocabulary, canonical bounded `em` dimensions and
position offsets, and exact glyph font scales. Ordinary glyph text is limited
to the metric set's reviewed Unicode ranges; font-internal stretchy variants
are limited to Plane 15 private-use scalars mapped by the packaged WOFF2 font.

Standalone export runs the source through the same renderer and sanitizer. The
content script then serializes the safe document, current layout settings,
table of contents, viewer stylesheets, packaged math font as a data URL, and a
small interaction script into one HTML file. The native standalone tool embeds
the same assets. The exported controls can toggle the contents sidebar and
light/dark theme. Images remain resolved links; extension code and WebAssembly
are not included in the exported page.

## Math development workflow

Ongoing viewer/typesetter development uses the sibling checkout through
`./build.sh math-dev <step>`. This keeps local integration moving without
rewriting the immutable GitHub dependency after every typesetter commit. The
typesetter is pushed and `./build.sh pin-math` is run only before pushing a
viewer change that depends on that revision.

Chromium is the active compatibility and visual-regression browser for the
HTML math backend. Firefox coverage is intentionally deferred and is not a
current development or release requirement.

`./build.sh math-dev chromium-math-e2e` runs the release-small Wasm renderer in
Chromium with the production content script, sanitizer policies, styles, and
packaged font. It verifies the visual/MathML composite boundary, retained safe
dimensions, script scaling, non-overlapping fraction layers, non-empty glyph
geometry, inline baseline anchoring, display-limit placement, aligned-row
spacing, hostile-markup filtering, font loading, and standalone-export embedding.

The repeatable equal-scale HTML/MathML screenshot procedure is documented in
[`MATH_VISUAL_COMPARISON.md`](MATH_VISUAL_COMPARISON.md). Use it instead of
comparing interactive browser tabs whose page zoom levels may differ.
