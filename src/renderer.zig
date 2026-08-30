const std = @import("std");
const builtin = @import("builtin");
const markdown = @import("markdown");
const math = @import("math_typesetter");
const highlight = @import("highlight.zig");
const unicode_slug = @import("unicode_slug.zig");

const allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.page_allocator;
const Renderer = markdown.Renderer(*const RenderContext);
const max_macro_config_bytes = 1024 * 1024;

pub const MathMacroDefinition = math.MacroDefinition;

pub const RenderOptions = struct {
    escape_raw_html: bool = false,
    safe_urls: bool = false,
    /// Caller-owned definitions compiled once and reused for every math span
    /// in this render operation.
    math_macros: []const MathMacroDefinition = &.{},
};

const RenderContext = struct {
    allocator: std.mem.Allocator,
    headings: *const HeadingIndex,
    options: RenderOptions,
    math_session: ?*const math.MacroSession,
};

var input: []u8 = &.{};
var output: []u8 = &.{};
var macro_config_input: []u8 = &.{};
var configured_math_session: ?math.MacroSession = null;
var last_error: ErrorCode = .none;

const ErrorCode = enum(u32) {
    none = 0,
    out_of_memory = 1,
    parse = 2,
    render = 3,
    invalid_input = 4,
    invalid_math_macros = 5,
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

    output = renderAllocWithMathSession(
        allocator,
        input[0..length],
        .{},
        if (configured_math_session) |*session| session else null,
    ) catch |err| {
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

/// Reserves a bounded binary macro-configuration buffer. A later call
/// invalidates the previous buffer pointer.
export fn allocateMacroConfig(length: u32) u32 {
    releaseMacroConfig();
    last_error = .none;
    if (length > max_macro_config_bytes) {
        last_error = .invalid_math_macros;
        return 0;
    }
    macro_config_input = allocator.alloc(u8, length) catch {
        last_error = .out_of_memory;
        return 0;
    };
    return @intCast(@intFromPtr(macro_config_input.ptr));
}

/// Atomically installs the macro table encoded in the configuration buffer.
/// The format is a little-endian definition count followed by, per definition,
/// name length, replacement length, argument count, name bytes, and replacement
/// bytes. All three per-definition integers are u32 values.
export fn configureMathMacros(length: u32) u32 {
    last_error = .none;
    if (length > macro_config_input.len) {
        last_error = .invalid_math_macros;
        return 0;
    }

    const definitions = parseMacroConfigAlloc(
        allocator,
        macro_config_input[0..length],
    ) catch |err| {
        last_error = switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.InvalidMacroConfig => .invalid_math_macros,
        };
        return 0;
    };
    defer allocator.free(definitions);

    if (definitions.len == 0) {
        clearConfiguredMathSession();
        return 1;
    }

    const candidate = math.MacroSession.init(allocator, definitions, .{}) catch |err| {
        last_error = switch (err) {
            error.OutOfMemory => .out_of_memory,
            else => .invalid_math_macros,
        };
        return 0;
    };
    clearConfiguredMathSession();
    configured_math_session = candidate;
    return 1;
}

export fn releaseMacroConfig() void {
    if (macro_config_input.len != 0) allocator.free(macro_config_input);
    macro_config_input = &.{};
}

export fn clearMathMacros() void {
    last_error = .none;
    clearConfiguredMathSession();
}

fn clearConfiguredMathSession() void {
    if (configured_math_session) |*session| session.deinit();
    configured_math_session = null;
}

const ParseMacroConfigError = error{ OutOfMemory, InvalidMacroConfig };

fn parseMacroConfigAlloc(
    gpa: std.mem.Allocator,
    bytes: []const u8,
) ParseMacroConfigError![]MathMacroDefinition {
    var cursor: usize = 0;
    const definition_count = readMacroConfigU32(bytes, &cursor) orelse
        return error.InvalidMacroConfig;
    if (definition_count > (math.Limits{}).max_macro_definitions) {
        return error.InvalidMacroConfig;
    }

    const definitions = try gpa.alloc(MathMacroDefinition, definition_count);
    errdefer gpa.free(definitions);
    for (definitions) |*definition| {
        const name_length = readMacroConfigU32(bytes, &cursor) orelse
            return error.InvalidMacroConfig;
        const replacement_length = readMacroConfigU32(bytes, &cursor) orelse
            return error.InvalidMacroConfig;
        const argument_count = readMacroConfigU32(bytes, &cursor) orelse
            return error.InvalidMacroConfig;
        if (argument_count > std.math.maxInt(u8)) return error.InvalidMacroConfig;

        if (name_length > bytes.len - cursor) return error.InvalidMacroConfig;
        const name_end = cursor + name_length;
        const name = bytes[cursor..name_end];
        cursor = name_end;

        if (replacement_length > bytes.len - cursor) return error.InvalidMacroConfig;
        const replacement_end = cursor + replacement_length;
        const replacement = bytes[cursor..replacement_end];
        cursor = replacement_end;

        definition.* = .{
            .name = name,
            .replacement = replacement,
            .argument_count = @intCast(argument_count),
        };
    }
    if (cursor != bytes.len) return error.InvalidMacroConfig;
    return definitions;
}

fn readMacroConfigU32(bytes: []const u8, cursor: *usize) ?u32 {
    if (cursor.* > bytes.len or bytes.len - cursor.* < 4) return null;
    const value = @as(u32, bytes[cursor.*]) |
        (@as(u32, bytes[cursor.* + 1]) << 8) |
        (@as(u32, bytes[cursor.* + 2]) << 16) |
        (@as(u32, bytes[cursor.* + 3]) << 24);
    cursor.* += 4;
    return value;
}

pub const RenderError = error{ OutOfMemory, ParseFailed, RenderFailed };

pub fn renderAlloc(gpa: std.mem.Allocator, source: []const u8) RenderError![]u8 {
    return renderAllocOptions(gpa, source, .{});
}

pub fn renderAllocOptions(
    gpa: std.mem.Allocator,
    source: []const u8,
    options: RenderOptions,
) RenderError![]u8 {
    var math_session = if (options.math_macros.len == 0)
        null
    else
        math.MacroSession.init(gpa, options.math_macros, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.RenderFailed,
        };
    defer if (math_session) |*session| session.deinit();

    return renderAllocWithMathSession(
        gpa,
        source,
        options,
        if (math_session) |*session| session else null,
    );
}

fn renderAllocWithMathSession(
    gpa: std.mem.Allocator,
    source: []const u8,
    options: RenderOptions,
    math_session: ?*const math.MacroSession,
) RenderError![]u8 {
    var parser = markdown.Parser.init(gpa) catch return error.OutOfMemory;
    defer parser.deinit();
    parser.feed(source) catch return error.ParseFailed;

    var document = parser.endInput() catch return error.ParseFailed;
    defer document.deinit(gpa);

    var headings = HeadingIndex.init(gpa, document) catch return error.OutOfMemory;
    defer headings.deinit();

    const context: RenderContext = .{
        .allocator = gpa,
        .headings = &headings,
        .options = options,
        .math_session = math_session,
    };

    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    const renderer: Renderer = .{ .context = &context, .renderFn = renderNode };
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
        .code_span, .math_inline, .text => try writer.writeAll(document.string(view.data.text.content)),
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
            const heading = renderer.context.headings.get(node).?;
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
        .math_inline => try renderMath(
            renderer.context,
            document.string(view.data.text.content),
            .inline_math,
            writer,
        ),
        .math_block => {
            try renderMath(
                renderer.context,
                document.string(view.data.text.content),
                .display_math,
                writer,
            );
            try writer.writeByte('\n');
        },
        .html_block, .html_inline => {
            if (!renderer.context.options.escape_raw_html) {
                try renderer.renderDefault(document, node, writer);
                return;
            }
            try writer.print("{f}", .{markdown.fmtHtml(document.string(view.data.text.content))});
            if (view.tag == .html_block) try writer.writeByte('\n');
        },
        .link => {
            if (!renderer.context.options.safe_urls or
                isSafeUrl(document.string(view.data.link.target), true))
            {
                try renderer.renderDefault(document, node, writer);
                return;
            }
            for (document.children(node)) |child| {
                try renderer.renderFn(renderer, document, child, writer);
            }
        },
        .image => {
            if (!renderer.context.options.safe_urls or
                isSafeUrl(document.string(view.data.link.target), false))
            {
                try renderer.renderDefault(document, node, writer);
                return;
            }
            for (document.children(node)) |child| {
                try renderer.renderFn(renderer, document, child, writer);
            }
        },
        else => try renderer.renderDefault(document, node, writer),
    }
}

fn renderMath(
    context: *const RenderContext,
    source: []const u8,
    display_mode: math.DisplayMode,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    var result = if (context.math_session) |session|
        session.renderMathMlAlloc(context.allocator, source, .{
            .display_mode = display_mode,
            .profile = .ams,
        }) catch return renderMathFallback(source, display_mode, writer)
    else
        math.renderMathMlAlloc(context.allocator, source, .{
            .display_mode = display_mode,
            .profile = .ams,
        }) catch return renderMathFallback(source, display_mode, writer);
    defer result.deinit(context.allocator);

    switch (result) {
        .output => |output_html| try writer.writeAll(output_html),
        .diagnostic => try renderMathFallback(source, display_mode, writer),
    }
}

fn renderMathFallback(
    source: []const u8,
    display_mode: math.DisplayMode,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    switch (display_mode) {
        .inline_math => try writer.print("${f}$", .{markdown.fmtHtml(source)}),
        .display_math => try writer.print(
            "<pre><code class=\"language-math\">{f}</code></pre>",
            .{markdown.fmtHtml(source)},
        ),
    }
}

fn isSafeUrl(raw: []const u8, is_link: bool) bool {
    const url = std.mem.trim(u8, raw, " \t\r\n");
    if (url.len == 0 or url[0] == '#' or std.mem.startsWith(u8, url, "//")) return true;

    const boundary = std.mem.indexOfAny(u8, url, "/?#") orelse url.len;
    const colon = std.mem.indexOfScalar(u8, url, ':') orelse {
        const prefix = url[0..boundary];
        if (std.mem.indexOf(u8, prefix, "&#") != null or
            indexOfIgnoreCase(prefix, "&colon;") != null) return false;
        return true;
    };
    if (boundary < colon) return true;
    const scheme = url[0..colon];

    if (std.ascii.eqlIgnoreCase(scheme, "http") or
        std.ascii.eqlIgnoreCase(scheme, "https") or
        std.ascii.eqlIgnoreCase(scheme, "file")) return true;
    if (is_link and (std.ascii.eqlIgnoreCase(scheme, "mailto") or
        std.ascii.eqlIgnoreCase(scheme, "tel"))) return true;
    if (!is_link and std.ascii.eqlIgnoreCase(scheme, "data")) {
        return startsWithIgnoreCase(url[colon + 1 ..], "image/png;") or
            startsWithIgnoreCase(url[colon + 1 ..], "image/gif;") or
            startsWithIgnoreCase(url[colon + 1 ..], "image/jpeg;") or
            startsWithIgnoreCase(url[colon + 1 ..], "image/jpg;") or
            startsWithIgnoreCase(url[colon + 1 ..], "image/webp;");
    }
    return false;
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}

fn indexOfIgnoreCase(value: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (value.len < needle.len) return null;
    for (0..value.len - needle.len + 1) |start| {
        if (std.ascii.eqlIgnoreCase(value[start .. start + needle.len], needle)) return start;
    }
    return null;
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

test "renders inline and display math as safe MathML" {
    const html = try renderAlloc(std.testing.allocator,
        \\Inline $x_1 + \alpha$.
        \\
        \\```math
        \\\frac{x}{\sqrt[3]{y}}
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(
        u8,
        html,
        "<math class=\"zig-math\" display=\"inline\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<msub>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mi>α</mi>") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        html,
        "<math class=\"zig-math\" display=\"block\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mfrac>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mroot>") != null);
}

test "renders AMS matrices cases and aligned equations" {
    const html = try renderAlloc(std.testing.allocator,
        \\```math
        \\\begin{pmatrix}a&b\\c&d\end{pmatrix}
        \\```
        \\
        \\```math
        \\\begin{cases}x&x>0\\-x&x\le0\end{cases}
        \\```
        \\
        \\```math
        \\\begin{aligned}x&=1\\y&=2\end{aligned}
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, html, "<mtable>"));
    try std.testing.expect(std.mem.indexOf(u8, html, "<mo>(</mo>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mo>{</mo><mtable>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mtd columnalign=\"right\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mtd columnalign=\"left\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "language-math") == null);
}

test "renders caller-configured macros across a Markdown document" {
    const macros = [_]MathMacroDefinition{.{
        .name = "f",
        .replacement = "#1f(#2)",
        .argument_count = 2,
    }};
    const source =
        \\# KaTeX macro formula
        \\
        \\~~~math
        \\% \f is defined as #1f(#2) using the macro
        \\\f\relax{x} = \int_{-\infty}^\infty
        \\    \f\hat\xi\,e^{2 \pi i \xi x}
        \\    \,d\xi
        \\~~~
    ;
    const html = try renderAllocOptions(
        std.testing.allocator,
        source,
        .{ .math_macros = &macros },
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(
        u8,
        html,
        "<math class=\"zig-math\" display=\"block\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mover>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<mi>ξ</mi>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "language-math") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "using the macro") == null);

    const fallback = try renderAlloc(std.testing.allocator, source);
    defer std.testing.allocator.free(fallback);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "language-math") != null);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "\\f\\relax{x}") != null);
}

test "math diagnostics fall back to complete escaped source" {
    const inline_html = try renderAlloc(std.testing.allocator, "Broken $\\frac{x}$ here.\n");
    defer std.testing.allocator.free(inline_html);
    try std.testing.expectEqualStrings("<p>Broken $\\frac{x}$ here.</p>\n", inline_html);
    try std.testing.expect(std.mem.indexOf(u8, inline_html, "<math") == null);

    const display = try renderAlloc(std.testing.allocator,
        \\```tex
        \\\text{a<&
        \\```
    );
    defer std.testing.allocator.free(display);
    try std.testing.expectEqualStrings(
        "<pre><code class=\"language-math\">\\text{a&lt;&amp;\n</code></pre>\n",
        display,
    );
    try std.testing.expect(std.mem.indexOf(u8, display, "<math") == null);
}

test "math source contributes to heading anchors" {
    const html = try renderAlloc(std.testing.allocator, "# Energy $E=mc^2$\n");
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "id=\"energy-emc2\"") != null);
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

test "native standalone mode escapes raw HTML and unsafe URLs" {
    const html = try renderAllocOptions(std.testing.allocator,
        \\<script>alert('raw')</script>
        \\
        \\[unsafe](javascript:alert(1))
        \\[encoded unsafe](javascript&colon;alert(1))
        \\![unsafe image](data:text/html,boom)
        \\
        \\[safe](https://ziglang.org/)
    , .{
        .escape_raw_html = true,
        .safe_urls = true,
    });
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;script&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<script>") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "javascript:") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "javascript&colon;") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "data:text/html") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "href=\"https://ziglang.org/\"") != null);
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

test "highlights promoted GDScript Nushell AWK and Typst fences" {
    const html = try renderAlloc(std.testing.allocator,
        \\```gdscript
        \\class_name Player
        \\func move(direction: Vector2):
        \\    return direction.normalized()
        \\```
        \\```nu
        \\def main [input: path] { open $input | lines }
        \\```
        \\```awk
        \\$1 ~ /^[0-9]+$/ { print normalize($1 / 2) }
        \\```
        \\```typst
        \\#let badge(body) = box()[#body]
        \\= Report <report>
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-gdscript\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Player</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-nu\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">input</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-awk\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-string\">/^[0-9]+$/</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-typst\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">&lt;report&gt;</span>") != null);
}

test "highlights promoted Elixir Julia Haskell and Perl fences" {
    const html = try renderAlloc(std.testing.allocator,
        \\```elixir
        \\defmodule Demo.Worker do
        \\  def run(input), do: Regex.match?(~r/foo/, input)
        \\end
        \\```
        \\```julia
        \\module Geometry
        \\function area(circle::Circle)
        \\    @assert circle.radius > 0
        \\end
        \\end
        \\```
        \\```haskell
        \\module Demo.Shapes where
        \\data Shape = Circle Double
        \\area shape = 1
        \\```
        \\```perl
        \\package Demo::Worker;
        \\sub run ($input) { my $pattern = qr/foo/; say $input; }
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-elixir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-julia\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-attribute syntax-macro\">@assert</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-haskell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Circle</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-perl\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-parameter syntax-variable\">$input</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-special syntax-string\">qr</span>") != null);
}

test "highlights promoted OCaml and F# fences" {
    const html = try renderAlloc(std.testing.allocator,
        \\```ocaml
        \\module Geometry = struct
        \\  type shape = Circle of float
        \\  let area radius = radius *. radius
        \\end
        \\```
        \\```fsharp
        \\namespace Demo.Geometry
        \\type Shape = Circle of radius: float
        \\let area shape = shape
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-ocaml\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Geometry</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">area</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-fsharp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Geometry</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">radius</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">shape</span>") != null);
}

test "highlights promoted Gleam structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```gleam
        \\import gleam/result
        \\import gleam/string as text
        \\pub fn render(person: Person) -> String {
        \\  let Person(name, enabled) = person
        \\  use suffix <- result.try(Ok("!"))
        \\  let updated = Person(..person, enabled: False)
        \\  <<name:utf8>> |> text.append(suffix)
        \\}
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-gleam\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">result</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">text</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">suffix</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">enabled</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-attribute\">utf8</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">append</span>") != null);
}

test "highlights promoted D structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```d
        \\module demo.render;
        \\struct Item {
        \\  string name;
        \\  int total(int delta) { return delta; }
        \\}
        \\Item make_item(string name) { return Item(name); }
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">total</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">delta</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Item</span>") != null);
}

test "highlights promoted V structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```v
        \\module main
        \\import time
        \\struct Item { value string }
        \\fn (item Item) total(delta int) int { return item.value.len + delta }
        \\fn make_item(name string) Item { return Item{ value: name } }
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-v\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">main</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">time</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">value</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">total</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">delta</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Item</span>") != null);
}

test "highlights promoted Odin structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```odin
        \\package main
        \\Item :: struct { value: string }
        \\total :: proc(item: Item, delta: int) -> int { return item.value.len + delta }
        \\make_item :: proc(name: string) -> Item { return Item{value = name} }
        \\answer :: 42
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-odin\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">main</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">value</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">total</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">delta</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">answer</span>") != null);
}

test "highlights promoted C3 structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```c3
        \\module demo::render;
        \\import std::io;
        \\struct Item { String value; int count; }
        \\fn int total(Item item, int delta) { return item.count + delta; }
        \\fn Item make_item(String name) { io::printfn(name); return { .value = name }; }
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-c3\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">value</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">total</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">delta</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">printfn</span>") != null);
}

test "highlights promoted Elm structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```elm
        \\module Demo.Profile exposing (Profile, Status(..), render)
        \\import Html as H
        \\type alias Profile = { name : String, enabled : Bool }
        \\type Status = Ready | Failed String
        \\render : Profile -> String
        \\render profile = H.text profile.name
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-elm\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Profile</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Profile</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Ready</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">profile</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">H</span>") != null);
}

test "highlights promoted PureScript structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```purescript
        \\module Demo.Profile where
        \\import Data.Maybe as M
        \\type Profile = { name :: String, enabled :: Boolean }
        \\data Status = Ready | Failed String
        \\newtype User = User { name :: String }
        \\render :: Profile -> String
        \\render profile = M.fromMaybe "unknown" (Just profile.name)
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-purescript\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Profile</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Ready</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">User</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">profile</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">M</span>") != null);
}

test "highlights promoted SystemVerilog structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```systemverilog
        \\`define DEFAULT_WIDTH 8
        \\package demo_pkg;
        \\  typedef enum logic [1:0] { IDLE, RUN } state_t;
        \\endpackage
        \\module demo #(parameter int WIDTH = `DEFAULT_WIDTH) (input logic clk);
        \\  import demo_pkg::*;
        \\  state_t state;
        \\  function int add(input int lhs, input int rhs); return lhs + rhs; endfunction
        \\  assign ready = state.valid;
        \\  initial $display("ready", ready);
        \\endmodule
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-systemverilog\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">`define</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">demo_pkg</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">WIDTH</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">clk</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">state_t</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">add</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">valid</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">$display</span>") != null);
}

test "highlights promoted Common Lisp structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```commonlisp
        \\(defpackage demo (:use :cl))
        \\(defclass person () ((name :initarg :name)))
        \\(defun greet (person &optional prefix) (format nil "~a" person))
        \\(defmacro withperson ((name value) &body body) `(let ((,name ,value)) ,@body))
        \\(let ((message "ready")) (greet message))
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-commonlisp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">greet</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">withperson</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">message</span>") != null);
}

test "highlights promoted Scheme structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```scheme
        \\(define-library (demo core)
        \\  (import (scheme base))
        \\  (begin
        \\    (define-record-type person (makeperson name) person? (name personname))
        \\    (define (greet person) (let ((message "ready")) message))
        \\    (define-syntax whenready (syntax-rules () ((_ body) body)))))
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-scheme\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">greet</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">message</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">whenready</span>") != null);
}

test "highlights promoted Nim structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```nim
        \\import std/strformat
        \\type
        \\  Person* = object
        \\    name*: string
        \\const Limit* = 42
        \\proc render*(person: Person, prefix: string): string {.inline.} = prefix & person.name
        \\proc makePerson(name: string): Person = Person(name: name)
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-nim\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">std</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">Limit</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">person</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">Person</span>") != null);
}

test "highlights verified Assembly and NASM lexical roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```asm
        \\.macro save reg
        \\  push \\reg
        \\.endm
        \\.globl start
        \\start:
        \\  mov $42, %rax
        \\  call render
        \\```
        \\```nasm
        \\%define COUNT 42
        \\section .text
        \\global start
        \\start:
        \\  mov rax, COUNT
        \\  jmp .done
        \\.done:
        \\  ret
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-asm\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">.macro</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">%rax</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-nasm\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">%define</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">COUNT</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">.done</span>") != null);
}

test "highlights promoted OpenSCAD structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```openscad
        \\module rounded_box(size = [1, 2, 3], radius = 1) {
        \\  translate([0, 0, radius]) cube(size = size, center = true);
        \\}
        \\function doubled(value) = value * 2;
        \\steps = [for (item = [0:2]) doubled(item)];
        \\let (offset = 2) rounded_box(radius = offset);
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-openscad\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">rounded_box</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">size</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">cube</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">center</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">doubled</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">offset</span>") != null);
}

test "highlights promoted Hare structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```hare
        \\use fmt;
        \\type coords = struct { x: int, y: int };
        \\def DEFAULT_LIMIT: size = 5;
        \\fn translate(point: coords, dx: int) coords = {
        \\  return coords { x = point.x + dx, y = point.y };
        \\};
        \\export fn main() void = {
        \\  const origin = coords { x = 1, y = 2 };
        \\  fmt::printfln("{}", translate(origin, DEFAULT_LIMIT))!;
        \\};
        \\```
    );
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-hare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">fmt</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">coords</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">x</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">DEFAULT_LIMIT</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">translate</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">point</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">coords</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">origin</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">printfln</span>") != null);
}

test "highlights promoted Nickel structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```nickel
        \\let make_item = fun name enabled => {
        \\  name | String = name,
        \\  nested.count = 42,
        \\  message = "hello %{name}",
        \\} in let item = make_item "demo" true in item.name
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-nickel\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">make_item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">count</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-embedded syntax-string\">%{name}</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">item</span>") != null);
}

test "highlights promoted Agda structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```agda
        \\module Demo.Core where
        \\open import Data.Nat
        \\data Item : Set where
        \\  item : Item
        \\record Point : Set where
        \\  field
        \\    x : Set
        \\select : Item → Item
        \\select value = value
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-agda\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Demo</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Core</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Data</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Nat</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constructor\">item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">x</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">select</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">value</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "→") != null);
}

test "highlights promoted Vimscript structural roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```vim
        \\vim9script
        \\import autoload './util.vim' as util
        \\def Render(name: string): string
        \\  const message = util.Format(name)
        \\  return message
        \\enddef
        \\function! s:Legacy(value)
        \\  let l:item = a:value
        \\  return s:Render(l:item)
        \\endfunction
        \\command! -nargs=1 Show call s:Render(<args>)
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-vim\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">util</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">Render</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">name</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">message</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">Format</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">Legacy</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">item</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">Show</span>") != null);
}

test "highlights promoted Uxntal lexical roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```uxntal
        \\|0100
        \\%emit-byte ( value -- ) { #18 DEO }
        \\@main
        \\  &loop
        \\  #2a #01 ADD2k
        \\  ,&loop JCN
        \\  ;Screen/width DEI2
        \\  "hello
        \\  BRK
        \\( outer ( nested ) comment )
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-uxntal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-number\">|0100</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">%emit-byte</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">@main</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-keyword\">ADD2k</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">;Screen/width</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-string\">&quot;hello</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-comment\">( outer ( nested ) comment )</span>") != null);
}

test "highlights verified comment-tag roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```comment
        \\TODO(alice): preserve source for #123
        \\NOTE: see https://example.test/docs
        \\FIXME: escape <unsafe>& bytes
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-comment\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-special\">TODO</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">alice</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-number\">#123</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-markup-link") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "https://example.test/docs") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;unsafe&gt;&amp;") != null);
}

test "highlights verified DTD declaration roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```dtd
        \\<!ELEMENT note (to,from,heading,body)>
        \\<!ATTLIST note id ID #REQUIRED status (draft|final) "draft">
        \\<!ENTITY % shared "INCLUDE">
        \\%shared;
        \\<!ENTITY writer "Oleg &amp; Co.">
        \\<!NOTATION gif SYSTEM "image/gif">
        \\<![IGNORE[ <!ELEMENT ignored ANY> ]]>
        \\<!-- comment -->
        \\<?audit source?>
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-dtd\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-keyword\">ELEMENT</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-tag\">note</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-attribute\">id</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">ID</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-constant\">draft</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-escape") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-comment\">&lt;![</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-comment syntax-keyword\">IGNORE</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-special\">&lt;?audit source?&gt;</span>") != null);
}

test "highlights structural CMake roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```cmake
        \\#[=[ structural example ]=]
        \\function(build_target source)
        \\  set(NAME "$ENV{HOME}")
        \\  add_executable(app ${source})
        \\  set_property(TARGET app PROPERTY CXX_STANDARD 23)
        \\  target_compile_definitions(app PRIVATE "$<$<CONFIG:Debug>:DEBUG_BUILD>")
        \\endfunction()
        \\macro(enable_warnings target)
        \\endmacro()
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-cmake\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">build_target</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">source</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-macro\">enable_warnings</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-variable\">NAME</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-variable\">$ENV{HOME}</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">app</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">CXX_STANDARD</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-embedded") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-comment\">#[=[ structural example ]=]</span>") != null);
}

test "highlights Fortran free and fixed form lexical syntax" {
    const html = try renderAlloc(std.testing.allocator,
        \\```fortran
        \\C fixed-form comment
        \\  100 CONTINUE
        \\     1 VALUE = Z'2A' + 1.25_real64
        \\name = 'don''t'
        \\if (.TRUE. .and. VALUE >= 0) VALUE = VALUE &
        \\  & + 1
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"language-fortran\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-comment\">C fixed-form comment</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-label\">100</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-number\">Z&#39;2A&#39;</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-number\">1.25_real64</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "syntax-escape syntax-string\">&#39;&#39;</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-boolean\">.TRUE.</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-operator\">.and.</span>") != null);
}

test "highlights structural Fortran roles" {
    const html = try renderAlloc(std.testing.allocator,
        \\```fortran
        \\module Geometry
        \\  use, intrinsic :: iso_fortran_env
        \\  type, extends(shape) :: Circle
        \\    real :: radius
        \\  contains
        \\    procedure :: area => circle_area
        \\  end type Circle
        \\contains
        \\  pure function circle_area(self, scale) result(total)
        \\    type(Circle), intent(in) :: self
        \\    total = self%radius * scale
        \\    call report(total)
        \\  end function circle_area
        \\end module Geometry
        \\```
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">Geometry</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-namespace\">iso_fortran_env</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">shape</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-type\">Circle</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">radius</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-property\">area</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">circle_area</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">self</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-parameter\">scale</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"syntax-function\">report</span>") != null);
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
