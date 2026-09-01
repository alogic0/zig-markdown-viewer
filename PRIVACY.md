# Privacy Policy

Effective date: August 29, 2026

Zig Markdown Viewer renders Markdown documents and supported source-code files
in Chrome and Chromium-based browsers. Its single purpose is to turn developer
text files that the user opens into readable, locally rendered pages.

## Data the extension handles

The extension handles the content and URL of a supported Markdown or source
file only when the user opens that file. Rendering, syntax highlighting,
table-of-contents generation, and standalone HTML export happen locally on the
user's device.

The extension stores these values in `chrome.storage.local`:

- display and refresh preferences;
- up to 20 recently opened document URLs;
- each recent document's displayed title and last-opened timestamp.

Recent documents can be cleared from the extension popup. Stored preferences
and history are not synchronized by this extension.

## Network access

For an opened HTTP or HTTPS Markdown or supported source URL, the extension may
fetch that same URL to obtain its text. The request omits browser credentials
and bypasses the HTTP cache so optional auto-refresh can detect changes. Any
request needed to load a linked image is performed by the browser directly
under normal browser rules.

The extension does not send document content, URLs, settings, or usage data to
the developer or to a developer-operated service.

## Collection, sharing, and sale

The developer does not collect, transmit, sell, rent, or share user data. The
extension contains no analytics, telemetry, advertising, tracking pixels, or
remote executable code. Its Zig, WebAssembly, JavaScript, and CSS components
are included in the installed extension package.

## Data retention and control

Preferences and recent-document metadata remain in local extension storage
until the user changes or clears them, clears extension data, or uninstalls the
extension. Standalone HTML files are created only when the user presses the
download button and are saved through the browser's normal download behavior.

## Permissions

- `storage` stores display settings and the local recent-document list.
- `declarativeNetRequestWithHostAccess` redirects only top-level supported
  local source-file navigations to the packaged source viewer. The independent
  source-viewer setting removes this redirect when disabled.
- `file:///*` allows rendering local Markdown and supported source files after
  the user explicitly enables file URL access for the extension.
- `http://*/*` and `https://*/*` allow rendering Markdown documents on
  arbitrary sites and fetching the exact Markdown URL the user opened. Content
  scripts remain restricted to supported Markdown extensions; source
  interception is restricted to local `file://` URLs.

## Changes and contact

Material changes will be recorded in the project changelog and published with
a new extension version. Privacy questions can be filed through the project's
public issue tracker.
