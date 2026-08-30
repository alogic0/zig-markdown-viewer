(() => {
  'use strict';

  const errorMessages = {
    1: 'The WebAssembly renderer ran out of memory.',
    2: 'The Markdown parser rejected this document.',
    3: 'The Markdown renderer could not produce HTML.',
    4: 'The WebAssembly renderer received an invalid input buffer.',
    5: 'The math macro configuration is invalid or conflicts with a built-in command.',
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

      try {
        new Uint8Array(this.exports.memory.buffer, sourcePointer, bytes.length).set(bytes);
        const outputPointer = this.exports.renderMarkdown(bytes.length);
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

    configureMathMacros(definitions) {
      const normalized = globalThis.ZigMarkdownMathMacros.validate(definitions);
      if (normalized.length === 0) {
        this.exports.clearMathMacros();
        return normalized;
      }

      const encoded = normalized.map(definition => ({
        name: this.encoder.encode(definition.name),
        replacement: this.encoder.encode(definition.replacement),
        argumentCount: definition.argumentCount,
      }));
      const length = 4 + encoded.reduce(
        (total, definition) => total + 12 + definition.name.length + definition.replacement.length,
        0
      );
      const bytes = new Uint8Array(length);
      const view = new DataView(bytes.buffer);
      view.setUint32(0, encoded.length, true);
      let offset = 4;
      for (const definition of encoded) {
        view.setUint32(offset, definition.name.length, true);
        view.setUint32(offset + 4, definition.replacement.length, true);
        view.setUint32(offset + 8, definition.argumentCount, true);
        offset += 12;
        bytes.set(definition.name, offset);
        offset += definition.name.length;
        bytes.set(definition.replacement, offset);
        offset += definition.replacement.length;
      }

      const pointer = this.exports.allocateMacroConfig(bytes.length);
      if (pointer === 0) this.throwLastError();
      try {
        new Uint8Array(this.exports.memory.buffer, pointer, bytes.length).set(bytes);
        if (this.exports.configureMathMacros(bytes.length) !== 1) this.throwLastError();
      } finally {
        this.exports.releaseMacroConfig();
      }
      return normalized;
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
