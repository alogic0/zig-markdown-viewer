(() => {
  'use strict';

  const MAX_DEFINITIONS = 256;
  const MAX_ARGUMENTS = 9;
  const MAX_CONFIG_BYTES = 1024 * 1024;
  const encoder = new TextEncoder();

  class MacroValidationError extends Error {}

  function validate(definitions) {
    if (!Array.isArray(definitions)) {
      throw new MacroValidationError('Math macros must be a list.');
    }
    if (definitions.length > MAX_DEFINITIONS) {
      throw new MacroValidationError(`At most ${MAX_DEFINITIONS} math macros are allowed.`);
    }

    const names = new Set();
    const normalized = definitions.map((definition, index) => {
      if (!definition || typeof definition !== 'object') {
        throw new MacroValidationError(`Macro ${index + 1} is not a definition.`);
      }
      const rawName = typeof definition.name === 'string' ? definition.name.trim() : '';
      const name = rawName.startsWith('\\') ? rawName.slice(1) : rawName;
      if (!/^[A-Za-z]+$/.test(name)) {
        throw new MacroValidationError(
          `Macro ${index + 1} needs an ASCII letter name such as \\f.`
        );
      }
      if (names.has(name)) {
        throw new MacroValidationError(`Macro \\${name} is defined more than once.`);
      }
      names.add(name);

      const argumentCount = definition.argumentCount;
      if (!Number.isInteger(argumentCount) || argumentCount < 0 || argumentCount > MAX_ARGUMENTS) {
        throw new MacroValidationError(
          `Macro \\${name} must accept between 0 and ${MAX_ARGUMENTS} arguments.`
        );
      }
      if (typeof definition.replacement !== 'string') {
        throw new MacroValidationError(`Macro \\${name} needs replacement text.`);
      }

      return { name, replacement: definition.replacement, argumentCount };
    });

    const encodedBytes = 4 + normalized.reduce((total, definition) =>
      total + 12 + encoder.encode(definition.name).length +
        encoder.encode(definition.replacement).length, 0);
    if (encodedBytes > MAX_CONFIG_BYTES) {
      throw new MacroValidationError('The encoded math macro configuration exceeds 1 MiB.');
    }
    return normalized;
  }

  const api = Object.freeze({
    MAX_ARGUMENTS,
    MAX_CONFIG_BYTES,
    MAX_DEFINITIONS,
    MacroValidationError,
    validate,
  });
  globalThis.ZigMarkdownMathMacros = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})();
