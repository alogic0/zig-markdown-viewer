# Highlighting Quality

## Decision

The viewer exposes a curated registry of quality-verified backends. It does not automatically
register every backend available from `zig-native-syntax`. A fence whose language is experimental,
unsupported, or unknown keeps its language label and CSS class, but its source is rendered as
escaped plain text.

The viewer does not guess a language for an unlabelled fence. Incorrect semantic coloring is more
misleading than conservative plain text.

## Parser And Tokenizer Policy

A parser or syntax tree is required when highlighting depends on contextual roles such as
declarations, calls, types, properties, parameters, bindings, or embedded-language regions. A
maintained tokenizer or focused scanner is sufficient when the useful highlighting surface is
lexical, as with markup tokens, JSON values, or diff line structure.

Implementation mechanism and quality are separate properties:

- `BackendKind` records whether a backend is lexical, parser-backed, or composed;
- `SupportLevel` records whether its behavior is experimental, verified lexical, or verified
  structural.

Consuming a parser does not automatically establish quality, and using a tokenizer does not
automatically make a backend low quality.

## Current Registry

Verified structural backends:

- Zig;
- Bash and RPM Bash;
- JavaScript and TypeScript;
- Rust;
- Ziggy Schema;
- Scripty;
- Markdown;
- composed SuperHTML.

Verified lexical backends:

- Ziggy;
- HTML and XML;
- CSS;
- JSON;
- Diff/patch.

Accepted aliases are deliberately narrow: `sh`, `shell`, `rpm-bash`, `js`, `ts`, `rs`, `patch`,
`md`, `smd`, `supermd`, `markdown-inline`, `csproj`, and `props`.

The viewer does not map JSX or TSX to parsers that do not understand those dialects. It likewise
does not treat GLSL as C, generic configuration as Fish, or Nimble as TOML.

## Promotion Gate

A backend can enter the viewer registry only after all applicable requirements are satisfied:

1. Strings, comments, escapes, numbers, punctuation, and malformed-input recovery have exact tests.
2. Contextual roles are derived from reliable syntax structure when the language requires them.
3. Captures preserve the original source and valid UTF-8 boundaries.
4. Representative real-world corpus fixtures pass.
5. Viewer tests assert exact highlighted HTML for important constructs rather than merely checking
   that some syntax class exists.
6. Every accepted alias represents syntax the backend actually understands.
7. Native and WebAssembly paths produce the same source-preserving result.
8. Backend failure falls back to escaped plain text.

Promotion is a reviewed source change to the explicit registry in `src/highlight.zig`. Adding a
backend to `zig-native-syntax` alone does not make it visible in the viewer.
