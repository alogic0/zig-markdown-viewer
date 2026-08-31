'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const standalone = require('../extension/js/standalone.js');
const contentCss = readFileSync(path.join(__dirname, '../extension/css/content.css'), 'utf8');

class FakeClassList {
  constructor(...names) {
    this.names = new Set(names);
  }

  contains(name) {
    return this.names.has(name);
  }

  toggle(name, force) {
    if (force !== undefined) {
      if (force) this.names.add(name);
      else this.names.delete(name);
      return force;
    }
    if (this.names.has(name)) {
      this.names.delete(name);
      return false;
    }
    this.names.add(name);
    return true;
  }

  remove(name) {
    this.names.delete(name);
  }
}

class FakeButton {
  constructor() {
    this.attributes = new Map();
    this.listeners = new Map();
  }

  addEventListener(name, listener) {
    this.listeners.set(name, listener);
  }

  setAttribute(name, value) {
    this.attributes.set(name, value);
  }

  removeAttribute(name) {
    this.attributes.delete(name);
  }

  click() {
    this.listeners.get('click')();
  }
}

test('builds one standalone document with embedded CSS and JavaScript', () => {
  const html = standalone.buildHtml({
    title: 'Example <document>',
    theme: 'dark',
    centered: true,
    tocVisible: true,
    codeWrap: true,
    maxWidth: 1080,
    fontSize: 17,
    lineHeight: 1.7,
    css: '#zig-md-document { color: red; }',
    documentHtml: '<h1 id="hello">Hello</h1><div class="zig-md-code-block"><pre><code>const x = 1;</code></pre><button class="zig-md-copy">Copy</button></div>',
    tocHtml: '<a class="level-1" href="#hello">Hello</a>',
  });

  assert.match(html, /^<!doctype html>/);
  assert.match(html, /<title>Example &lt;document&gt;<\/title>/);
  assert.match(html, /data-zig-markdown-theme="dark"/);
  assert.match(html, /class="is-centered has-toc code-wrap"/);
  assert.match(html, /--zig-md-width:1080px;--zig-md-font-size:17px;--zig-md-line-height:1.7/);
  assert.match(html, /<style>\s*#zig-md-document \{ color: red; \}\s*<\/style>/);
  assert.match(html, /<main id="zig-md-document"><h1 id="hello">Hello<\/h1>/);
  assert.match(html, /data-action="toc"/);
  assert.match(html, /data-action="theme"/);
  assert.match(html, /classList\.toggle\('has-toc'\)/);
  assert.match(html, /zigMarkdownTheme = dark \? 'light' : 'dark'/);
  assert.match(html, /<script>\s*\(\(\) => \{/);
  assert.doesNotMatch(html, /<(?:link|script)[^>]+(?:href|src)=/);

  const embeddedScript = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/)[1];
  assert.doesNotThrow(() => new vm.Script(embeddedScript));

  const root = { dataset: { zigMarkdownTheme: 'dark' }, scrollHeight: 1000 };
  const shell = { classList: new FakeClassList('has-toc') };
  const tocToggle = new FakeButton();
  const themeToggle = new FakeButton();
  const tocLink = new FakeButton();
  tocLink.hash = '#hello';
  tocLink.classList = new FakeClassList('level-1');
  const heading = { getBoundingClientRect: () => ({ top: 0 }) };
  const mobileQuery = { matches: true, addEventListener() {} };
  const context = vm.createContext({
    document: {
      documentElement: root,
      querySelector(selector) {
        return {
          '#zig-md-shell': shell,
          '[data-action="toc"]': tocToggle,
          '[data-action="theme"]': themeToggle,
        }[selector] || null;
      },
      querySelectorAll(selector) {
        return selector === '#zig-md-toc nav a' ? [tocLink] : [];
      },
      getElementById(id) { return id === 'hello' ? heading : null; },
    },
    navigator: {},
    window: { addEventListener() {}, scrollTo() {} },
    requestAnimationFrame() { return 1; },
    matchMedia(query) {
      return query === '(max-width: 680px)'
        ? mobileQuery
        : { matches: false, addEventListener() {} };
    },
    scrollY: 0,
    innerHeight: 800,
    setTimeout,
  });
  new vm.Script(embeddedScript).runInContext(context);

  assert.equal(shell.classList.contains('has-toc'), false);
  assert.equal(tocToggle.attributes.get('aria-pressed'), 'false');
  tocToggle.click();
  assert.equal(shell.classList.contains('has-toc'), true);
  assert.equal(tocToggle.attributes.get('aria-pressed'), 'true');
  tocLink.click();
  assert.equal(shell.classList.contains('has-toc'), false);
  assert.equal(tocToggle.attributes.get('aria-pressed'), 'false');
  themeToggle.click();
  assert.equal(root.dataset.zigMarkdownTheme, 'light');
  assert.equal(themeToggle.attributes.get('aria-label'), 'Switch to dark theme');
});

test('creates safe HTML filenames from Markdown URLs', () => {
  assert.equal(
    standalone.downloadName('file:///tmp/My%20Roadmap.markdown'),
    'My Roadmap.html'
  );
  assert.equal(
    standalone.downloadName('https://example.test/docs/report.MDX?raw=1'),
    'report.html'
  );
  assert.equal(standalone.downloadName('not a URL'), 'markdown-document.html');
});

test('keeps code copy controls visible without hover', () => {
  assert.match(
    contentCss,
    /@media \(hover: none\), \(pointer: coarse\) \{\s*\.zig-md-code-block > \.zig-md-copy \{ opacity: 1; \}/
  );
});

test('styles native inline display and printed math', () => {
  assert.match(contentCss, /\.zig-math\[display="inline"\][^{]*\{[^}]*vertical-align:/s);
  assert.match(contentCss, /\.zig-math\[display="block"\][^{]*\{[^}]*display: inline-block;[^}]*overflow-x: auto;/s);
  assert.match(contentCss, /\.zig-math-display\.zig-math-display-center[^{]*\{[^}]*text-align: center;/s);
  assert.match(contentCss, /\.zig-math-display\.zig-math-display-start[^{]*\{[^}]*text-align: start;/s);
  assert.match(contentCss, /@media print \{[\s\S]*\.zig-math\[display="block"\][^{]*\{ break-inside: avoid; \}/);
});

test('matches the Zig 0.17 standalone language reference code style', () => {
  const light = contentCss.match(/^:root \{([\s\S]*?)^\}/m)[1];
  const dark = contentCss.match(
    /^:root\[data-zig-markdown-theme='dark'\] \{([\s\S]*?)^\}/m
  )[1];

  for (const declaration of [
    '--zig-md-bg: #ffffff;',
    '--zig-md-code: #f8f8f8;',
    '--zig-md-code-text: #000000;',
    '--zig-md-syntax-comment: #545454;',
    '--zig-md-syntax-keyword: #333333;',
    '--zig-md-syntax-string: #dd1144;',
    '--zig-md-syntax-builtin: #005c7a;',
    '--zig-md-syntax-null: #005c5c;',
    '--zig-md-syntax-number: #005c5c;',
    '--zig-md-syntax-function: #990000;',
    '--zig-md-syntax-type: #445588;',
  ]) {
    assert.ok(light.includes(declaration), `missing light style: ${declaration}`);
  }

  for (const declaration of [
    '--zig-md-bg: #121212;',
    '--zig-md-code: #222222;',
    '--zig-md-code-text: #cccccc;',
    '--zig-md-syntax-comment: #aaaa77;',
    '--zig-md-syntax-keyword: #eeeeee;',
    '--zig-md-syntax-string: #22ee55;',
    '--zig-md-syntax-builtin: #ff894c;',
    '--zig-md-syntax-null: #ff8080;',
    '--zig-md-syntax-number: #ff8080;',
    '--zig-md-syntax-function: #b1a0f8;',
    '--zig-md-syntax-type: #6688ff;',
  ]) {
    assert.ok(dark.includes(declaration), `missing dark style: ${declaration}`);
  }

  assert.match(
    contentCss,
    /:is\(\.syntax-comment, \.syntax-documentation\) \{[^}]*font-style: italic;/s
  );
  assert.match(
    contentCss,
    /:is\(\.syntax-keyword, \.syntax-macro\) \{[^}]*font-weight: bold;/s
  );
  assert.match(
    contentCss,
    /:is\(\.syntax-function, \.syntax-constructor\) \{[^}]*font-weight: bold;/s
  );
  assert.match(
    contentCss,
    /:is\(\.syntax-type,[^}]*\.syntax-property\) \{[^}]*font-weight: bold;/s
  );
});

test('falls back to safe display settings', () => {
  const html = standalone.buildHtml({
    title: '',
    theme: 'unknown',
    centered: false,
    tocVisible: false,
    codeWrap: false,
    maxWidth: 'not-a-number',
    fontSize: null,
    lineHeight: undefined,
    css: '',
    documentHtml: '<p>Text</p>',
    tocHtml: '',
  });

  assert.match(html, /data-zig-markdown-theme="auto"/);
  assert.match(html, /class="" style="--zig-md-width:960px;--zig-md-font-size:16px;--zig-md-line-height:1.65"/);
  assert.match(html, /<title>Markdown document<\/title>/);
});
