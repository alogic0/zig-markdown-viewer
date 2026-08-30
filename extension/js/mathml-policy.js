(function (root, factory) {
  const policy = factory();
  if (typeof module === 'object' && module.exports) module.exports = policy;
  root.ZigMarkdownMathMlPolicy = policy;
})(typeof globalThis === 'object' ? globalThis : this, () => {
  'use strict';

  const namespace = 'http://www.w3.org/1998/Math/MathML';
  const elements = new Set([
    'math', 'mrow', 'mi', 'mn', 'mo', 'mtext', 'mspace', 'mfrac', 'msqrt',
    'mroot', 'msub', 'msup', 'msubsup', 'munder', 'mover', 'munderover',
    'mstyle', 'mtable', 'mtr', 'mtd',
  ]);
  const spaceWidths = new Set([
    '-0.1667em', '0.1667em', '0.2222em', '0.2778em', '0.3333em', '1em', '2em',
  ]);
  const mathSizes = new Set([
    '0.5em', '0.7em', '0.8em', '0.85em', '1em',
    '1.2em', '1.44em', '1.73em', '2.07em', '2.49em',
  ]);

  function allowsElement(name, elementNamespace, attributes, isRoot) {
    if (elementNamespace !== namespace || !elements.has(name)) return false;
    const values = new Map(attributes);
    if (values.size !== attributes.length) return false;
    if (isRoot) {
      return name === 'math' &&
        values.size === 2 &&
        values.get('class') === 'zig-math' &&
        ['inline', 'block'].includes(values.get('display'));
    }
    if (name === 'mspace') {
      return values.size === 1 && spaceWidths.has(values.get('width'));
    }
    if (name === 'mtd') {
      return values.size === 0 ||
        (values.size === 1 && ['right', 'left'].includes(values.get('columnalign')));
    }
    if (name === 'mi') {
      return values.size === 0 ||
        (values.size === 1 && values.get('mathvariant') === 'normal');
    }
    if (name === 'mfrac') {
      return values.size === 0 ||
        (values.size === 1 && ['true', 'false'].includes(values.get('displaystyle'))) ||
        (values.size === 1 && values.get('linethickness') === '0');
    }
    if (name === 'mover') {
      return values.size === 0 ||
        (values.size === 1 && values.get('accent') === 'true');
    }
    if (name === 'munder') {
      return values.size === 0 ||
        (values.size === 1 && values.get('accentunder') === 'true');
    }
    if (name === 'mo') {
      return values.size === 0 ||
        (values.size === 1 && values.get('stretchy') === 'true');
    }
    if (name === 'mstyle') {
      if (values.size === 1) return mathSizes.has(values.get('mathsize'));
      if (values.size !== 2) return false;
      const displaystyle = values.get('displaystyle');
      const scriptlevel = values.get('scriptlevel');
      return (displaystyle === 'true' && scriptlevel === '0') ||
        (displaystyle === 'false' && ['0', '1', '2'].includes(scriptlevel));
    }
    return values.size === 0;
  }

  function allowsTree(mathRoot) {
    const descendants = [mathRoot, ...mathRoot.querySelectorAll('*')];
    return descendants.every((element, index) => allowsElement(
      element.localName,
      element.namespaceURI,
      [...element.attributes].map(attribute => [attribute.name, attribute.value]),
      index === 0
    ));
  }

  return Object.freeze({ allowsElement, allowsTree, namespace });
});
