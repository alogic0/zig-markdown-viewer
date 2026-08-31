(() => {
  'use strict';

  const errorMessages = {
    1: 'The WebAssembly renderer ran out of memory.',
    2: 'The Markdown parser rejected this document.',
    3: 'The Markdown renderer could not produce HTML.',
    4: 'The WebAssembly renderer received an invalid input buffer.',
  };

  class Renderer {
    constructor(instance) {
      this.exports = instance.exports;
      this.encoder = new TextEncoder();
      this.decoder = new TextDecoder();
    }

    render(source) {
      const bytes = this.encoder.encode(source);
      return this.renderBytes(bytes, () => this.exports.renderMarkdown(bytes.length));
    }

    renderSource(language, source) {
      const languageBytes = this.encoder.encode(language);
      const sourceBytes = this.encoder.encode(source);
      const bytes = new Uint8Array(languageBytes.length + sourceBytes.length);
      bytes.set(languageBytes);
      bytes.set(sourceBytes, languageBytes.length);
      return this.renderBytes(
        bytes,
        () => this.exports.renderSource(languageBytes.length, sourceBytes.length)
      );
    }

    renderBytes(bytes, render) {
      const sourcePointer = this.exports.allocateSource(bytes.length);
      if (bytes.length !== 0 && sourcePointer === 0) this.throwLastError();

      try {
        new Uint8Array(this.exports.memory.buffer, sourcePointer, bytes.length).set(bytes);
        const outputPointer = render();
        const outputLength = this.exports.renderedLength();
        if (outputPointer === 0 && outputLength === 0 && this.exports.errorCode() !== 0) {
          this.throwLastError();
        }

        return this.decoder.decode(
          new Uint8Array(this.exports.memory.buffer, outputPointer, outputLength)
        );
      } finally {
        this.exports.releaseSource();
      }
    }

    throwLastError() {
      const code = this.exports.errorCode();
      throw new Error(errorMessages[code] || `Unknown renderer error (${code}).`);
    }
  }

  let rendererPromise;

  async function load() {
    if (!rendererPromise) {
      rendererPromise = (async () => {
        const url = chrome.runtime.getURL('renderer.wasm');
        let result;
        try {
          result = await WebAssembly.instantiateStreaming(fetch(url), {});
        } catch {
          const response = await fetch(url);
          result = await WebAssembly.instantiate(await response.arrayBuffer(), {});
        }
        return new Renderer(result.instance);
      })();
    }
    return rendererPromise;
  }

  const api = { Renderer, load };
  globalThis.ZigMarkdownRenderer = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})();
