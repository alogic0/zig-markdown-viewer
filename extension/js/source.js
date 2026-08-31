(() => {
  'use strict';

  const DEFAULTS = {
    theme: 'auto',
    centered: true,
    maxWidth: 960,
    fontSize: 16,
    lineHeight: 1.65,
    codeWrap: false,
    autoRefresh: false,
    autoRefreshInterval: 3,
  };

  const state = {
    url: location.hash.slice(1),
    source: '',
    language: null,
    settings: { ...DEFAULTS },
    renderer: null,
    refreshTimer: null,
  };

  function storageGet(keys) {
    return new Promise(resolve => chrome.storage.local.get(keys, resolve));
  }

  function storageSet(values) {
    return new Promise(resolve => chrome.storage.local.set(values, resolve));
  }

  function fetchSource() {
    return new Promise(resolve => {
      chrome.runtime.sendMessage(
        { action: 'fetchSource', url: state.url },
        result => resolve(chrome.runtime.lastError ? null : result)
      );
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

  function applySettings() {
    const shell = document.querySelector('#zig-md-shell');
    document.documentElement.dataset.zigMarkdownTheme = state.settings.theme;
    shell.style.setProperty('--zig-md-width', `${state.settings.maxWidth}px`);
    shell.style.setProperty('--zig-md-font-size', `${state.settings.fontSize}px`);
    shell.style.setProperty('--zig-md-line-height', state.settings.lineHeight);
    shell.classList.toggle('is-centered', state.settings.centered);
    shell.classList.toggle('code-wrap', state.settings.codeWrap);
    startAutoRefresh();
  }

  function render() {
    const content = document.querySelector('#zig-md-document');
    content.classList.remove('is-loading', 'is-error');
    content.innerHTML = state.renderer.renderSource(state.language, state.source);
  }

  function showError(message) {
    const content = document.querySelector('#zig-md-document');
    content.classList.remove('is-loading');
    content.classList.add('is-error');
    content.textContent = message;
  }

  async function cycleTheme() {
    const themes = ['auto', 'light', 'dark'];
    state.settings.theme = themes[(themes.indexOf(state.settings.theme) + 1) % themes.length];
    applySettings();
    await storageSet({ theme: state.settings.theme });
    notify(`Theme: ${state.settings.theme}`);
  }

  async function toggleWrap() {
    state.settings.codeWrap = !state.settings.codeWrap;
    applySettings();
    await storageSet({ codeWrap: state.settings.codeWrap });
    notify(state.settings.codeWrap ? 'Line wrapping enabled' : 'Line wrapping disabled');
  }

  async function copySource() {
    try {
      await navigator.clipboard.writeText(state.source);
      notify('Source copied');
    } catch {
      notify('Unable to copy source', true);
    }
  }

  function downloadSource() {
    const objectUrl = URL.createObjectURL(new Blob([state.source], { type: 'text/plain;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = objectUrl;
    link.download = globalThis.ZigSourceLanguages.fileName(state.url) || 'source.txt';
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
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
    render();
    notify('Source refreshed');
  }

  async function saveRecent() {
    const values = await storageGet({ recentDocuments: [] });
    const current = {
      url: state.url,
      title: globalThis.ZigSourceLanguages.fileName(state.url),
      visitedAt: Date.now(),
    };
    const recentDocuments = [current, ...values.recentDocuments.filter(item => item.url !== current.url)]
      .slice(0, 20);
    await storageSet({ recentDocuments });
  }

  function bindActions() {
    document.querySelector('[data-action="wrap"]').addEventListener('click', toggleWrap);
    document.querySelector('[data-action="theme"]').addEventListener('click', cycleTheme);
    document.querySelector('[data-action="copy"]').addEventListener('click', copySource);
    document.querySelector('[data-action="download"]').addEventListener('click', downloadSource);
  }

  async function initialize() {
    const content = document.querySelector('#zig-md-document');
    content.classList.add('is-loading');
    content.textContent = 'Loading source…';

    state.language = globalThis.ZigSourceLanguages.languageForUrl(state.url);
    if (!state.language) {
      showError('This URL is not a supported source file.');
      return;
    }

    const name = globalThis.ZigSourceLanguages.fileName(state.url) || 'Source file';
    document.title = `${name} · Zig Markdown Viewer`;
    document.querySelector('#zig-source-name').textContent = name;
    document.querySelector('#zig-source-language').textContent = state.language;
    document.querySelector('#zig-source-location').textContent = state.url;

    state.settings = { ...DEFAULTS, ...await storageGet(DEFAULTS) };
    applySettings();
    bindActions();

    const response = await fetchSource();
    if (!response?.ok) {
      showError(response?.error || 'Unable to load this source file.');
      return;
    }
    state.source = response.source;

    try {
      state.renderer = await globalThis.ZigMarkdownRenderer.load();
      render();
      await saveRecent();
    } catch (error) {
      console.error('Zig source viewer failed to initialize:', error);
      showError('Unable to render this source file.');
    }
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local') return;
    for (const [key, change] of Object.entries(changes)) {
      if (key in DEFAULTS) state.settings[key] = change.newValue ?? DEFAULTS[key];
    }
    applySettings();
  });

  initialize();
})();
