const std = @import("std");
const syntax = @import("native_syntax");

const optional_backends = [_]syntax.Backend{
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
    .{ .alias = "assembly", .canonical = "asm" },
    .{ .alias = "sh", .canonical = "bash" },
    .{ .alias = "shell", .canonical = "bash" },
    .{ .alias = "glsl", .canonical = "c" },
    .{ .alias = "cs", .canonical = "c-sharp" },
    .{ .alias = "csharp", .canonical = "c-sharp" },
    .{ .alias = "c++", .canonical = "cpp" },
    .{ .alias = "patch", .canonical = "diff" },
    .{ .alias = "docker", .canonical = "dockerfile" },
    .{ .alias = "js", .canonical = "javascript" },
    .{ .alias = "jsx", .canonical = "javascript" },
    .{ .alias = "kt", .canonical = "kotlin" },
    .{ .alias = "objective-c", .canonical = "objc" },
    .{ .alias = "ps1", .canonical = "powershell" },
    .{ .alias = "protobuf", .canonical = "proto" },
    .{ .alias = "py", .canonical = "python" },
    .{ .alias = "rb", .canonical = "ruby" },
    .{ .alias = "rs", .canonical = "rust" },
    .{ .alias = "ts", .canonical = "typescript" },
    .{ .alias = "tsx", .canonical = "typescript" },
    .{ .alias = "yml", .canonical = "yaml" },
    .{ .alias = "md", .canonical = "markdown" },
    .{ .alias = "smd", .canonical = "markdown" },
    .{ .alias = "supermd", .canonical = "markdown" },
    .{ .alias = "markdown-inline", .canonical = "markdown" },
    .{ .alias = "conf", .canonical = "fish" },
    .{ .alias = "nushell", .canonical = "nu" },
    .{ .alias = "sshconfig", .canonical = "ssh-config" },
    .{ .alias = "git-commit", .canonical = "gitcommit" },
    .{ .alias = "gitrebase", .canonical = "git-rebase" },
    .{ .alias = "gettext", .canonical = "po" },
    .{ .alias = "restructuredtext", .canonical = "rst" },
    .{ .alias = "tex", .canonical = "latex" },
    .{ .alias = "orgmode", .canonical = "org" },
    .{ .alias = "email", .canonical = "mail" },
    .{ .alias = "rpm-spec", .canonical = "rpmspec" },
    .{ .alias = "rpm-bash", .canonical = "rpmbash" },
    .{ .alias = "f#", .canonical = "fsharp" },
    .{ .alias = "lisp", .canonical = "commonlisp" },
    .{ .alias = "purs", .canonical = "purescript" },
    .{ .alias = "dlang", .canonical = "d" },
    .{ .alias = "vlang", .canonical = "v" },
    .{ .alias = "system-verilog", .canonical = "systemverilog" },
    .{ .alias = "sv", .canonical = "systemverilog" },
    .{ .alias = "llvm-ir", .canonical = "llvm" },
    .{ .alias = "ll", .canonical = "llvm" },
    .{ .alias = "scad", .canonical = "openscad" },
    .{ .alias = "tree-sitter-query", .canonical = "query" },
    .{ .alias = "tsquery", .canonical = "query" },
    .{ .alias = "vimscript", .canonical = "vim" },
    .{ .alias = "comment-tags", .canonical = "comment" },
    .{ .alias = "nimble", .canonical = "toml" },
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
    inline for (comptime std.meta.declarations(syntax.languages)) |declaration| {
        const backend = @field(syntax.languages, declaration).backend;
        if (std.ascii.eqlIgnoreCase(name, backend.info.canonical_name)) return backend;
    }
    for (optional_backends) |backend| {
        if (std.ascii.eqlIgnoreCase(name, backend.info.canonical_name)) return backend;
    }
    return null;
}

fn isInfoWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

test "routes every core and optional backend" {
    inline for (comptime std.meta.declarations(syntax.languages)) |declaration| {
        const backend = @field(syntax.languages, declaration).backend;
        try std.testing.expectEqualStrings(
            backend.info.canonical_name,
            backendFor(backend.info.canonical_name).?.info.canonical_name,
        );
    }
    for (optional_backends) |backend| {
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
