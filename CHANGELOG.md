# Changelog

All notable changes to Zig Markdown Viewer are documented here. Releases use
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A Chromium end-to-end visual-math gate covering the release-small Wasm
  renderer, production sanitizer, packaged font, browser geometry, hostile
  markup removal, and standalone-export font embedding.
- Atomic document-local `markdown-viewer` settings fences with fixed `center`
  or `start` block-math alignment.
- `./build.sh math-dev` for temporary sibling typesetter overrides and
  `./build.sh pin-math` for validated exact GitHub revision updates.
- Centered multi-row formulas through the bounded AMS `gathered` environment.
- First-, middle-, and last-aligned display rows through bounded AMS `multline`.
- Two-column equation alignment through bounded AMS `split` rows.
- Explicit bounded alignment-pair groups through the AMS `alignedat` environment.
- Generic bounded AMS arrays with validated left, center, and right columns.
- Bounded interior array separators with a strict solid/none column-line
  browser policy.
- Acute, grave, check, breve, ring, and stretchable over-arrow accents.
- Triple- and quadruple-dot accents plus stretchable left and right harpoons.
- Ten scoped math size commands with an exact fixed-value browser allowlist.
- Scoped math colors with twelve compiled names and no arbitrary CSS input.
- Portable document-local math macros through restricted, atomic
  `math-macros` declaration fences.
- Math matrices, fenced matrix variants, cases, and aligned equations through
  the bounded `zig-math-typesetter` AMS profile.
- Caller-provided, bounded math macros can be configured per native renderer
  operation and are compiled once for all expressions in the document.
- Scoped roman, bold, italic, sans-serif, monospace, double-struck, and script
  mathematical alphabets.
- Bold and italic Greek alphabets, styled fractions, binomial coefficients,
  angle/floor/ceiling/double-vertical fences, custom operator names, wide
  accents, and explicit math styles.
- Logic, relation, large-operator, arrow, binary-operator, constant, and dot
  commands; `\pmod`, stretchable braces, bounded multi-line `\substack`
  limits, compact AMS `smallmatrix`, and scoped `\mathfrak`.
- Explicit `\limits` and `\nolimits` placement overrides for large and named
  operators.
- Custom display-limit operators through `\operatorname*{name}` and grouped
  expression operators through `\mathop{body}`.

### Changed

- Pinned `zig-math-typesetter` at `15e9d9b` after the bounded `split` slice.
- Extended the inert MathML policy with only the fixed alignment, column-line,
  accent, size, and color attribute values emitted by the typesetter.
- Updated `zig-math-typesetter` to 0.4.0 and replaced the viewer-local macro
  declaration scanner with its allocator-owned public API.
- Updated `zig-math-typesetter` to 0.3.0 for the optional bounded AMS table
  profile.
- Extended the inert MathML policy with table elements and fixed aligned-cell
  values required by the AMS profile.
- Extended the inert MathML policy with only the fixed
  `mathvariant="normal"` value on `mi` required by roman identifiers.
- Extended the inert MathML policy with `mstyle` and only the fixed fraction,
  accent, stretching, display-style, and script-level values emitted by the
  typesetter.
- Updated `zig-math-typesetter` to 0.2.0 for Greek accents, named operators,
  `\relax`, and generic token-macro expansion.
- Replaced the extension and popup mark with the `M^{\,z}` formula and added a
  reproducible SVG generator backed by `zig-math-typesetter` with configurable
  foreground and background colors. The logo update step also regenerates every
  checked-in Chrome icon size for the normal build to install.

### Removed

- Extension-level math macro settings and their stored definitions; portable
  `math-macros` fences are now the browser integration.

## [0.2.0] - 2026-08-30

### Added

- Local inline and fenced display math rendering through `zig-math-typesetter`
  and an allowlisted MathML Core subset, with escaped literal fallback.

### Security

- MathML is accepted at the browser boundary only when its namespace,
  elements, attributes, and fixed spacing widths match the typesetter's inert
  output contract.

## [0.1.0] - 2026-08-29

### Added

- Local-first rendering for Markdown, Markdown Extra-style tables, task lists,
  footnotes, strikethrough, autolinks, and smart punctuation.
- Source-preserving syntax highlighting for 95 quality-reviewed language
  backends through `zig-native-syntax`.
- Responsive table of contents with active-heading tracking, raw/rendered
  switching, light/dark/system themes, code copying, printing, and scroll-to-top.
- Standalone HTML export with embedded CSS and JavaScript.
- Native `zig-md-render` command for rendering Markdown without WebAssembly.
- Local preferences, recent-document navigation, and optional auto-refresh.
- Deterministic, validated Chrome extension release archives.

### Security

- Raw HTML is escaped by the Zig renderer and rendered output is sanitized
  before insertion into the document.
- Unsafe link and image schemes are removed.
- The extension contains no remotely executed code, telemetry, advertising, or
  runtime dependency on a developer-operated service.
- Release Wasm removes compiler name and DWARF metadata, preventing local
  checkout paths from entering published artifacts.

[Unreleased]: https://github.com/alogic0/zig-markdown-viewer/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/alogic0/zig-markdown-viewer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/alogic0/zig-markdown-viewer/releases/tag/v0.1.0
