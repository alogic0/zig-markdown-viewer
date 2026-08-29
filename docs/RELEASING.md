# Release Checklist

Zig Markdown Viewer releases publish one source tag and the deterministic
Chrome extension ZIP generated from that exact commit.

## Prepare

- Confirm `main` is clean and synchronized with its remote.
- Update the version in `build.zig.zon`, `extension/manifest.json`, and
  `release_version` in `build.zig`.
- Move the release notes from `Unreleased` into the dated changelog section.
- Confirm every Zig package dependency uses an immutable remote revision and
  package hash.
- Confirm `PRIVACY.md` and `docs/CHROME_WEB_STORE.md` still describe the actual
  permissions, storage, requests, and data flow.

## Verify

Run the complete local gate with the pinned Zig compiler:

```sh
zig fmt --check build.zig src tools
./build.sh test
./build.sh check-wasm-size
node --test tests/wasm.test.mjs
node --test tests/standalone.test.cjs
node --check extension/js/background.js
node --check extension/js/content.js
node --check extension/js/popup.js
node --check extension/js/standalone.js
node --check extension/js/wasm.js
./build.sh package-extension
unzip -t zig-out/dist/zig-markdown-viewer-0.1.0.zip
sha256sum zig-out/dist/zig-markdown-viewer-0.1.0.zip
```

Build the package a second time and confirm that its SHA-256 is identical.

Load `zig-out/extension` unpacked and smoke-test a local and remote Markdown
document, settings persistence, raw mode, theme switching, table-of-contents
navigation, code copying, printing, and standalone HTML export.

## Publish

1. Push the release commit and require the GitHub Actions matrix and package job
   to pass.
2. Create an annotated `vMAJOR.MINOR.PATCH` tag at the verified commit and push
   the tag.
3. Create a GitHub Release from the matching changelog section.
4. Attach the versioned ZIP and its SHA-256 checksum to the GitHub Release.
5. Upload the same ZIP to the Chrome Web Store dashboard, complete the listing
   and privacy fields from `docs/CHROME_WEB_STORE.md`, and submit for review.
6. After publication, install the store build in a clean Chrome profile and
   repeat the core smoke test.

Never rebuild an artifact for an existing tag. Correct a released defect with
a new version and changelog entry.
