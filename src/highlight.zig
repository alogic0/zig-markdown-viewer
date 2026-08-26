const std = @import("std");
const syntax = @import("native_syntax");

const verified_backends = [_]syntax.Backend{
    syntax.languages.zig.backend,
    syntax.languages.bash.backend,
    syntax.languages.rpmbash.backend,
    syntax.languages.javascript.backend,
    syntax.languages.typescript.backend,
    syntax.languages.rust.backend,
    syntax.languages.json.backend,
    syntax.languages.toml.backend,
    syntax.languages.yaml.backend,
    syntax.languages.dockerfile.backend,
    syntax.languages.python.backend,
    syntax.languages.sql.backend,
    syntax.languages.hcl.backend,
    syntax.languages.make.backend,
    syntax.languages.cmake.backend,
    syntax.languages.kdl.backend,
    syntax.languages.ssh_config.backend,
    syntax.languages.gitcommit.backend,
    syntax.languages.git_rebase.backend,
    syntax.languages.diff.backend,
    @import("native_syntax_ziggy").backend,
    @import("native_syntax_ziggy_schema").backend,
    @import("native_syntax_scripty").backend,
    @import("native_syntax_html").backend,
    @import("native_syntax_xml").backend,
    @import("native_syntax_css").backend,
    @import("native_syntax_superhtml").backend,
    @import("native_syntax_markdown").backend,
};

const aliases = [_]struct {
    alias: []const u8,
    canonical: []const u8,
}{
    .{ .alias = "sh", .canonical = "bash" },
    .{ .alias = "shell", .canonical = "bash" },
    .{ .alias = "patch", .canonical = "diff" },
    .{ .alias = "docker", .canonical = "dockerfile" },
    .{ .alias = "yml", .canonical = "yaml" },
    .{ .alias = "py", .canonical = "python" },
    .{ .alias = "terraform", .canonical = "hcl" },
    .{ .alias = "makefile", .canonical = "make" },
    .{ .alias = "sshconfig", .canonical = "ssh-config" },
    .{ .alias = "git-commit", .canonical = "gitcommit" },
    .{ .alias = "gitrebase", .canonical = "git-rebase" },
    .{ .alias = "js", .canonical = "javascript" },
    .{ .alias = "rs", .canonical = "rust" },
    .{ .alias = "ts", .canonical = "typescript" },
    .{ .alias = "md", .canonical = "markdown" },
    .{ .alias = "smd", .canonical = "markdown" },
    .{ .alias = "supermd", .canonical = "markdown" },
    .{ .alias = "markdown-inline", .canonical = "markdown" },
    .{ .alias = "rpm-bash", .canonical = "rpmbash" },
    .{ .alias = "csproj", .canonical = "xml" },
    .{ .alias = "props", .canonical = "xml" },
};

pub fn fenceLanguage(info: []const u8) []const u8 {
    var start: usize = 0;
    while (start < info.len and isInfoWhitespace(info[start])) start += 1;

    var end = start;
    while (end < info.len and !isInfoWhitespace(info[end])) end += 1;
    return info[start..end];
}

pub fn backendFor(name: []const u8) ?syntax.Backend {
    if (canonicalBackendFor(name)) |backend| return backend;

    for (aliases) |entry| {
        if (std.ascii.eqlIgnoreCase(name, entry.alias)) {
            return canonicalBackendFor(entry.canonical);
        }
    }
    return null;
}

pub fn renderAlloc(
    allocator: std.mem.Allocator,
    language: []const u8,
    source: []const u8,
) ?[]u8 {
    const backend = backendFor(fenceLanguage(language)) orelse return null;

    var sink: syntax.CaptureSink = .init(allocator, source.len);
    defer sink.deinit();
    backend.highlight(source, &sink) catch return null;

    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    syntax.html.render(source, sink.captures(), allocator, &writer.writer) catch return null;
    return writer.toOwnedSlice() catch null;
}

fn canonicalBackendFor(name: []const u8) ?syntax.Backend {
    for (verified_backends) |backend| {
        if (std.ascii.eqlIgnoreCase(name, backend.info.canonical_name)) return backend;
    }
    return null;
}

fn isInfoWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

test "routes every quality-verified backend" {
    for (verified_backends) |backend| {
        try std.testing.expect(backend.info.support_level != .experimental);
        try std.testing.expectEqualStrings(
            backend.info.canonical_name,
            backendFor(backend.info.canonical_name).?.info.canonical_name,
        );
    }
}

test "routes aliases and ignores fence attributes" {
    try std.testing.expectEqualStrings("javascript", backendFor("JS").?.info.canonical_name);
    try std.testing.expectEqualStrings("bash", backendFor("shell").?.info.canonical_name);
    try std.testing.expectEqualStrings("markdown", backendFor("md").?.info.canonical_name);
    try std.testing.expectEqualStrings("zig", backendFor(fenceLanguage(" zig title=demo")).?.info.canonical_name);
    try std.testing.expectEqual(null, backendFor("unknown-language"));
}

test "does not route experimental or unsupported dialect aliases" {
    for ([_][]const u8{
        "jsx",
        "tsx",
        "glsl",
        "conf",
        "nimble",
    }) |name| {
        try std.testing.expectEqual(null, backendFor(name));
    }
}

test "renders exact structural classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "javascript",
        "const answer = thing.value();",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">const</span> " ++
            "<span class=\"syntax-variable\">answer</span> " ++
            "<span class=\"syntax-operator\">=</span> " ++
            "<span class=\"syntax-variable\">thing</span>" ++
            "<span class=\"syntax-punctuation\">.</span>" ++
            "<span class=\"syntax-function syntax-property\">value</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-punctuation\">)</span>" ++
            "<span class=\"syntax-punctuation\">;</span>",
        html,
    );
}

test "renders exact verified lexical classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "json",
        "{\"ok\": true}",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-punctuation\">{</span>" ++
            "<span class=\"syntax-property\">&quot;ok&quot;</span>" ++
            "<span class=\"syntax-punctuation\">:</span> " ++
            "<span class=\"syntax-boolean\">true</span>" ++
            "<span class=\"syntax-punctuation\">}</span>",
        html,
    );
}

test "renders exact TOML key and value classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "toml",
        "title = \"demo\"",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-property\">title</span> " ++
            "<span class=\"syntax-operator\">=</span> " ++
            "<span class=\"syntax-string\">&quot;demo&quot;</span>",
        html,
    );
}

test "renders exact YAML key and value classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "yml",
        "name: \"demo\"\nenabled: true",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-property\">name</span>" ++
            "<span class=\"syntax-operator\">:</span> " ++
            "<span class=\"syntax-string\">&quot;demo&quot;</span>\n" ++
            "<span class=\"syntax-property\">enabled</span>" ++
            "<span class=\"syntax-operator\">:</span> " ++
            "<span class=\"syntax-boolean\">true</span>",
        html,
    );
}

test "renders exact composed Dockerfile classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "dockerfile",
        "RUN echo \"$HOME\"",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">RUN</span> " ++
            "<span class=\"syntax-builtin syntax-embedded syntax-function\">echo</span>" ++
            "<span class=\"syntax-embedded\"> </span>" ++
            "<span class=\"syntax-embedded syntax-string\">&quot;</span>" ++
            "<span class=\"syntax-embedded syntax-string syntax-variable\">$HOME</span>" ++
            "<span class=\"syntax-embedded syntax-string\">&quot;</span>",
        html,
    );
}

test "renders exact structural Python classifications" {
    const html = renderAlloc(
        std.testing.allocator,
        "py",
        "def greet(name: str):\n    return name.upper()",
    ).?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">def</span> " ++
            "<span class=\"syntax-function\">greet</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-parameter\">name</span>" ++
            "<span class=\"syntax-operator\">:</span> " ++
            "<span class=\"syntax-builtin syntax-type\">str</span>" ++
            "<span class=\"syntax-punctuation\">)</span>" ++
            "<span class=\"syntax-operator\">:</span>\n    " ++
            "<span class=\"syntax-keyword\">return</span> " ++
            "<span class=\"syntax-variable\">name</span>" ++
            "<span class=\"syntax-punctuation\">.</span>" ++
            "<span class=\"syntax-function syntax-property\">upper</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-punctuation\">)</span>",
        html,
    );
}

test "renders exact SQL lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "sql", "SELECT count(\"user_id\") WHERE id = :id;").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">SELECT</span> " ++
            "<span class=\"syntax-function\">count</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-property\">&quot;user_id&quot;</span>" ++
            "<span class=\"syntax-punctuation\">)</span> " ++
            "<span class=\"syntax-keyword\">WHERE</span> " ++
            "<span class=\"syntax-variable\">id</span> " ++
            "<span class=\"syntax-operator\">=</span> " ++
            "<span class=\"syntax-parameter\">:id</span>" ++
            "<span class=\"syntax-punctuation\">;</span>",
        html,
    );
}

test "renders exact HCL lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "terraform", "enabled = true\nname = format(\"app\")").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-property\">enabled</span> " ++
            "<span class=\"syntax-operator\">=</span> " ++
            "<span class=\"syntax-boolean\">true</span>\n" ++
            "<span class=\"syntax-property\">name</span> " ++
            "<span class=\"syntax-operator\">=</span> " ++
            "<span class=\"syntax-function\">format</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-string\">&quot;app&quot;</span>" ++
            "<span class=\"syntax-punctuation\">)</span>",
        html,
    );
}

test "renders exact composed Make classifications" {
    const html = renderAlloc(std.testing.allocator, "makefile", "app:\n\techo hi").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-label\">app</span>" ++
            "<span class=\"syntax-operator\">:</span>\n\t" ++
            "<span class=\"syntax-builtin syntax-embedded syntax-function\">echo</span>" ++
            "<span class=\"syntax-embedded\"> hi</span>",
        html,
    );
}

test "renders exact CMake lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "cmake", "if(ON)\n  message(\"ready\")\nendif()").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">if</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-boolean\">ON</span>" ++
            "<span class=\"syntax-punctuation\">)</span>\n  " ++
            "<span class=\"syntax-function\">message</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-string\">&quot;ready&quot;</span>" ++
            "<span class=\"syntax-punctuation\">)</span>\n" ++
            "<span class=\"syntax-keyword\">endif</span>" ++
            "<span class=\"syntax-punctuation\">(</span>" ++
            "<span class=\"syntax-punctuation\">)</span>",
        html,
    );
}

test "renders exact KDL lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "kdl", "service image=\"demo\" enabled=true").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-tag\">service</span> " ++
            "<span class=\"syntax-property\">image</span>" ++
            "<span class=\"syntax-operator\">=</span>" ++
            "<span class=\"syntax-string\">&quot;demo&quot;</span> " ++
            "<span class=\"syntax-property\">enabled</span>" ++
            "<span class=\"syntax-operator\">=</span>" ++
            "<span class=\"syntax-boolean\">true</span>",
        html,
    );
}

test "renders exact SSH config lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "sshconfig", "Host demo\n  Port 2222").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">Host</span> demo\n  " ++
            "<span class=\"syntax-property\">Port</span> " ++
            "<span class=\"syntax-number\">2222</span>",
        html,
    );
}

test "renders exact Git commit lexical classifications" {
    const html = renderAlloc(std.testing.allocator, "git-commit", "feat: render safely").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword syntax-markup-heading\">feat</span>" ++
            "<span class=\"syntax-punctuation syntax-markup-heading\">:</span>" ++
            "<span class=\"syntax-markup-heading\"> render safely</span>",
        html,
    );
}

test "renders exact composed Git rebase classifications" {
    const html = renderAlloc(std.testing.allocator, "gitrebase", "pick abc123 render safely\nexec echo done").?;
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<span class=\"syntax-keyword\">pick</span> " ++
            "<span class=\"syntax-constant\">abc123</span> " ++
            "<span class=\"syntax-string\">render safely</span>\n" ++
            "<span class=\"syntax-keyword\">exec</span> " ++
            "<span class=\"syntax-builtin syntax-embedded syntax-function\">echo</span>" ++
            "<span class=\"syntax-embedded\"> </span>" ++
            "<span class=\"syntax-embedded syntax-keyword\">done</span>",
        html,
    );
}

test "unsupported dialects request plain-text fallback" {
    try std.testing.expectEqual(
        null,
        renderAlloc(std.testing.allocator, "jsx", "const node = <main />"),
    );
}
