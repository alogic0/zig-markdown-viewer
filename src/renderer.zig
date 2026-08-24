const std = @import("std");
const builtin = @import("builtin");
const markdown = @import("markdown");

const allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.page_allocator;
const Renderer = markdown.Renderer(void);

var input: []u8 = &.{};
var output: []u8 = &.{};
var last_error: ErrorCode = .none;

const ErrorCode = enum(u32) {
    none = 0,
    out_of_memory = 1,
    parse = 2,
    render = 3,
    invalid_input = 4,
};

/// Reserves a source buffer in WebAssembly memory. A later call invalidates
/// the previous input pointer.
export fn allocateSource(length: u32) u32 {
    releaseSource();
    last_error = .none;
    input = allocator.alloc(u8, length) catch {
        last_error = .out_of_memory;
        return 0;
    };
    return @intCast(@intFromPtr(input.ptr));
}

/// Parses the source buffer and returns the rendered HTML pointer. The output
/// remains valid until the next render or releaseOutput call.
export fn renderMarkdown(length: u32) u32 {
    releaseOutput();
    last_error = .none;
    if (length > input.len) {
        last_error = .invalid_input;
        return 0;
    }

    output = renderAlloc(allocator, input[0..length]) catch |err| {
        last_error = switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.ParseFailed => .parse,
            error.RenderFailed => .render,
        };
        return 0;
    };
    return @intCast(@intFromPtr(output.ptr));
}

export fn renderedLength() u32 {
    return @intCast(output.len);
}

export fn errorCode() u32 {
    return @backingInt(last_error);
}

export fn releaseSource() void {
    if (input.len != 0) allocator.free(input);
    input = &.{};
}

export fn releaseOutput() void {
    if (output.len != 0) allocator.free(output);
    output = &.{};
}

const RenderError = error{ OutOfMemory, ParseFailed, RenderFailed };

fn renderAlloc(gpa: std.mem.Allocator, source: []const u8) RenderError![]u8 {
    var parser = markdown.Parser.init(gpa) catch return error.OutOfMemory;
    defer parser.deinit();
    parser.feed(source) catch return error.ParseFailed;

    var document = parser.endInput() catch return error.ParseFailed;
    defer document.deinit(gpa);

    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    const renderer: Renderer = .{ .context = {}, .renderFn = renderNode };
    renderer.render(document, &writer.writer) catch return error.RenderFailed;
    return writer.toOwnedSlice() catch return error.OutOfMemory;
}

fn renderNode(
    renderer: Renderer,
    document: markdown.Document,
    node: markdown.Document.Node.Index,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    const view = document.nodeAt(@backingInt(node)).?;
    switch (view.tag) {
        .code_block => {
            const language = document.string(view.data.code_block.tag);
            const content = document.string(view.data.code_block.content);
            if (language.len == 0) {
                try writer.writeAll("<pre><code>");
            } else {
                try writer.print(
                    "<pre data-language=\"{f}\"><code class=\"language-{f}\">",
                    .{ markdown.fmtHtml(language), markdown.fmtHtml(language) },
                );
            }
            try writer.print("{f}</code></pre>\n", .{markdown.fmtHtml(content)});
        },
        else => try renderer.renderDefault(document, node, writer),
    }
}

test "renders the viewer's core Markdown features" {
    const source =
        \\# Viewer
        \\
        \\| left | right |
        \\| :--- | ---: |
        \\| one | two |
        \\
        \\- [x] done
        \\
        \\```zig
        \\const answer = 42;
        \\```
    ;
    const html = try renderAlloc(std.testing.allocator, source);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Viewer</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<table>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "checked=\"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-zig\"") != null);
}

test "escapes code block language and source" {
    const html = try renderAlloc(std.testing.allocator, "```x&amp;\n<a>\n```\n");
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "language-x&amp;amp") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;a&gt;") != null);
}
