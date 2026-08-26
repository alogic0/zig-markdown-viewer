'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');
const standalone = require('../extension/js/standalone.js');

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
    documentHtml: '<h1 id="hello">Hello</h1><pre><code>const x = 1;</code><button class="zig-md-copy">Copy</button></pre>',
    tocHtml: '<a class="level-1" href="#hello">Hello</a>',
  });

  assert.match(html, /^<!doctype html>/);
  assert.match(html, /<title>Example &lt;document&gt;<\/title>/);
  assert.match(html, /data-zig-markdown-theme="dark"/);
  assert.match(html, /class="is-centered has-toc code-wrap"/);
  assert.match(html, /--zig-md-width:1080px;--zig-md-font-size:17px;--zig-md-line-height:1.7/);
  assert.match(html, /<style>\s*#zig-md-document \{ color: red; \}\s*<\/style>/);
  assert.match(html, /<main id="zig-md-document"><h1 id="hello">Hello<\/h1>/);
  assert.match(html, /<script>\s*\(\(\) => \{/);
  assert.doesNotMatch(html, /<(?:link|script)[^>]+(?:href|src)=/);

  const embeddedScript = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/)[1];
  assert.doesNotThrow(() => new vm.Script(embeddedScript));
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
