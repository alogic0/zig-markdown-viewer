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
    mathMacros: [],
  };

  let mathMacros = [];
  let editedMacroIndex = null;

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
      if (input.type === 'checkbox') input.checked = key === 'centered' ? !value : value;
      else input.value = String(value);
      updateOutput(key, value);
      input.addEventListener('input', () => {
        const next = input.type === 'checkbox'
          ? key === 'centered' ? !input.checked : input.checked
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
    return settings;
  }

  function updateOutput(key, value) {
    const output = document.getElementById(`${key}-output`);
    if (!output) return;
    output.textContent = key === 'lineHeight' ? Number(value).toFixed(2) : `${value}px`;
  }

  function setMacroStatus(message, isError = false) {
    const status = document.getElementById('math-macro-status');
    status.textContent = message;
    status.classList.toggle('is-error', isError);
  }

  function closeMacroEditor() {
    editedMacroIndex = null;
    document.getElementById('math-macro-editor').hidden = true;
    document.getElementById('math-macro-error').textContent = '';
  }

  function openMacroEditor(index = null) {
    if (index === null && mathMacros.length >= globalThis.ZigMarkdownMathMacros.MAX_DEFINITIONS) {
      setMacroStatus('The maximum number of math macros has been reached.', true);
      return;
    }
    editedMacroIndex = index;
    const definition = index === null
      ? { name: '', replacement: '', argumentCount: 0 }
      : mathMacros[index];
    document.getElementById('math-macro-name').value = definition.name
      ? `\\${definition.name}`
      : '';
    document.getElementById('math-macro-arguments').value = String(definition.argumentCount);
    document.getElementById('math-macro-replacement').value = definition.replacement;
    document.getElementById('math-macro-error').textContent = '';
    const editor = document.getElementById('math-macro-editor');
    editor.hidden = false;
    document.getElementById('math-macro-name').focus();
  }

  function renderMathMacros() {
    const list = document.getElementById('math-macro-list');
    list.replaceChildren();
    if (mathMacros.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'macro-empty';
      empty.textContent = 'No custom macros configured.';
      list.append(empty);
      return;
    }

    mathMacros.forEach((definition, index) => {
      const item = document.createElement('article');
      item.className = 'macro-item';

      const summary = document.createElement('div');
      const name = document.createElement('code');
      name.textContent = `\\${definition.name}`;
      const argumentsLabel = document.createElement('small');
      argumentsLabel.textContent = `${definition.argumentCount} argument${definition.argumentCount === 1 ? '' : 's'}`;
      const replacement = document.createElement('code');
      replacement.className = 'macro-replacement';
      replacement.textContent = definition.replacement || '(empty replacement)';
      summary.append(name, argumentsLabel, replacement);

      const actions = document.createElement('div');
      actions.className = 'macro-item-actions';
      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'text-button';
      edit.textContent = 'Edit';
      edit.addEventListener('click', () => openMacroEditor(index));
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'text-button is-danger';
      remove.textContent = 'Remove';
      remove.addEventListener('click', async () => {
        remove.disabled = true;
        try {
          await saveMathMacros(mathMacros.filter((_, itemIndex) => itemIndex !== index));
          closeMacroEditor();
          renderMathMacros();
          setMacroStatus(`Removed \\${definition.name}.`);
        } catch (error) {
          setMacroStatus(error.message, true);
          remove.disabled = false;
        }
      });
      actions.append(edit, remove);
      item.append(summary, actions);
      list.append(item);
    });
  }

  async function saveMathMacros(definitions) {
    const renderer = await globalThis.ZigMarkdownRenderer.load();
    const normalized = renderer.configureMathMacros(definitions);
    await storageSet({ mathMacros: normalized });
    mathMacros = normalized;
  }

  function setupMathMacros(storedDefinitions) {
    try {
      mathMacros = globalThis.ZigMarkdownMathMacros.validate(storedDefinitions);
    } catch (error) {
      mathMacros = [];
      setMacroStatus(`Stored macros were ignored: ${error.message}`, true);
    }
    renderMathMacros();

    document.getElementById('add-math-macro').addEventListener('click', () => {
      setMacroStatus('');
      openMacroEditor();
    });
    document.getElementById('cancel-math-macro').addEventListener('click', closeMacroEditor);
    document.getElementById('math-macro-editor').addEventListener('submit', async event => {
      event.preventDefault();
      const submit = event.currentTarget.querySelector('[type="submit"]');
      submit.disabled = true;
      const nextDefinition = {
        name: document.getElementById('math-macro-name').value,
        argumentCount: Number(document.getElementById('math-macro-arguments').value),
        replacement: document.getElementById('math-macro-replacement').value,
      };
      const next = [...mathMacros];
      if (editedMacroIndex === null) next.push(nextDefinition);
      else next[editedMacroIndex] = nextDefinition;

      try {
        await saveMathMacros(next);
        const savedName = globalThis.ZigMarkdownMathMacros.validate([nextDefinition])[0].name;
        closeMacroEditor();
        renderMathMacros();
        setMacroStatus(`Saved \\${savedName}.`);
      } catch (error) {
        document.getElementById('math-macro-error').textContent = error.message;
      } finally {
        submit.disabled = false;
      }
    });
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
    const settings = await setupSettings();
    setupMathMacros(settings.mathMacros);
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
