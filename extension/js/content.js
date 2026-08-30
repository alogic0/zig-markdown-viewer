(() => {
  'use strict';

  const DEFAULTS = {
    enabled: true,
    theme: 'auto',
    centered: true,
    maxWidth: 960,
    fontSize: 16,
    lineHeight: 1.65,
    tocVisible: true,
    codeWrap: false,
    autoRefresh: false,
    autoRefreshInterval: 3,
  };
  const mobileToc = window.matchMedia('(max-width: 680px)');

  const state = {
    source: '',
    settings: { ...DEFAULTS },
    renderer: null,
    refreshTimer: null,
    rawMode: false,
    tocEntries: [],
    activeHeadingId: null,
    scrollFrame: null,
    tocOpen: true,
    documentTitle: document.title || fileName(window.location.href),
    exportStylesPromise: null,
  };

  function storageGet(keys) {
    return new Promise(resolve => chrome.storage.local.get(keys, resolve));
  }

  function storageSet(values) {
    return new Promise(resolve => chrome.storage.local.set(values, resolve));
  }

  function fileName(url) {
    try {
      const name = new URL(url).pathname.split('/').filter(Boolean).pop();
      return name ? decodeURIComponent(name) : 'Markdown document';
    } catch {
      return 'Markdown document';
    }
  }

  function extractSource() {
    const pre = document.querySelector('body > pre') || document.querySelector('pre');
    if (pre) return pre.textContent || '';
    const contentType = document.contentType.toLowerCase();
    if (contentType.includes('text/plain') || contentType.includes('markdown')) {
      return document.body?.innerText || '';
    }
    return '';
  }

  function fetchSource() {
    return new Promise(resolve => {
      chrome.runtime.sendMessage(
        { action: 'fetchMarkdown', url: window.location.href },
        result => resolve(chrome.runtime.lastError ? null : result)
      );
    });
  }

  function setFavicon() {
    let favicon = document.querySelector('link[data-zig-md-favicon]');
    if (!favicon) {
      favicon = document.createElement('link');
      favicon.rel = 'icon';
      favicon.type = 'image/svg+xml';
      favicon.dataset.zigMdFavicon = '';
      document.head.append(favicon);
    }
    favicon.href = chrome.runtime.getURL('icons/favicon.svg');
  }

  function sanitize(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    for (const root of [...template.content.querySelectorAll('math')]) {
      if (!globalThis.ZigMarkdownMathMlPolicy.allowsTree(root)) root.remove();
    }
    template.content
      .querySelectorAll('script,style,iframe,frame,frameset,object,embed,applet,base,meta,link,form,svg,audio,video,source,track')
      .forEach(element => element.remove());

    const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_ELEMENT);
    const elements = [];
    while (walker.nextNode()) elements.push(walker.currentNode);

    for (const element of elements) {
      for (const attribute of [...element.attributes]) {
        const name = attribute.name.toLowerCase();
        if (
          name.startsWith('on') ||
          ['srcdoc', 'formaction', 'xlink:href', 'srcset', 'ping', 'autofocus', 'contenteditable'].includes(name)
        ) {
          element.removeAttribute(attribute.name);
          continue;
        }
        if (name === 'style' && !/^\s*text-align\s*:\s*(left|center|right)\s*;?\s*$/i.test(attribute.value)) {
          element.removeAttribute(attribute.name);
        }
      }

      if (element.tagName === 'INPUT') {
        const safeTask = element.type === 'checkbox' && element.disabled;
        if (!safeTask) element.remove();
      }
      if (element.tagName === 'A') secureUrl(element, 'href', true);
      if (element.tagName === 'IMG') secureUrl(element, 'src', false);
    }
    return template.content;
  }

  function secureUrl(element, attribute, isLink) {
    const raw = element.getAttribute(attribute);
    if (!raw) return;
    if (isLink && raw.startsWith('#')) return;
    try {
      const resolved = new URL(raw, window.location.href);
      const safeProtocol = ['http:', 'https:', 'file:'].includes(resolved.protocol) ||
        (isLink && ['mailto:', 'tel:'].includes(resolved.protocol)) ||
        (!isLink && /^data:image\/(png|gif|jpe?g|webp);/i.test(raw));
      if (!safeProtocol) {
        element.removeAttribute(attribute);
        return;
      }
      if (!raw.startsWith('data:')) element.setAttribute(attribute, resolved.href);
      if (isLink && resolved.origin !== window.location.origin) {
        element.target = '_blank';
        element.rel = 'noopener noreferrer';
      }
    } catch {
      element.removeAttribute(attribute);
    }
  }

  function buildShell() {
    document.documentElement.dataset.zigMarkdownTheme = state.settings.theme;
    setFavicon();
    document.body.replaceChildren();
    document.body.className = 'zig-md-page';

    const shell = document.createElement('div');
    shell.id = 'zig-md-shell';
    shell.innerHTML = `
      <aside id="zig-md-toc" aria-label="Table of contents">
        <div class="zig-md-toc-heading">On this page</div>
        <nav></nav>
      </aside>
      <div id="zig-md-main">
        <header id="zig-md-toolbar" aria-label="Document tools">
          <div class="zig-md-actions">
            <button type="button" data-action="toc" title="Toggle table of contents" aria-label="Toggle table of contents">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
            </button>
            <button type="button" data-action="raw" title="Toggle rendered and raw Markdown" aria-label="Toggle rendered and raw Markdown">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18-6-6 6-6M15 6l6 6-6 6"/></svg>
            </button>
            <button type="button" data-action="theme" title="Cycle color theme" aria-label="Cycle color theme">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9Z"/></svg>
            </button>
            <button type="button" data-action="print" title="Print document" aria-label="Print document">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 14h12v7H6z"/></svg>
            </button>
            <button type="button" data-action="download" title="Download standalone HTML" aria-label="Download standalone HTML">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12M7 10l5 5 5-5M5 21h14"/></svg>
            </button>
          </div>
        </header>
        <main id="zig-md-document" tabindex="-1"></main>
        <button id="zig-md-scroll-top" type="button" aria-label="Scroll to top">↑</button>
      </div>`;
    document.body.append(shell);

    shell.querySelector('[data-action="toc"]').addEventListener('click', () => {
      state.tocOpen = !state.tocOpen;
      state.settings.tocVisible = state.tocOpen;
      applySettings();
      storageSet({ tocVisible: state.settings.tocVisible });
    });
    shell.querySelector('[data-action="raw"]').addEventListener('click', () => {
      state.rawMode = !state.rawMode;
      renderCurrent();
    });
    shell.querySelector('[data-action="theme"]').addEventListener('click', cycleTheme);
    shell.querySelector('[data-action="print"]').addEventListener('click', () => window.print());
    shell.querySelector('[data-action="download"]').addEventListener('click', event => {
      downloadStandalone(event.currentTarget);
    });
    shell.querySelector('#zig-md-scroll-top').addEventListener('click', () => {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
    window.addEventListener('scroll', updateScrollState, { passive: true });
  }

  function applySettings() {
    const shell = document.querySelector('#zig-md-shell');
    if (!shell) return;
    document.documentElement.dataset.zigMarkdownTheme = state.settings.theme;
    shell.style.setProperty('--zig-md-width', `${state.settings.maxWidth}px`);
    shell.style.setProperty('--zig-md-font-size', `${state.settings.fontSize}px`);
    shell.style.setProperty('--zig-md-line-height', state.settings.lineHeight);
    shell.classList.toggle('is-centered', state.settings.centered);
    shell.classList.toggle('has-toc', state.tocOpen);
    shell.classList.toggle('code-wrap', state.settings.codeWrap);
    startAutoRefresh();
  }

  async function cycleTheme() {
    const themes = ['auto', 'light', 'dark'];
    state.settings.theme = themes[(themes.indexOf(state.settings.theme) + 1) % themes.length];
    applySettings();
    await storageSet({ theme: state.settings.theme });
    notify(`Theme: ${state.settings.theme}`);
  }

  function renderCurrent() {
    const content = document.querySelector('#zig-md-document');
    if (!content) return;
    content.replaceChildren();

    if (state.rawMode) {
      const raw = document.createElement('pre');
      raw.className = 'zig-md-raw';
      raw.textContent = state.source;
      content.append(raw);
      document.querySelector('#zig-md-toc nav').replaceChildren();
      state.tocEntries = [];
      state.activeHeadingId = null;
      return;
    }

    const html = state.renderer.render(state.source);
    content.append(sanitize(html));
    enhanceCodeBlocks(content);
    buildToc(content);
  }

  function enhanceCodeBlocks(content) {
    content.querySelectorAll('pre > code').forEach(code => {
      const pre = code.parentElement;
      if (pre.parentElement?.classList.contains('zig-md-code-block')) return;

      const block = document.createElement('div');
      block.className = 'zig-md-code-block';
      pre.before(block);
      block.append(pre);

      if (pre.dataset.language) {
        const language = document.createElement('span');
        language.className = 'zig-md-language';
        language.textContent = pre.dataset.language;
        block.append(language);
      }

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'zig-md-copy';
      button.textContent = 'Copy';
      button.addEventListener('click', async () => {
        await navigator.clipboard.writeText(code.textContent || '');
        button.textContent = 'Copied';
        setTimeout(() => { button.textContent = 'Copy'; }, 1200);
      });
      block.append(button);
    });
  }

  function standaloneTocHtml(content) {
    const nav = document.createElement('nav');
    for (const heading of content.querySelectorAll('h1,h2,h3')) {
      const link = document.createElement('a');
      link.href = `#${encodeURIComponent(heading.id)}`;
      link.className = `level-${heading.tagName.slice(1)}`;
      link.textContent = heading.textContent.replace(/^#/, '').trim();
      nav.append(link);
    }
    if (!nav.hasChildNodes()) {
      const empty = document.createElement('p');
      empty.className = 'zig-md-toc-empty';
      empty.textContent = 'No headings';
      nav.append(empty);
    }
    return nav.innerHTML;
  }

  function closeMobileToc() {
    if (!mobileToc.matches || !state.tocOpen) return;
    state.tocOpen = false;
    applySettings();
  }

  async function exportStyles() {
    if (!state.exportStylesPromise) {
      state.exportStylesPromise = fetch(chrome.runtime.getURL('css/content.css')).then(response => {
        if (!response.ok) throw new Error(`Unable to load viewer styles (${response.status})`);
        return response.text();
      });
    }
    try {
      return await state.exportStylesPromise;
    } catch (error) {
      state.exportStylesPromise = null;
      throw error;
    }
  }

  async function downloadStandalone(button) {
    button.disabled = true;
    try {
      const content = document.createElement('main');
      content.append(sanitize(state.renderer.render(state.source)));
      enhanceCodeBlocks(content);

      const html = globalThis.ZigMarkdownStandalone.buildHtml({
        title: state.documentTitle,
        theme: state.settings.theme,
        centered: state.settings.centered,
        tocVisible: state.tocOpen,
        codeWrap: state.settings.codeWrap,
        maxWidth: state.settings.maxWidth,
        fontSize: state.settings.fontSize,
        lineHeight: state.settings.lineHeight,
        css: await exportStyles(),
        documentHtml: content.innerHTML,
        tocHtml: standaloneTocHtml(content),
      });
      const name = globalThis.ZigMarkdownStandalone.downloadName(window.location.href);
      const objectUrl = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }));
      const link = document.createElement('a');
      link.href = objectUrl;
      link.download = name;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
      notify(`Downloaded ${name}`);
    } catch (error) {
      console.error('Unable to export standalone HTML:', error);
      notify('Unable to download HTML', true);
    } finally {
      button.disabled = false;
    }
  }

  function buildToc(content) {
    const nav = document.querySelector('#zig-md-toc nav');
    nav.replaceChildren();
    state.tocEntries = [];
    state.activeHeadingId = null;
    const headings = [...content.querySelectorAll('h1,h2,h3')];
    if (headings.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'zig-md-toc-empty';
      empty.textContent = 'No headings';
      nav.append(empty);
      return;
    }
    for (const heading of headings) {
      const link = document.createElement('a');
      link.href = `#${encodeURIComponent(heading.id)}`;
      link.className = `level-${heading.tagName.slice(1)}`;
      link.textContent = heading.textContent.replace(/^#/, '').trim();
      link.addEventListener('click', closeMobileToc);
      nav.append(link);
      state.tocEntries.push({ heading, link });
    }
    updateActiveTocLink();
  }

  function updateScrollButton() {
    document.querySelector('#zig-md-scroll-top')?.classList.toggle('is-visible', scrollY > 500);
  }

  function updateActiveTocLink() {
    if (state.tocEntries.length === 0) return;

    let active = state.tocEntries[0];
    const atBottom = scrollY > 0 && innerHeight + scrollY >= document.documentElement.scrollHeight - 2;
    if (atBottom) {
      active = state.tocEntries[state.tocEntries.length - 1];
    } else {
      for (const entry of state.tocEntries) {
        if (entry.heading.getBoundingClientRect().top > 96) break;
        active = entry;
      }
    }

    for (const entry of state.tocEntries) {
      const isActive = entry === active;
      entry.link.classList.toggle('is-active', isActive);
      if (isActive) entry.link.setAttribute('aria-current', 'location');
      else entry.link.removeAttribute('aria-current');
    }

    if (state.activeHeadingId === active.heading.id) return;
    state.activeHeadingId = active.heading.id;
    const toc = document.querySelector('#zig-md-toc');
    const linkRect = active.link.getBoundingClientRect();
    const tocRect = toc.getBoundingClientRect();
    if (linkRect.top < tocRect.top + 16) toc.scrollTop -= tocRect.top + 16 - linkRect.top;
    else if (linkRect.bottom > tocRect.bottom - 16) toc.scrollTop += linkRect.bottom - tocRect.bottom + 16;
  }

  function updateScrollState() {
    if (state.scrollFrame !== null) return;
    state.scrollFrame = requestAnimationFrame(() => {
      state.scrollFrame = null;
      updateScrollButton();
      updateActiveTocLink();
    });
  }

  function notify(message, isError = false) {
    document.querySelector('.zig-md-notification')?.remove();
    const element = document.createElement('div');
    element.className = `zig-md-notification${isError ? ' is-error' : ''}`;
    element.textContent = message;
    document.body.append(element);
    requestAnimationFrame(() => element.classList.add('is-visible'));
    setTimeout(() => element.remove(), 2400);
  }

  async function saveRecent() {
    const values = await storageGet({ recentDocuments: [] });
    const current = {
      url: window.location.href,
      title: state.documentTitle,
      visitedAt: Date.now(),
    };
    const recentDocuments = [current, ...values.recentDocuments.filter(item => item.url !== current.url)]
      .slice(0, 20);
    await storageSet({ recentDocuments });
  }

  function startAutoRefresh() {
    if (state.refreshTimer) clearInterval(state.refreshTimer);
    state.refreshTimer = null;
    if (!state.settings.autoRefresh) return;
    const milliseconds = Math.max(1, state.settings.autoRefreshInterval) * 1000;
    state.refreshTimer = setInterval(refreshSource, milliseconds);
  }

  async function refreshSource() {
    const response = await fetchSource();
    if (!response?.ok || response.source === state.source) return;
    state.source = response.source;
    renderCurrent();
    notify('Document refreshed');
  }

  function restoreRawDocument() {
    if (state.refreshTimer) clearInterval(state.refreshTimer);
    if (state.scrollFrame !== null) cancelAnimationFrame(state.scrollFrame);
    state.scrollFrame = null;
    state.tocEntries = [];
    state.activeHeadingId = null;
    document.documentElement.removeAttribute('data-zig-markdown-theme');
    document.querySelector('link[data-zig-md-favicon]')?.remove();
    document.body.className = '';
    const pre = document.createElement('pre');
    pre.textContent = state.source;
    document.body.replaceChildren(pre);
  }

  async function initialize() {
    const extractedSource = extractSource() || document.body?.innerText || '';
    const stored = await storageGet(DEFAULTS);
    state.settings = { ...DEFAULTS, ...stored };
    state.tocOpen = state.settings.tocVisible && !mobileToc.matches;
    if (!state.settings.enabled) return;

    // Chromium can decode a raw local Markdown page using a legacy charset
    // before content scripts run. Fetching it again preserves its UTF-8 text;
    // keep the page source as a fallback for inaccessible remote documents.
    const response = await fetchSource();
    state.source = response?.ok ? response.source : extractedSource;

    try {
      state.renderer = await globalThis.ZigMarkdownRenderer.load();
      buildShell();
      applySettings();
      renderCurrent();
      document.title = state.documentTitle;
      await saveRecent();
      if (window.location.hash) {
        requestAnimationFrame(() => document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView());
      }
    } catch (error) {
      console.error('Zig Markdown Viewer failed to initialize:', error);
      restoreRawDocument();
    }
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local') return;
    for (const [key, change] of Object.entries(changes)) {
      if (key in DEFAULTS) {
        state.settings[key] = change.newValue ?? DEFAULTS[key];
      }
    }
    if (changes.tocVisible) state.tocOpen = changes.tocVisible.newValue;
    if (changes.enabled?.newValue === false) {
      restoreRawDocument();
      return;
    }
    if (changes.enabled?.newValue === true && !document.querySelector('#zig-md-shell')) {
      initialize();
      return;
    }
    applySettings();
  });

  mobileToc.addEventListener('change', event => {
    state.tocOpen = event.matches ? false : state.settings.tocVisible;
    applySettings();
  });

  initialize();
})();
