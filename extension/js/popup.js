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

  function storageGet(keys) {
    return new Promise(resolve => chrome.storage.local.get(keys, resolve));
  }

  function storageSet(values) {
    return new Promise(resolve => chrome.storage.local.set(values, resolve));
  }

  function setupTabs() {
    document.querySelectorAll('.tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(item => item.classList.remove('is-active'));
        document.querySelectorAll('.panel').forEach(item => item.classList.remove('is-active'));
        tab.classList.add('is-active');
        document.getElementById(tab.dataset.tab).classList.add('is-active');
      });
    });
  }

  async function setupSettings() {
    const settings = await storageGet(DEFAULTS);
    for (const [key, fallback] of Object.entries(DEFAULTS)) {
      const input = document.getElementById(key);
      if (!input) continue;
      const value = settings[key] ?? fallback;
      if (input.type === 'checkbox') input.checked = value;
      else input.value = String(value);
      updateOutput(key, value);
      input.addEventListener('input', () => {
        const next = input.type === 'checkbox'
          ? input.checked
          : input.type === 'range' || key === 'autoRefreshInterval'
            ? Number(input.value)
            : input.value;
        updateOutput(key, next);
        storageSet({ [key]: next });
      });
    }
    document.getElementById('reset-settings').addEventListener('click', async () => {
      await storageSet(DEFAULTS);
      window.location.reload();
    });
  }

  function updateOutput(key, value) {
    const output = document.getElementById(`${key}-output`);
    if (!output) return;
    output.textContent = key === 'lineHeight' ? Number(value).toFixed(2) : `${value}px`;
  }

  async function renderRecent(query = '') {
    const { recentDocuments = [] } = await storageGet({ recentDocuments: [] });
    const needle = query.trim().toLowerCase();
    const documents = recentDocuments.filter(item =>
      !needle || item.title.toLowerCase().includes(needle) || item.url.toLowerCase().includes(needle)
    );
    const list = document.getElementById('recent-list');
    list.replaceChildren();
    if (documents.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.innerHTML = '<strong>No recent documents</strong><span>Open a Markdown URL and it will appear here.</span>';
      list.append(empty);
      return;
    }

    for (const item of documents) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'recent-item';
      const title = document.createElement('strong');
      title.textContent = item.title;
      const url = document.createElement('span');
      url.textContent = item.url;
      const time = document.createElement('time');
      time.textContent = new Date(item.visitedAt).toLocaleString();
      button.append(title, url, time);
      button.addEventListener('click', () => chrome.tabs.create({ url: item.url }));
      list.append(button);
    }
  }

  async function initialize() {
    setupTabs();
    await setupSettings();
    await renderRecent();
    document.getElementById('recent-search').addEventListener('input', event => {
      renderRecent(event.target.value);
    });
    document.getElementById('clear-recent').addEventListener('click', async () => {
      await storageSet({ recentDocuments: [] });
      await renderRecent();
    });
    const manifest = chrome.runtime.getManifest();
    document.getElementById('version').textContent = `v${manifest.version}`;
  }

  initialize();
})();
