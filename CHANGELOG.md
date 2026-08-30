# Changelog

All notable changes to Zig Markdown Viewer are documented here. Releases use
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Caller-provided, bounded math macros can be configured per native renderer
  operation and are compiled once for all expressions in the document.
- The WebAssembly renderer accepts atomic, bounded macro-table configuration
  while preserving the previous valid session when an update is rejected.
- The extension popup can add, edit, and remove custom math macros. Accepted
  definitions are stored locally and applied immediately to open documents.

### Changed

- Updated `zig-math-typesetter` to 0.2.0 for Greek accents, named operators,
  `\relax`, and generic token-macro expansion.
- Replaced the extension and popup mark with the rendered `M^{\;z}` formula.

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
