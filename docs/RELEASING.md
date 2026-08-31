# Release Checklist

Zig Markdown Viewer releases publish one source tag and the deterministic
Chrome extension ZIP generated from that exact commit.

## Prepare

- Confirm `main` is clean and synchronized with its remote.
- Read the synchronized package version with `./build.sh version`, then update
  every version location with `./build.sh version set MAJOR.MINOR.PATCH`.
- Move the release notes from `Unreleased` into the dated changelog section.
- Confirm every Zig package dependency uses an immutable remote revision and
  package hash.
- Confirm `PRIVACY.md` and `docs/CHROME_WEB_STORE.md` still describe the actual
  permissions, storage, requests, and data flow.

## Verify

Run the complete local gate with the pinned Zig compiler:

When publishing viewer changes that depend on local `zig-math-typesetter`
development, push that repository first and refresh the viewer pin:

```sh
./build.sh pin-math
```

```sh
zig fmt --check build.zig src tools
./build.sh update-logo
./build.sh test
./build.sh check-wasm-size
./build.sh chromium-math-e2e
./build.sh chromium-source-e2e
node --test tests/wasm.test.mjs
node --test tests/standalone.test.cjs
node --test tests/mathml-policy.test.cjs
node --test tests/html-math-policy.test.cjs
node --test tests/settings.test.cjs
node --test tests/branding.test.cjs
node --test tests/source-languages.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/mathml-policy.js
node --check extension/js/html-math-policy.js
node --check extension/js/popup.js
node --check extension/js/source-languages.js
node --check extension/js/source.js
node --check extension/js/standalone.js
node --check extension/js/wasm.js
./build.sh package-extension
unzip -t zig-out/dist/zig-markdown-viewer-0.5.1.zip
sha256sum zig-out/dist/zig-markdown-viewer-0.5.1.zip
```

Build the package a second time and confirm that its SHA-256 is identical.

Load `zig-out/extension` unpacked and smoke-test a local and remote Markdown
document, settings persistence, raw mode, theme switching, table-of-contents
navigation, code copying, printing, and standalone HTML export.

Open a supported local and remote source file, including one returned with an
attachment content disposition. Verify highlighting, wrapping, copying, raw
download, auto-refresh, and disabling the source-viewer setting.

Chromium is the required browser for this checklist and for visual-math
regression review. Firefox coverage is deferred and is not a release gate for
the current development phase.

## Publish

1. Push the release commit and require the GitHub Actions matrix and package job
   to pass.
2. Create an annotated `vMAJOR.MINOR.PATCH` tag at the verified commit and push
   the tag.
3. Confirm the tag workflow creates a GitHub Release from the matching
   changelog section and attaches the verified ZIP and SHA-256 checksum.
5. Upload the same ZIP to the Chrome Web Store dashboard, complete the listing
   and privacy fields from `docs/CHROME_WEB_STORE.md`, and submit for review.
6. After publication, install the store build in a clean Chrome profile and
   repeat the core smoke test.

Never rebuild an artifact for an existing tag. Correct a released defect with
a new version and changelog entry.
