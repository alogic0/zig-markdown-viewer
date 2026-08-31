(function (root, factory) {
  const policy = factory();
  if (typeof module === 'object' && module.exports) module.exports = policy;
  root.ZigMarkdownHtmlMathPolicy = policy;
})(typeof globalThis === 'object' ? globalThis : this, () => {
  'use strict';

  const namespace = 'http://www.w3.org/1999/xhtml';
  const classes = new Set([
    'zig-math-html', 'zig-math-inline', 'zig-math-display',
    'zig-math-list', 'zig-math-hlist', 'zig-math-vlist',
    'zig-math-glyph', 'zig-math-kern', 'zig-math-rule',
    'zig-math-overlap', 'zig-math-shift', 'zig-math-delimiter',
    'zig-math-delimiter-vertical', 'zig-math-delimiter-horizontal', 'zig-math-assembled',
    'zig-math-scope', 'zig-math-text', 'zig-math-alpha-roman',
    'zig-math-alpha-bold', 'zig-math-alpha-italic', 'zig-math-alpha-sans_serif',
    'zig-math-alpha-monospace', 'zig-math-alpha-double_struck', 'zig-math-alpha-script',
    'zig-math-alpha-fraktur', 'zig-math-style-display', 'zig-math-style-text',
    'zig-math-style-script', 'zig-math-style-script_script', 'zig-math-size-tiny',
    'zig-math-size-script', 'zig-math-size-footnote', 'zig-math-size-small',
    'zig-math-size-normal', 'zig-math-size-large', 'zig-math-size-large_2',
    'zig-math-size-large_3', 'zig-math-size-huge', 'zig-math-size-huge_2',
    'zig-math-color-black', 'zig-math-color-white', 'zig-math-color-red',
    'zig-math-color-green', 'zig-math-color-blue', 'zig-math-color-cyan',
    'zig-math-color-magenta', 'zig-math-color-yellow', 'zig-math-color-gray',
    'zig-math-color-orange', 'zig-math-color-purple', 'zig-math-color-brown',
  ]);
  const dimension = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?em$/;
  const styleProperties = new Set(['width', 'height', 'vertical-align', 'margin-left', 'top']);
  const scopeClasses = new Set([...classes].filter(name =>
    name.startsWith('zig-math-alpha-') || name.startsWith('zig-math-style-') ||
    name.startsWith('zig-math-size-') || name.startsWith('zig-math-color-') ||
    name === 'zig-math-text'
  ));

  function parseClasses(value) {
    if (typeof value !== 'string' || value.length === 0 || /^\s|\s$|\s{2,}/.test(value)) return null;
    const tokens = value.split(' ');
    if (new Set(tokens).size !== tokens.length || tokens.some(token => !classes.has(token))) return null;
    return new Set(tokens);
  }

  function parseStyle(value) {
    if (typeof value !== 'string' || value.length === 0) return null;
    const declarations = value.split(';');
    if (declarations.at(-1) === '') declarations.pop();
    if (declarations.length === 0) return null;
    const parsed = new Map();
    for (const declaration of declarations) {
      const separator = declaration.indexOf(':');
      if (separator <= 0 || declaration.indexOf(':', separator + 1) !== -1) return null;
      const property = declaration.slice(0, separator);
      const propertyValue = declaration.slice(separator + 1);
      if (!styleProperties.has(property) || parsed.has(property) || !dimension.test(propertyValue)) return null;
      parsed.set(property, propertyValue);
    }
    return parsed;
  }

  function sameKeys(values, expected) {
    return values.size === expected.length && expected.every(name => values.has(name));
  }

  function allowsElement(name, elementNamespace, attributes, isRoot) {
    if (name !== 'span' || elementNamespace !== namespace) return false;
    const values = new Map(attributes);
    if (values.size !== attributes.length) return false;
    const tokens = parseClasses(values.get('class'));
    if (!tokens) return false;

    if (isRoot) {
      if (!sameKeys(values, ['class', 'aria-hidden']) || values.get('aria-hidden') !== 'true') return false;
      return tokens.size === 2 && tokens.has('zig-math-html') &&
        (tokens.has('zig-math-inline') !== tokens.has('zig-math-display'));
    }
    if (![...values.keys()].every(name => name === 'class' || name === 'style')) return false;
    if (!values.has('style')) return tokens.has('zig-math-scope') && tokens.size === 2 &&
      [...tokens].some(token => scopeClasses.has(token));
    const style = parseStyle(values.get('style'));
    if (!style) return false;
    if (tokens.has('zig-math-kern')) return tokens.size === 1 && sameKeys(style, ['width']);
    if (tokens.has('zig-math-shift')) return tokens.size === 1 && sameKeys(style, ['margin-left', 'top']);
    if (tokens.has('zig-math-delimiter')) {
      const axes = Number(tokens.has('zig-math-delimiter-vertical')) +
        Number(tokens.has('zig-math-delimiter-horizontal'));
      return axes === 1 && tokens.size === (tokens.has('zig-math-assembled') ? 3 : 2) &&
        sameKeys(style, ['width', 'height', 'vertical-align']);
    }
    if (tokens.has('zig-math-glyph') || tokens.has('zig-math-rule')) {
      return tokens.size === 1 && sameKeys(style, ['width', 'height', 'vertical-align']);
    }
    if (tokens.has('zig-math-list')) {
      const kinds = Number(tokens.has('zig-math-hlist')) + Number(tokens.has('zig-math-vlist')) +
        Number(tokens.has('zig-math-overlap'));
      return tokens.size === 2 && kinds === 1 && sameKeys(style, ['width', 'height', 'vertical-align']);
    }
    return false;
  }

  function allowsGlyphText(value) {
    if (typeof value !== 'string' || value.length === 0) return false;
    for (const scalar of value) {
      const codepoint = scalar.codePointAt(0);
      if (codepoint < 0xF0000 || codepoint > 0xFFFFD) return false;
    }
    return true;
  }

  function allowsVisualTree(visualRoot) {
    const descendants = [visualRoot, ...visualRoot.querySelectorAll('*')];
    for (const [index, element] of descendants.entries()) {
      if (!allowsElement(
        element.localName,
        element.namespaceURI,
        [...element.attributes].map(attribute => [attribute.name, attribute.value]),
        index === 0
      )) return false;
      const glyph = element.classList.contains('zig-math-glyph');
      const childElements = [...element.children];
      for (const child of element.childNodes) {
        if (glyph) {
          if (child.nodeType !== 3 || !allowsGlyphText(child.nodeValue)) return false;
        } else if (child.nodeType !== 1) return false;
      }
      if (glyph && (childElements.length !== 0 || element.childNodes.length === 0)) return false;
      if ((element.classList.contains('zig-math-kern') || element.classList.contains('zig-math-rule')) &&
          element.childNodes.length !== 0) return false;
      if ((element.classList.contains('zig-math-shift') || element.classList.contains('zig-math-scope')) &&
          childElements.length !== 1) return false;
    }
    return visualRoot.children.length === 1;
  }

  function allowsTree(composite) {
    if (composite.localName !== 'span' || composite.namespaceURI !== namespace ||
        composite.attributes.length !== 1 || composite.getAttribute('class') !== 'zig-math-composite') return false;
    if ([...composite.childNodes].some(node => node.nodeType !== 1)) return false;
    if (composite.children.length !== 2) return false;
    const visual = composite.children[0];
    const semantic = composite.children[1];
    return allowsVisualTree(visual) && semantic.localName === 'math' &&
      semantic.getAttribute('class') === 'zig-math' &&
      visual.classList.contains(semantic.getAttribute('display') === 'block' ? 'zig-math-display' : 'zig-math-inline');
  }

  function allowsStyle(element) {
    return element.closest('.zig-math-composite') !== null &&
      allowsElement(
        element.localName,
        element.namespaceURI,
        [...element.attributes].map(attribute => [attribute.name, attribute.value]),
        element.classList.contains('zig-math-html')
      );
  }

  return Object.freeze({ allowsElement, allowsGlyphText, allowsStyle, allowsTree, namespace });
});
