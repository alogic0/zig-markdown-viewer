(() => {
  'use strict';

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.action !== 'fetchMarkdown') return false;
    fetchMarkdown(message.url || sender.url)
      .then(sendResponse)
      .catch(error => sendResponse({ ok: false, error: String(error) }));
    return true;
  });

  async function fetchMarkdown(url) {
    if (!url) return { ok: false, error: 'No document URL was provided.' };
    const response = await fetch(url, {
      cache: 'no-store',
      credentials: 'omit',
      headers: { Accept: 'text/markdown,text/plain;q=0.9,*/*;q=0.1' },
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
})();

