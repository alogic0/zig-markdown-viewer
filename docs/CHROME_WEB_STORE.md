# Chrome Web Store Submission

This document contains the canonical copy and disclosures for the `0.4.0`
submission. Keep the dashboard answers consistent with `PRIVACY.md` and the
extension manifest.

## Single purpose

Render Markdown and supported source-code files opened from local files or web
URLs as readable pages with local Zig/WebAssembly parsing and highlighting.

## Short description

Fast, local-first Markdown and source rendering powered by Zig and WebAssembly.

## Detailed description

Zig Markdown Viewer turns `.md`, `.markdown`, `.mkd`, and `.mdx` documents into
readable pages directly in Chrome. It also displays supported source-code URLs
with native syntax highlighting, including files that a server marks as an
attachment. It includes a responsive table of contents, light and dark themes,
raw source view, local inline and display math rendering with document-local
macros, printing, code-copy controls, optional auto-refresh, raw source
download, and one-click standalone Markdown HTML export.

Rendering, math typesetting, and syntax highlighting run locally in the
bundled WebAssembly module. The extension includes no analytics, advertising,
remote executable code, CDN dependency, or developer-operated service.

## Permission justifications

### storage

Required to retain the user's display preferences, refresh settings, and a
user-clearable list of up to 20 recently opened developer text files. The data
remains in `chrome.storage.local` and is not transmitted to the developer.

### declarativeNetRequestWithHostAccess

Required to redirect only top-level navigations whose filenames match the
extension's fixed supported-source map into the packaged source viewer before
Chrome handles an attachment response as a download. It does not inspect or
modify subresources, and users can disable source interception independently.

### Host access: file URLs

Required to render local Markdown and supported source files. Chrome
additionally requires the user to enable **Allow access to file URLs** from the
extension details page. The permission is not usable until the user makes that
choice.

### Host access: HTTP and HTTPS

Required because developer text files can be hosted on any domain. The content
script matches only supported Markdown filename extensions, while a fixed
main-frame rule matches supported source filenames. The background worker may
fetch only the exact URL the user opened, with credentials omitted, to preserve
text and provide explicitly enabled auto-refresh.

## Remote code

Select **No, I am not using remote code**. All JavaScript, CSS, and WebAssembly
executed by the extension are contained in the submitted ZIP.

## Data-use disclosures

The extension handles website content, user-generated content, and browsing
activity consisting of the opened Markdown or source file and its URL.
Processing is necessary for the extension's single purpose and occurs locally.
The extension does not collect or transmit this data to the developer or a
third party.

Certify that data is not sold, used outside the extension's single purpose,
used for creditworthiness or lending, or transferred for advertising. Use the
public URL for `PRIVACY.md` as the dashboard privacy-policy URL.

## Reviewer instructions

1. Load or install the extension.
2. Enable **Allow access to file URLs** on the extension details page.
3. Open a `.md` file and confirm that Markdown, inline math, and a fenced
   `math` block render.
4. Use the toolbar to switch raw/rendered mode and theme.
5. Open the extension popup to change display settings and clear recent files.
6. Use the download control to create a standalone HTML copy.
7. Open a supported source file such as `.zig`; confirm it is highlighted, then
   use the source-viewer setting and raw-download control.

No account, credentials, payment, or external service is required.

## Listing assets still supplied in the dashboard

- the 128px product icon from `extension/icons/icon128.png`;
- screenshots showing a rendered document, syntax highlighting, the table of
  contents, and the settings popup;
- the project's public homepage/support URL and `PRIVACY.md` URL.
