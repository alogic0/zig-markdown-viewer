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
        "python",
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

test "experimental languages request plain-text fallback" {
    try std.testing.expectEqual(
        null,
        renderAlloc(std.testing.allocator, "python", "def answer(): pass"),
    );
}
