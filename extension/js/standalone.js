(() => {
  'use strict';

  const PAGE_SCRIPT = `(() => {
  'use strict';

  const root = document.documentElement;
  const shell = document.querySelector('#zig-md-shell');
  const tocToggle = document.querySelector('[data-action="toc"]');
  const themeToggle = document.querySelector('[data-action="theme"]');

  function updateTocToggle() {
    const visible = shell?.classList.contains('has-toc') || false;
    tocToggle?.setAttribute('aria-pressed', String(visible));
  }

  tocToggle?.addEventListener('click', () => {
    shell?.classList.toggle('has-toc');
    updateTocToggle();
  });

  function updateThemeToggle() {
    const setting = root.dataset.zigMarkdownTheme;
    const dark = setting === 'dark' ||
      (setting === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    themeToggle?.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
    themeToggle?.setAttribute('title', dark ? 'Switch to light theme' : 'Switch to dark theme');
  }

  themeToggle?.addEventListener('click', () => {
    const setting = root.dataset.zigMarkdownTheme;
    const dark = setting === 'dark' ||
      (setting === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    root.dataset.zigMarkdownTheme = dark ? 'light' : 'dark';
    updateThemeToggle();
  });

  function copyText(text) {
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text);
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.append(textarea);
    textarea.select();
    document.execCommand('copy');
    textarea.remove();
    return Promise.resolve();
  }

  document.querySelectorAll('.zig-md-copy').forEach(button => {
    const code = button.parentElement?.querySelector('code');
    button.addEventListener('click', async () => {
      await copyText(code?.textContent || '');
      button.textContent = 'Copied';
      setTimeout(() => { button.textContent = 'Copy'; }, 1200);
    });
  });

  const scrollTop = document.querySelector('#zig-md-scroll-top');
  scrollTop?.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));

  const entries = [...document.querySelectorAll('#zig-md-toc nav a')]
    .map(link => ({ link, heading: document.getElementById(decodeURIComponent(link.hash.slice(1))) }))
    .filter(entry => entry.heading);
  let scrollFrame = null;

  function updateScrollState() {
    scrollTop?.classList.toggle('is-visible', scrollY > 500);
    if (entries.length === 0) return;

    let active = entries[0];
    const atBottom = scrollY > 0 && innerHeight + scrollY >= document.documentElement.scrollHeight - 2;
    if (atBottom) {
      active = entries[entries.length - 1];
    } else {
      for (const entry of entries) {
        if (entry.heading.getBoundingClientRect().top > 96) break;
        active = entry;
      }
    }

    for (const entry of entries) {
      const isActive = entry === active;
      entry.link.classList.toggle('is-active', isActive);
      if (isActive) entry.link.setAttribute('aria-current', 'location');
      else entry.link.removeAttribute('aria-current');
    }
  }

  window.addEventListener('scroll', () => {
    if (scrollFrame !== null) return;
    scrollFrame = requestAnimationFrame(() => {
      scrollFrame = null;
      updateScrollState();
    });
  }, { passive: true });
  updateTocToggle();
  updateThemeToggle();
  updateScrollState();
})();`;

  function escapeHtml(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function finiteNumber(value, fallback) {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback;
  }

  function buildHtml(options) {
    const theme = ['auto', 'light', 'dark'].includes(options.theme) ? options.theme : 'auto';
    const classes = [
      options.centered ? 'is-centered' : '',
      options.tocVisible ? 'has-toc' : '',
      options.codeWrap ? 'code-wrap' : '',
    ].filter(Boolean).join(' ');
    const width = finiteNumber(options.maxWidth, 960);
    const fontSize = finiteNumber(options.fontSize, 16);
    const lineHeight = finiteNumber(options.lineHeight, 1.65);

    return `<!doctype html>
<html lang="en" data-zig-markdown-theme="${theme}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(options.title || 'Markdown document')}</title>
  <style>
${options.css}
  </style>
</head>
<body class="zig-md-page">
  <div id="zig-md-shell" class="${classes}" style="--zig-md-width:${width}px;--zig-md-font-size:${fontSize}px;--zig-md-line-height:${lineHeight}">
    <aside id="zig-md-toc" aria-label="Table of contents">
      <div class="zig-md-toc-heading">On this page</div>
      <nav>${options.tocHtml}</nav>
    </aside>
    <div id="zig-md-main">
      <header id="zig-md-toolbar" aria-label="Document tools">
        <div class="zig-md-actions">
          <button type="button" data-action="toc" title="Toggle table of contents" aria-label="Toggle table of contents">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
          </button>
          <button type="button" data-action="theme" title="Switch color theme" aria-label="Switch color theme">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9Z"/></svg>
          </button>
        </div>
      </header>
      <main id="zig-md-document">${options.documentHtml}</main>
      <button id="zig-md-scroll-top" type="button" aria-label="Scroll to top">↑</button>
    </div>
  </div>
  <script>
${PAGE_SCRIPT}
  </script>
</body>
</html>
`;
  }

  function downloadName(sourceUrl) {
    let name = 'markdown-document';
    try {
      const segment = new URL(sourceUrl).pathname.split('/').filter(Boolean).pop();
      if (segment) name = decodeURIComponent(segment);
    } catch {
      // Keep the fallback name for malformed source URLs.
    }
    name = name.replace(/\.(?:md|markdown|mkd|mdx)$/i, '');
    name = name.replace(/[\\/:*?"<>|]+/g, '-').trim() || 'markdown-document';
    return `${name}.html`;
  }

  const api = Object.freeze({ buildHtml, downloadName });
  globalThis.ZigMarkdownStandalone = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})();
