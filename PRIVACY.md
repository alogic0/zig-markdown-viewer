# Privacy Policy

Effective date: August 29, 2026

Zig Markdown Viewer renders Markdown documents in Chrome and Chromium-based
browsers. Its single purpose is to turn Markdown documents that the user opens
into readable, navigable HTML.

## Data the extension handles

The extension handles the content and URL of a Markdown document only when the
user opens that document. Rendering, syntax highlighting, table-of-contents
generation, and standalone HTML export happen locally on the user's device.

The extension stores these values in `chrome.storage.local`:

- display and refresh preferences;
- user-defined math macro names, argument counts, and replacement text;
- up to 20 recently opened document URLs;
- each recent document's displayed title and last-opened timestamp.

Recent documents can be cleared from the extension popup. Stored preferences
and history are not synchronized by this extension.

## Network access

For an opened HTTP or HTTPS Markdown URL, the extension may fetch that same URL
to obtain its source text. The request omits browser credentials and bypasses
the HTTP cache so optional auto-refresh can detect changes. Any request needed
to load a linked image is performed by the browser directly under normal
browser rules.

The extension does not send document content, URLs, settings, or usage data to
the developer or to a developer-operated service.

## Collection, sharing, and sale

The developer does not collect, transmit, sell, rent, or share user data. The
extension contains no analytics, telemetry, advertising, tracking pixels, or
remote executable code. Its Zig, WebAssembly, JavaScript, and CSS components
are included in the installed extension package.

## Data retention and control

Preferences, math macro definitions, and recent-document metadata remain in
local extension storage until the user changes or clears them, clears extension
data, or uninstalls the extension. Standalone HTML files are created only when
the user presses the download button and are saved through the browser's normal
download behavior.

## Permissions

- `storage` stores display settings, math macro definitions, and the local
  recent-document list.
- `file:///*` allows rendering local Markdown files after the user explicitly
  enables file URL access for the extension.
- `http://*/*` and `https://*/*` allow rendering Markdown documents on arbitrary
  sites and fetching the exact document the user opened. Content scripts remain
  restricted to URLs with supported Markdown filename extensions.

## Changes and contact

Material changes will be recorded in the project changelog and published with
a new extension version. Privacy questions can be filed through the project's
public issue tracker.
