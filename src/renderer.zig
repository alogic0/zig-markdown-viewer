const std = @import("std");
const builtin = @import("builtin");
const markdown = @import("markdown");
const highlight = @import("highlight.zig");
const unicode_slug = @import("unicode_slug.zig");

const allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.page_allocator;
const Renderer = markdown.Renderer(*const HeadingIndex);

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

    var headings = HeadingIndex.init(gpa, document) catch return error.OutOfMemory;
    defer headings.deinit();

    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    const renderer: Renderer = .{ .context = &headings, .renderFn = renderNode };
    renderer.render(document, &writer.writer) catch return error.RenderFailed;
    return writer.toOwnedSlice() catch return error.OutOfMemory;
}

const Heading = struct {
    text: []u8,
    slug: []u8,
};

const HeadingIndex = struct {
    allocator: std.mem.Allocator,
    items: std.AutoHashMap(markdown.Document.Node.Index, Heading),

    fn init(gpa: std.mem.Allocator, document: markdown.Document) error{OutOfMemory}!HeadingIndex {
        var result: HeadingIndex = .{
            .allocator = gpa,
            .items = .init(gpa),
        };
        errdefer result.deinit();

        var counts = std.StringHashMap(u32).init(gpa);
        defer counts.deinit();

        for (0..document.nodeCount()) |ordinal| {
            const view = document.nodeAt(ordinal).?;
            if (view.tag != .heading) continue;
            const heading = try buildHeading(
                gpa,
                document,
                view.index,
                &counts,
            );
            errdefer {
                gpa.free(heading.text);
                gpa.free(heading.slug);
            }
            try result.items.put(view.index, heading);
        }
        return result;
    }

    fn deinit(index: *HeadingIndex) void {
        var values = index.items.valueIterator();
        while (values.next()) |heading| {
            index.allocator.free(heading.text);
            index.allocator.free(heading.slug);
        }
        index.items.deinit();
        index.* = undefined;
    }

    fn get(index: HeadingIndex, node: markdown.Document.Node.Index) ?Heading {
        return index.items.get(node);
    }
};

fn buildHeading(
    gpa: std.mem.Allocator,
    document: markdown.Document,
    node: markdown.Document.Node.Index,
    counts: *std.StringHashMap(u32),
) error{OutOfMemory}!Heading {
    const text = try headingTextAlloc(gpa, document, node);
    errdefer gpa.free(text);

    const base = try slugAlloc(gpa, text);
    var base_owned = true;
    errdefer if (base_owned) gpa.free(base);

    if (counts.getPtr(base)) |count| {
        count.* += 1;
        const unique = try std.fmt.allocPrint(gpa, "{s}-{d}", .{ base, count.* });
        gpa.free(base);
        base_owned = false;
        return .{ .text = text, .slug = unique };
    }

    try counts.put(base, 1);
    return .{ .text = text, .slug = base };
}

fn headingTextAlloc(
    gpa: std.mem.Allocator,
    document: markdown.Document,
    heading: markdown.Document.Node.Index,
) error{OutOfMemory}![]u8 {
    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    for (document.children(heading)) |child| {
        writeHeadingText(document, child, &writer.writer) catch return error.OutOfMemory;
    }
    return writer.toOwnedSlice();
}

fn writeHeadingText(
    document: markdown.Document,
    node: markdown.Document.Node.Index,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    const view = document.nodeAt(@backingInt(node)).?;
    switch (view.tag) {
        .link, .strong, .emphasis, .strikethrough => {
            for (document.children(node)) |child| {
                try writeHeadingText(document, child, writer);
            }
        },
        .image, .html_inline => {},
        .code_span, .text => try writer.writeAll(document.string(view.data.text.content)),
        .footnote_reference => try writer.print(
            "{d}",
            .{footnoteOrdinal(document, document.string(view.data.text.content))},
        ),
        .line_break, .soft_break => try writer.writeByte('\n'),
        else => {},
    }
}

fn footnoteOrdinal(document: markdown.Document, label: []const u8) usize {
    var ordinal: usize = 0;
    for (0..document.nodeCount()) |node_ordinal| {
        const view = document.nodeAt(node_ordinal).?;
        if (view.tag != .footnote_definition) continue;
        ordinal += 1;
        if (std.ascii.eqlIgnoreCase(
            document.string(view.data.footnote_definition.label),
            label,
        )) return ordinal;
    }
    return 0;
}

fn slugAlloc(
    gpa: std.mem.Allocator,
    text: []const u8,
) error{OutOfMemory}![]u8 {
    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    var wrote_content = false;
    var pending_separator = false;
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();

    while (iterator.nextCodepoint()) |codepoint| {
        appendSlugCodepoint(
            &writer.writer,
            codepoint,
            &wrote_content,
            &pending_separator,
        ) catch return error.OutOfMemory;
    }

    if (!wrote_content) writer.writer.writeAll("section") catch return error.OutOfMemory;
    return writer.toOwnedSlice();
}

fn appendSlugCodepoint(
    writer: *std.Io.Writer,
    codepoint: u21,
    wrote_content: *bool,
    pending_separator: *bool,
) std.Io.Writer.Error!void {
    if (codepoint == '-' or unicode_slug.isWhitespace(codepoint)) {
        if (wrote_content.*) pending_separator.* = true;
        return;
    }

    const folded = unicode_slug.fold(codepoint);
    if (!unicode_slug.isLetter(folded) and !unicode_slug.isNumber(folded)) return;

    if (pending_separator.*) {
        try writer.writeByte('-');
        pending_separator.* = false;
    }
    var encoded: [4]u8 = undefined;
    const length = std.unicode.utf8Encode(folded, &encoded) catch unreachable;
    try writer.writeAll(encoded[0..length]);
    wrote_content.* = true;
}

fn renderNode(
    renderer: Renderer,
    document: markdown.Document,
    node: markdown.Document.Node.Index,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    const view = document.nodeAt(@backingInt(node)).?;
    switch (view.tag) {
        .heading => {
            const heading = renderer.context.get(node).?;
            const level = view.data.heading.level;
            try writer.print(
                "<h{d} id=\"{f}\"><a class=\"zig-md-heading-anchor\" href=\"#",
                .{ level, markdown.fmtHtml(heading.slug) },
            );
            try writeUriFragment(writer, heading.slug);
            try writer.print(
                "\" aria-label=\"Link to {f}\">#</a>",
                .{markdown.fmtHtml(heading.text)},
            );
            for (document.children(node)) |child| {
                try renderer.renderFn(renderer, document, child, writer);
            }
            try writer.print("</h{d}>\n", .{level});
        },
        .list_item => {
            const item = view.data.list_item;
            if (item.task == .none) {
                try writer.writeAll("<li>");
            } else {
                try writer.writeAll("<li class=\"zig-md-task-item\">");
            }
            switch (item.task) {
                .none => {},
                .unchecked => try writer.writeAll("<input type=\"checkbox\" disabled=\"\" /> "),
                .checked => try writer.writeAll("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "),
            }
            for (document.children(node)) |child| {
                const child_view = document.nodeAt(@backingInt(child)).?;
                if (item.tight and child_view.tag == .paragraph) {
                    for (document.children(child)) |paragraph_child| {
                        try renderer.renderFn(renderer, document, paragraph_child, writer);
                    }
                } else {
                    try renderer.renderFn(renderer, document, child, writer);
                }
            }
            try writer.writeAll("</li>\n");
        },
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
            if (highlight.renderAlloc(renderer.context.allocator, language, content)) |html| {
                defer renderer.context.allocator.free(html);
                try writer.writeAll(html);
            } else {
                try writer.print("{f}", .{markdown.fmtHtml(content)});
            }
            try writer.writeAll("</code></pre>\n");
        },
        else => try renderer.renderDefault(document, node, writer),
    }
}

fn writeUriFragment(writer: *std.Io.Writer, fragment: []const u8) std.Io.Writer.Error!void {
    const hex = "0123456789ABCDEF";
    for (fragment) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or
            byte == '!' or byte == '~' or byte == '*' or byte == '\'' or
            byte == '(' or byte == ')')
        {
            try writer.writeByte(byte);
        } else {
            try writer.writeAll(&.{ '%', hex[byte >> 4], hex[byte & 0x0f] });
        }
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

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1 id=\"viewer\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<table>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "checked=\"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<li class=\"zig-md-task-item\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-keyword") != null);
}

test "generates compatible unique heading anchors" {
    const html = try renderAlloc(std.testing.allocator,
        \\# 2.1 Core Directories and Purposes
        \\# Café *déjà*
        \\# Café déjà
        \\# !!!
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(
        u8,
        html,
        "<h1 id=\"21-core-directories-and-purposes\"><a class=\"zig-md-heading-anchor\" href=\"#21-core-directories-and-purposes\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"cafe-deja\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"cafe-deja-2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"section\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "aria-label=\"Link to Café déjà\"") != null);
}

test "percent-encodes Unicode heading fragments" {
    const html = try renderAlloc(std.testing.allocator, "# 東京\n");
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"東京\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "href=\"#%E6%9D%B1%E4%BA%AC\"") != null);
}

test "classifies non-Latin heading slugs with generated Unicode data" {
    const html = try renderAlloc(std.testing.allocator,
        \\# ПРИВЕТ
        \\# مرحبا، ١٢٣ 😀
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"привет\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"مرحبا-١٢٣\"") != null);
}

test "adds a class only to task list items" {
    const html = try renderAlloc(std.testing.allocator,
        \\- [x] done
        \\- plain
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<li class=\"zig-md-task-item\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<li>plain</li>") != null);
}

test "escapes code block language and source" {
    const html = try renderAlloc(std.testing.allocator, "```x&amp;\n<a>\n```\n");
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "language-x&amp;amp") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;a&gt;") != null);
}

test "highlights verified core, optional, and aliased fenced languages" {
    const html = try renderAlloc(std.testing.allocator,
        \\```js
        \\const answer = 42;
        \\```
        \\```html
        \\<main class="page">Hello</main>
        \\```
        \\```css
        \\.page { color: red; }
        \\```
        \\```ziggy
        \\answer = 42
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-js\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-keyword") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-property") != null);
}

test "unknown fenced languages remain safely escaped" {
    const html = try renderAlloc(std.testing.allocator,
        \\```unknown-language
        \\<script>alert("no")</script>
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;script&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-") == null);
}

test "experimental and unsupported dialect fences remain plain" {
    const html = try renderAlloc(std.testing.allocator,
        \\```jsx
        \\const node = <main />;
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "language-jsx") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;main /&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-") == null);
}
