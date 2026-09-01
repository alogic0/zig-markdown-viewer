'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const languages = require('../extension/js/source-languages.js');

test('maps supported local source URLs and special filenames', () => {
  const cases = new Map([
    ['file:///tmp/main.ZIG?raw=1', 'zig'],
    ['file:///tmp/CMakeLists.txt', 'cmake'],
    ['file:///tmp/Dockerfile', 'dockerfile'],
    ['file:///tmp/project/BUILD', 'starlark'],
    ['file:///tmp/types.d.ts', 'typescript'],
    ['file:///tmp/hello%20world.rs', 'rust'],
  ]);
  for (const [url, expected] of cases) {
    assert.equal(languages.languageForUrl(url), expected, url);
  }
  assert.equal(languages.fileName('file:///tmp/hello%20world.rs'), 'hello world.rs');
});

test('leaves remote URLs, unsupported dialects, and binary files alone', () => {
  for (const url of [
    'https://example.test/README.md',
    'https://example.test/component.tsx',
    'https://example.test/src/main.zig',
    'https://raw.githubusercontent.com/kristoff-it/superhtml/main/src/Ast.zig',
    'https://example.test/image.svg',
    'https://example.test/archive.zig.zip',
    'data:text/plain,const%20x=1',
  ]) assert.equal(languages.languageForUrl(url), null, url);
});

test('builds a case-insensitive main-frame redirect that preserves the original URL', () => {
  const patterns = languages.navigationRegexes.map(value => new RegExp(value, 'i'));
  const matches = url => patterns.some(pattern => pattern.test(url));
  assert.ok(matches('file:///tmp/main.zig?download=1&raw=1'));
  assert.ok(matches('file:///tmp/Makefile'));
  assert.ok(!matches('https://example.test/src/main.zig'));
  assert.ok(!matches('https://example.test/src/main.zig.exe'));

  const rules = languages.redirectRules(1001, 'chrome-extension://viewer/source.html');
  assert.ok(rules.length > 1);
  assert.deepEqual(rules.map(rule => rule.id), rules.map((_, index) => 1001 + index));
  const rule = rules[0];
  assert.equal(rule.id, 1001);
  assert.deepEqual(rule.condition.resourceTypes, ['main_frame']);
  assert.equal(rule.condition.isUrlFilterCaseSensitive, false);
  assert.equal(
    rule.action.redirect.regexSubstitution,
    'chrome-extension://viewer/source.html#\\0'
  );
});
