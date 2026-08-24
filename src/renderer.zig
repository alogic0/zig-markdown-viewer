const std = @import("std");
const builtin = @import("builtin");
const markdown = @import("markdown");

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
    if (codepoint == '-' or isUnicodeWhitespace(codepoint)) {
        if (wrote_content.*) pending_separator.* = true;
        return;
    }

    const folded = foldSlugCodepoint(codepoint) orelse return;
    if (isCombiningMark(folded) or isUnicodePunctuationOrSymbol(folded)) return;

    if (pending_separator.*) {
        try writer.writeByte('-');
        pending_separator.* = false;
    }
    var encoded: [4]u8 = undefined;
    const length = std.unicode.utf8Encode(folded, &encoded) catch unreachable;
    try writer.writeAll(encoded[0..length]);
    wrote_content.* = true;
}

// Zig's standard library does not provide Unicode normalization or category
// tables. Fold the Latin forms produced by NFKD in typical document titles,
// lowercase common alphabet ranges, and preserve letters from other scripts.
fn foldSlugCodepoint(codepoint: u21) ?u21 {
    if (codepoint <= std.math.maxInt(u8)) {
        const byte: u8 = @intCast(codepoint);
        if (std.ascii.isAlphanumeric(byte)) return std.ascii.toLower(byte);
        if (byte < 0x80) return null;
    }

    return switch (codepoint) {
        0x00AA => 'a',
        0x00B2 => '2',
        0x00B3 => '3',
        0x00B5 => 0x03BC,
        0x00B9 => '1',
        0x00BA => 'o',
        'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'à', 'á', 'â', 'ã', 'ä', 'å' => 'a',
        'Æ', 'Ð', 'Ø', 'Þ' => codepoint + 0x20,
        'Ç', 'ç' => 'c',
        'È', 'É', 'Ê', 'Ë', 'è', 'é', 'ê', 'ë' => 'e',
        'Ì', 'Í', 'Î', 'Ï', 'ì', 'í', 'î', 'ï' => 'i',
        'Ñ', 'ñ' => 'n',
        'Ò', 'Ó', 'Ô', 'Õ', 'Ö', 'ò', 'ó', 'ô', 'õ', 'ö' => 'o',
        'Ù', 'Ú', 'Û', 'Ü', 'ù', 'ú', 'û', 'ü' => 'u',
        'Ý', 'Ÿ', 'ý', 'ÿ' => 'y',
        'Ā', 'Ă', 'Ą', 'ā', 'ă', 'ą' => 'a',
        'Ć', 'Ĉ', 'Ċ', 'Č', 'ć', 'ĉ', 'ċ', 'č' => 'c',
        'Ď', 'ď' => 'd',
        'Ē', 'Ĕ', 'Ė', 'Ę', 'Ě', 'ē', 'ĕ', 'ė', 'ę', 'ě' => 'e',
        'Ĝ', 'Ğ', 'Ġ', 'Ģ', 'ĝ', 'ğ', 'ġ', 'ģ' => 'g',
        'Ĥ', 'ĥ' => 'h',
        'Ĩ', 'Ī', 'Ĭ', 'Į', 'İ', 'ĩ', 'ī', 'ĭ', 'į', 'ı' => 'i',
        'Ĵ', 'ĵ' => 'j',
        'Ķ', 'ķ' => 'k',
        'Ĺ', 'Ļ', 'Ľ', 'ĺ', 'ļ', 'ľ' => 'l',
        'Ń', 'Ņ', 'Ň', 'ń', 'ņ', 'ň' => 'n',
        'Ō', 'Ŏ', 'Ő', 'ō', 'ŏ', 'ő' => 'o',
        'Ŕ', 'Ŗ', 'Ř', 'ŕ', 'ŗ', 'ř' => 'r',
        'Ś', 'Ŝ', 'Ş', 'Š', 'ś', 'ŝ', 'ş', 'š' => 's',
        'Ţ', 'Ť', 'ţ', 'ť' => 't',
        'Ũ', 'Ū', 'Ŭ', 'Ů', 'Ű', 'Ų', 'ũ', 'ū', 'ŭ', 'ů', 'ű', 'ų' => 'u',
        'Ŵ', 'ŵ' => 'w',
        'Ŷ', 'ŷ' => 'y',
        'Ź', 'Ż', 'Ž', 'ź', 'ż', 'ž' => 'z',
        0x0391...0x03A1, 0x03A3...0x03AB, 0x0410...0x042F => codepoint + 0x20,
        0x0400...0x040F => codepoint + 0x50,
        else => codepoint,
    };
}

fn isUnicodeWhitespace(codepoint: u21) bool {
    if (codepoint <= std.math.maxInt(u8) and std.ascii.isWhitespace(@intCast(codepoint))) {
        return true;
    }
    return switch (codepoint) {
        0x00A0,
        0x1680,
        0x2000...0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        0xFEFF,
        => true,
        else => false,
    };
}

fn isCombiningMark(codepoint: u21) bool {
    return switch (codepoint) {
        0x0300...0x036F,
        0x1AB0...0x1AFF,
        0x1DC0...0x1DFF,
        0x20D0...0x20FF,
        0xFE20...0xFE2F,
        => true,
        else => false,
    };
}

fn isUnicodePunctuationOrSymbol(codepoint: u21) bool {
    if (codepoint < 0x80) return !std.ascii.isAlphanumeric(@intCast(codepoint));
    return switch (codepoint) {
        0x00A1...0x00BF,
        0x00D7,
        0x00F7,
        0x200B...0x206F,
        0x20A0...0x20CF,
        0x2100...0x2BFF,
        0x2E00...0x2E7F,
        0x3001...0x3006,
        0x3008...0x303F,
        0xFE10...0xFE1F,
        0xFE30...0xFE6F,
        0xFF01...0xFF0F,
        0xFF1A...0xFF20,
        0xFF3B...0xFF40,
        0xFF5B...0xFF65,
        0x1F000...0x1FAFF,
        => true,
        else => false,
    };
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
            try writer.print("{f}</code></pre>\n", .{markdown.fmtHtml(content)});
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
