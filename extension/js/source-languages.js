(() => {
  'use strict';

  const extensions = Object.freeze({
    zig: 'zig',
    zon: 'zig',
    c: 'c',
    h: 'c',
    cc: 'cpp',
    cpp: 'cpp',
    cxx: 'cpp',
    hpp: 'cpp',
    hh: 'cpp',
    hxx: 'cpp',
    cs: 'c-sharp',
    m: 'objc',
    mm: 'objc',
    rs: 'rust',
    go: 'go',
    java: 'java',
    kt: 'kotlin',
    kts: 'kotlin',
    swift: 'swift',
    js: 'javascript',
    mjs: 'javascript',
    cjs: 'javascript',
    ts: 'typescript',
    mts: 'typescript',
    cts: 'typescript',
    py: 'python',
    rb: 'ruby',
    php: 'php',
    lua: 'lua',
    pl: 'perl',
    pm: 'perl',
    sh: 'bash',
    bash: 'bash',
    zsh: 'bash',
    fish: 'fish',
    ps1: 'powershell',
    bat: 'batch',
    cmd: 'batch',
    ex: 'elixir',
    exs: 'elixir',
    jl: 'julia',
    hs: 'haskell',
    lhs: 'haskell',
    ml: 'ocaml',
    mli: 'ocaml',
    fs: 'fsharp',
    fsx: 'fsharp',
    gleam: 'gleam',
    d: 'd',
    v: 'v',
    odin: 'odin',
    c3: 'c3',
    elm: 'elm',
    purs: 'purescript',
    sv: 'systemverilog',
    svh: 'systemverilog',
    nim: 'nim',
    asm: 'asm',
    s: 'asm',
    nasm: 'nasm',
    scad: 'openscad',
    ha: 'hare',
    ncl: 'nickel',
    agda: 'agda',
    vim: 'vim',
    tal: 'uxntal',
    f: 'fortran',
    f90: 'fortran',
    f95: 'fortran',
    f03: 'fortran',
    f08: 'fortran',
    sql: 'sql',
    json: 'json',
    toml: 'toml',
    yaml: 'yaml',
    yml: 'yaml',
    hcl: 'hcl',
    tf: 'hcl',
    nix: 'nix',
    kdl: 'kdl',
    proto: 'proto',
    tex: 'latex',
    sty: 'latex',
    cls: 'latex',
    html: 'html',
    htm: 'html',
    xml: 'xml',
    xsd: 'xml',
    xsl: 'xml',
    xslt: 'xml',
    csproj: 'xml',
    props: 'xml',
    css: 'css',
    vue: 'vue',
    astro: 'astro',
    diff: 'diff',
    patch: 'diff',
    cmake: 'cmake',
    ninja: 'ninja',
    bzl: 'starlark',
    bazel: 'starlark',
    typ: 'typst',
    org: 'org',
    rst: 'rst',
    po: 'po',
    pot: 'po',
    hurl: 'hurl',
    mlir: 'mlir',
    td: 'tablegen',
    ll: 'llvm',
    pdll: 'pdll',
    dtd: 'dtd',
    eml: 'mail',
    ziggy: 'ziggy',
    'ziggy-schema': 'ziggy-schema',
    scripty: 'scripty',
    superhtml: 'superhtml',
  });

  const fileNames = Object.freeze({
    dockerfile: 'dockerfile',
    makefile: 'make',
    gnumakefile: 'make',
    'cmakelists.txt': 'cmake',
    build: 'starlark',
    workspace: 'starlark',
    'git-rebase-todo': 'git-rebase',
  });

  function fileName(url) {
    try {
      const path = new URL(url).pathname;
      const encoded = path.slice(path.lastIndexOf('/') + 1);
      try {
        return decodeURIComponent(encoded);
      } catch {
        return encoded;
      }
    } catch {
      return '';
    }
  }

  function languageForUrl(url) {
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      return null;
    }
    if (!['file:', 'http:', 'https:'].includes(parsed.protocol)) return null;

    const name = fileName(url).toLowerCase();
    if (fileNames[name]) return fileNames[name];
    const dot = name.lastIndexOf('.');
    return dot >= 0 ? extensions[name.slice(dot + 1)] || null : null;
  }

  function regexEscape(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function groups(values, size) {
    const result = [];
    for (let offset = 0; offset < values.length; offset += size) {
      result.push(values.slice(offset, offset + size));
    }
    return result;
  }

  function extensionRegex(names) {
    const pattern = names.map(regexEscape).join('|');
    return `^(?:https?|file)://[^?#]*\\.(?:${pattern})(?:\\?[^#]*)?$`;
  }

  const navigationRegexes = Object.freeze([
    ...groups(Object.keys(extensions), 12).map(extensionRegex),
    `^(?:https?|file)://[^?#]*/(?:${Object.keys(fileNames).map(regexEscape).join('|')})(?:\\?[^#]*)?$`,
  ]);

  function redirectRules(firstId, destination) {
    return navigationRegexes.map((regexFilter, index) => ({
      id: firstId + index,
      priority: 1,
      action: {
        type: 'redirect',
        redirect: { regexSubstitution: `${destination}#\\0` },
      },
      condition: {
        regexFilter,
        isUrlFilterCaseSensitive: false,
        resourceTypes: ['main_frame'],
      },
    }));
  }

  globalThis.ZigSourceLanguages = Object.freeze({
    extensions,
    fileNames,
    fileName,
    languageForUrl,
    navigationRegexes,
    redirectRules,
  });

  if (typeof module === 'object' && module.exports) module.exports = globalThis.ZigSourceLanguages;
})();
