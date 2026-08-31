(() => {
  'use strict';

  importScripts('source-languages.js');

  const SOURCE_REDIRECT_RULE_ID = 1001;

  chrome.runtime.onInstalled.addListener(() => {
    chrome.storage.local.remove('mathMacros');
    configureSourceRedirect();
  });

  chrome.runtime.onStartup.addListener(configureSourceRedirect);

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && changes.enabled) configureSourceRedirect();
  });

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!['fetchMarkdown', 'fetchSource'].includes(message?.action)) return false;
    fetchDocument(message.url || sender.url, message.action === 'fetchSource')
      .then(sendResponse)
      .catch(error => sendResponse({ ok: false, error: String(error) }));
    return true;
  });

  function configureSourceRedirect() {
    chrome.storage.local.get({ enabled: true }, settings => {
      const update = { removeRuleIds: [SOURCE_REDIRECT_RULE_ID] };
      if (settings.enabled) {
        update.addRules = [globalThis.ZigSourceLanguages.redirectRule(
          SOURCE_REDIRECT_RULE_ID,
          chrome.runtime.getURL('source.html')
        )];
      }
      chrome.declarativeNetRequest.updateDynamicRules(update, () => {
        if (chrome.runtime.lastError) {
          console.error('Unable to configure source redirects:', chrome.runtime.lastError.message);
        }
      });
    });
  }

  async function fetchDocument(url, sourceMode) {
    if (!url) return { ok: false, error: 'No document URL was provided.' };
    const response = await fetch(url, {
      cache: 'no-store',
      credentials: 'omit',
      headers: {
        Accept: sourceMode
          ? 'text/plain,text/*;q=0.9,*/*;q=0.1'
          : 'text/markdown,text/plain;q=0.9,*/*;q=0.1',
      },
    });
    if (!response.ok) {
      return { ok: false, error: `HTTP ${response.status}: ${response.statusText}` };
    }
    return {
      ok: true,
      source: await response.text(),
      url: response.url || url,
    };
  }

  configureSourceRedirect();
})();
