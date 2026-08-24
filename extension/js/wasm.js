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
      const sourcePointer = this.exports.allocateSource(bytes.length);
      if (bytes.length !== 0 && sourcePointer === 0) this.throwLastError();

      new Uint8Array(this.exports.memory.buffer, sourcePointer, bytes.length).set(bytes);
      const outputPointer = this.exports.renderMarkdown(bytes.length);
      const outputLength = this.exports.renderedLength();
      if (outputPointer === 0 && outputLength === 0 && this.exports.errorCode() !== 0) {
        this.throwLastError();
      }

      const html = this.decoder.decode(
        new Uint8Array(this.exports.memory.buffer, outputPointer, outputLength)
      );
      this.exports.releaseSource();
      return html;
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

  globalThis.ZigMarkdownRenderer = { load };
})();

