const std = @import("std");
const renderer = @import("renderer_core");
const viewer_assets = @import("viewer_assets");

const max_input_size = 256 * 1024 * 1024;
const content_css = viewer_assets.content_css;
const math_css = viewer_assets.math_css;
const math_font = viewer_assets.math_font;
const font_url = "chrome-extension://__MSG_@@extension_id__/css/fonts/ZigMathSTIX.woff2";

const Theme = enum { auto, light, dark };

const Options = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    theme: Theme = .auto,
    centered: bool = true,
    toc_visible: bool = true,
    code_wrap: bool = false,
};

const Command = union(enum) {
    help,
    render: Options,
};

const ArgumentError = error{
    MissingInput,
    MissingOptionValue,
    MultipleInputs,
    MultipleOutputs,
    InvalidTheme,
    UnknownOption,
};

const page_script =
    \\(() => {
    \\  'use strict';
    \\  const root = document.documentElement;
    \\  const shell = document.querySelector('#zig-md-shell');
    \\  const tocToggle = document.querySelector('[data-action="toc"]');
    \\  const themeToggle = document.querySelector('[data-action="theme"]');
    \\  const mobileToc = matchMedia('(max-width: 680px)');
    \\  function updateTocToggle() {
    \\    const visible = shell?.classList.contains('has-toc') || false;
    \\    tocToggle?.setAttribute('aria-pressed', String(visible));
    \\  }
    \\  tocToggle?.addEventListener('click', () => {
    \\    shell?.classList.toggle('has-toc');
    \\    updateTocToggle();
    \\  });
    \\  function closeMobileToc() {
    \\    if (!mobileToc.matches) return;
    \\    shell?.classList.remove('has-toc');
    \\    updateTocToggle();
    \\  }
    \\  function updateThemeToggle() {
    \\    const setting = root.dataset.zigMarkdownTheme;
    \\    const dark = setting === 'dark' ||
    \\      (setting === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    \\    themeToggle?.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
    \\    themeToggle?.setAttribute('title', dark ? 'Switch to light theme' : 'Switch to dark theme');
    \\  }
    \\  themeToggle?.addEventListener('click', () => {
    \\    const setting = root.dataset.zigMarkdownTheme;
    \\    const dark = setting === 'dark' ||
    \\      (setting === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    \\    root.dataset.zigMarkdownTheme = dark ? 'light' : 'dark';
    \\    updateThemeToggle();
    \\  });
    \\  function copyText(text) {
    \\    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text);
    \\    const textarea = document.createElement('textarea');
    \\    textarea.value = text;
    \\    textarea.style.position = 'fixed';
    \\    textarea.style.opacity = '0';
    \\    document.body.append(textarea);
    \\    textarea.select();
    \\    document.execCommand('copy');
    \\    textarea.remove();
    \\    return Promise.resolve();
    \\  }
    \\  document.querySelectorAll('.zig-md-copy').forEach(button => {
    \\    const code = button.parentElement?.querySelector('code');
    \\    button.addEventListener('click', async () => {
    \\      await copyText(code?.textContent || '');
    \\      button.textContent = 'Copied';
    \\      setTimeout(() => { button.textContent = 'Copy'; }, 1200);
    \\    });
    \\  });
    \\  const scrollTop = document.querySelector('#zig-md-scroll-top');
    \\  scrollTop?.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
    \\  const entries = [...document.querySelectorAll('#zig-md-toc nav a')]
    \\    .map(link => ({ link, heading: document.getElementById(decodeURIComponent(link.hash.slice(1))) }))
    \\    .filter(entry => entry.heading);
    \\  for (const entry of entries) entry.link.addEventListener('click', closeMobileToc);
    \\  let scrollFrame = null;
    \\  function updateScrollState() {
    \\    scrollTop?.classList.toggle('is-visible', scrollY > 500);
    \\    if (entries.length === 0) return;
    \\    let active = entries[0];
    \\    const atBottom = scrollY > 0 && innerHeight + scrollY >= document.documentElement.scrollHeight - 2;
    \\    if (atBottom) {
    \\      active = entries[entries.length - 1];
    \\    } else {
    \\      for (const entry of entries) {
    \\        if (entry.heading.getBoundingClientRect().top > 96) break;
    \\        active = entry;
    \\      }
    \\    }
    \\    for (const entry of entries) {
    \\      const isActive = entry === active;
    \\      entry.link.classList.toggle('is-active', isActive);
    \\      if (isActive) entry.link.setAttribute('aria-current', 'location');
    \\      else entry.link.removeAttribute('aria-current');
    \\    }
    \\  }
    \\  window.addEventListener('scroll', () => {
    \\    if (scrollFrame !== null) return;
    \\    scrollFrame = requestAnimationFrame(() => {
    \\      scrollFrame = null;
    \\      updateScrollState();
    \\    });
    \\  }, { passive: true });
    \\  mobileToc.addEventListener('change', closeMobileToc);
    \\  closeMobileToc();
    \\  updateTocToggle();
    \\  updateThemeToggle();
    \\  updateScrollState();
    \\})();
;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const command = parseArgs(args[1..]) catch |err| {
        var stderr_buffer: [2048]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        try stderr.print("zig-md-render: {s}\n\n", .{argumentErrorMessage(err)});
        try writeUsage(stderr);
        try stderr.flush();
        std.process.exit(2);
    };

    if (command == .help) {
        var stdout_buffer: [2048]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        try writeUsage(&stdout_writer.interface);
        try stdout_writer.interface.flush();
        return;
    }

    const options = command.render;
    const owned_output = if (options.output_path == null)
        try defaultOutputPath(init.gpa, options.input_path)
    else
        null;
    defer if (owned_output) |path| init.gpa.free(path);
    const output_path = options.output_path orelse owned_output.?;
    if (std.mem.eql(u8, options.input_path, output_path) or
        pathsReferToSameFile(init.io, init.gpa, options.input_path, output_path))
    {
        return fatal(init, "input and output paths must differ: '{s}'", .{output_path});
    }

    const source = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        options.input_path,
        init.gpa,
        .limited(max_input_size),
    ) catch |err| return fatal(init, "cannot read '{s}': {s}", .{
        options.input_path,
        @errorName(err),
    });
    defer init.gpa.free(source);

    const document_html = renderer.renderAllocOptions(init.gpa, source, .{
        .escape_raw_html = true,
        .safe_urls = true,
    }) catch |err| return fatal(init, "cannot render '{s}': {s}", .{
        options.input_path,
        @errorName(err),
    });
    defer init.gpa.free(document_html);

    const html = try buildStandaloneAlloc(
        init.gpa,
        std.Io.Dir.path.basename(options.input_path),
        document_html,
        options,
    );
    defer init.gpa.free(html);

    var output = std.Io.Dir.cwd().createFile(init.io, output_path, .{}) catch |err| {
        return fatal(init, "cannot create '{s}': {s}", .{ output_path, @errorName(err) });
    };
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, html);

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print("Rendered {s} -> {s}\n", .{
        options.input_path,
        output_path,
    });
    try stdout_writer.interface.flush();
}

fn fatal(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [2048]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("zig-md-render: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

fn parseArgs(args: []const [:0]const u8) ArgumentError!Command {
    var options: Options = .{ .input_path = "" };
    var positional_only = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg: []const u8 = args[index];
        if (!positional_only and std.mem.eql(u8, arg, "--")) {
            positional_only = true;
        } else if (!positional_only and
            (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")))
        {
            return .help;
        } else if (!positional_only and
            (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")))
        {
            if (options.output_path != null) return error.MultipleOutputs;
            index += 1;
            if (index == args.len) return error.MissingOptionValue;
            options.output_path = args[index];
        } else if (!positional_only and std.mem.eql(u8, arg, "--theme")) {
            index += 1;
            if (index == args.len) return error.MissingOptionValue;
            options.theme = std.meta.stringToEnum(Theme, args[index]) orelse
                return error.InvalidTheme;
        } else if (!positional_only and std.mem.eql(u8, arg, "--wide")) {
            options.centered = false;
        } else if (!positional_only and std.mem.eql(u8, arg, "--wrap")) {
            options.code_wrap = true;
        } else if (!positional_only and std.mem.eql(u8, arg, "--no-toc")) {
            options.toc_visible = false;
        } else if (!positional_only and std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else if (options.input_path.len != 0) {
            return error.MultipleInputs;
        } else {
            options.input_path = arg;
        }
    }
    if (options.input_path.len == 0) return error.MissingInput;
    return .{ .render = options };
}

fn argumentErrorMessage(err: ArgumentError) []const u8 {
    return switch (err) {
        error.MissingInput => "missing Markdown input path",
        error.MissingOptionValue => "missing option value",
        error.MultipleInputs => "expected one Markdown input path",
        error.MultipleOutputs => "output path specified more than once",
        error.InvalidTheme => "theme must be auto, light, or dark",
        error.UnknownOption => "unknown option",
    };
}

fn writeUsage(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(
        \\Usage: zig-md-render [options] <input.md>
        \\
        \\Render Markdown to a self-contained HTML document using the native Zig renderer.
        \\
        \\Argument:
        \\  <input.md>                 Markdown source to render. Supported filename
        \\                             extensions include .md, .markdown, .mkd, and .mdx.
        \\
        \\Options:
        \\  -o, --output <path>        Write HTML to this path. Without this option,
        \\                             the input extension is replaced with .html.
        \\                             An existing output file is replaced only after
        \\                             Markdown rendering succeeds. The input itself
        \\                             is never accepted as the output path.
        \\
        \\      --theme <name>         Select the initial color theme:
        \\                               auto   follow the browser or OS preference
        \\                               light  start with the light palette
        \\                               dark   start with the dark palette
        \\                             The generated page still includes its theme
        \\                             switch. Default: auto.
        \\
        \\      --wide                 Remove the centered 960px content limit and
        \\                             use the available browser width.
        \\
        \\      --wrap                 Wrap long fenced-code lines instead of giving
        \\                             each code block a horizontal scrollbar.
        \\
        \\      --no-toc               Start with Contents hidden. The generated page
        \\                             still includes the Contents toggle.
        \\
        \\  -h, --help                 Print this option reference and exit successfully.
        \\
        \\Output behavior:
        \\  The result is one portable HTML file containing CSS, JavaScript, syntax
        \\  highlighting, Contents, theme, copy, and scroll controls. Raw HTML is
        \\  escaped, and unsafe link and image URL schemes are removed.
        \\
        \\Examples:
        \\  ./build.sh render-html -- input.md -o output.html
        \\  zig-out/bin/zig-md-render --theme dark --wide README.md
        \\
    );
}

fn defaultOutputPath(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const extension = std.Io.Dir.path.extension(input);
    const stem = if (std.ascii.eqlIgnoreCase(extension, ".md") or
        std.ascii.eqlIgnoreCase(extension, ".markdown") or
        std.ascii.eqlIgnoreCase(extension, ".mkd") or
        std.ascii.eqlIgnoreCase(extension, ".mdx"))
        input[0 .. input.len - extension.len]
    else
        input;
    return std.fmt.allocPrint(allocator, "{s}.html", .{stem});
}

fn pathsReferToSameFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
) bool {
    const input_real = std.Io.Dir.cwd().realPathFileAlloc(io, input_path, allocator) catch
        return false;
    defer allocator.free(input_real);
    const output_real = std.Io.Dir.cwd().realPathFileAlloc(io, output_path, allocator) catch
        return false;
    defer allocator.free(output_real);
    return std.mem.eql(u8, input_real, output_real);
}

fn buildStandaloneAlloc(
    allocator: std.mem.Allocator,
    title: []const u8,
    document_html: []const u8,
    options: Options,
) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();
    const out = &writer.writer;

    try out.writeAll("<!doctype html>\n<html lang=\"en\" data-zig-markdown-theme=\"");
    try out.writeAll(@tagName(options.theme));
    try out.writeAll("\">\n<head>\n  <meta charset=\"utf-8\">\n");
    try out.writeAll("  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>");
    try writeHtmlEscaped(out, title);
    try out.writeAll("</title>\n  <style>\n");
    try out.writeAll(content_css);
    if (std.mem.indexOf(u8, document_html, "zig-math-composite") != null) {
        try out.writeByte('\n');
        try writeStandaloneMathCss(out);
    }
    try out.writeAll("\n  </style>\n</head>\n<body class=\"zig-md-page\">\n  <div id=\"zig-md-shell\" class=\"");
    var wrote_class = false;
    if (options.centered) {
        try out.writeAll("is-centered");
        wrote_class = true;
    }
    if (options.toc_visible) {
        if (wrote_class) try out.writeByte(' ');
        try out.writeAll("has-toc");
        wrote_class = true;
    }
    if (options.code_wrap) {
        if (wrote_class) try out.writeByte(' ');
        try out.writeAll("code-wrap");
    }
    try out.writeAll("\" style=\"--zig-md-width:960px;--zig-md-font-size:16px;--zig-md-line-height:1.65\">\n");
    try out.writeAll("    <aside id=\"zig-md-toc\" aria-label=\"Table of contents\">\n      <div class=\"zig-md-toc-heading\">On this page</div>\n      <nav>");
    try writeToc(document_html, out);
    try out.writeAll("</nav>\n    </aside>\n    <div id=\"zig-md-main\">\n");
    try out.writeAll("      <header id=\"zig-md-toolbar\" aria-label=\"Document tools\">\n        <div class=\"zig-md-actions\">\n");
    try out.writeAll("          <button type=\"button\" data-action=\"toc\" title=\"Toggle table of contents\" aria-label=\"Toggle table of contents\"><svg viewBox=\"0 0 24 24\" aria-hidden=\"true\"><path d=\"M4 6h16M4 12h16M4 18h16\"/></svg></button>\n");
    try out.writeAll("          <button type=\"button\" data-action=\"theme\" title=\"Switch color theme\" aria-label=\"Switch color theme\"><svg viewBox=\"0 0 24 24\" aria-hidden=\"true\"><path d=\"M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9Z\"/></svg></button>\n");
    try out.writeAll("        </div>\n      </header>\n      <main id=\"zig-md-document\">");
    try writeEnhancedCodeBlocks(document_html, out);
    try out.writeAll("</main>\n      <button id=\"zig-md-scroll-top\" type=\"button\" aria-label=\"Scroll to top\">↑</button>\n    </div>\n  </div>\n  <script>\n");
    try out.writeAll(page_script);
    try out.writeAll("\n  </script>\n</body>\n</html>\n");
    return writer.toOwnedSlice();
}

fn writeStandaloneMathCss(out: *std.Io.Writer) std.Io.Writer.Error!void {
    const start = std.mem.indexOf(u8, math_css, font_url) orelse unreachable;
    try out.writeAll(math_css[0..start]);
    try out.writeAll("data:font/woff2;base64,");
    try out.printBase64(math_font);
    try out.writeAll(math_css[start + font_url.len ..]);
}

fn writeEnhancedCodeBlocks(html: []const u8, writer: *std.Io.Writer) !void {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, html, cursor, "<pre")) |start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, start, '>') orelse break;
        const close_start = std.mem.indexOfPos(u8, html, tag_end + 1, "</code></pre>") orelse break;
        const end = close_start + "</code></pre>".len;
        try writer.writeAll(html[cursor..start]);
        try writer.writeAll("<div class=\"zig-md-code-block\">");
        try writer.writeAll(html[start..end]);

        const pre_tag = html[start .. tag_end + 1];
        if (attributeValue(pre_tag, "data-language")) |language| {
            try writer.writeAll("<span class=\"zig-md-language\">");
            try writer.writeAll(language);
            try writer.writeAll("</span>");
        }
        try writer.writeAll("<button type=\"button\" class=\"zig-md-copy\">Copy</button></div>");
        cursor = end;
    }
    try writer.writeAll(html[cursor..]);
}

fn writeToc(html: []const u8, writer: *std.Io.Writer) !void {
    var cursor: usize = 0;
    var found = false;
    while (std.mem.indexOfPos(u8, html, cursor, "<h")) |start| {
        cursor = start + 2;
        if (cursor + 1 >= html.len) break;
        const level = html[cursor];
        if (level < '1' or level > '3' or html[cursor + 1] != ' ') continue;
        const tag_end = std.mem.indexOfScalarPos(u8, html, cursor, '>') orelse break;
        const heading_end_marker = switch (level) {
            '1' => "</h1>",
            '2' => "</h2>",
            else => "</h3>",
        };
        const heading_end = std.mem.indexOfPos(u8, html, tag_end + 1, heading_end_marker) orelse break;
        const heading_html = html[start..heading_end];
        const href = attributeValue(heading_html, "href") orelse continue;
        const aria_label = attributeValue(heading_html, "aria-label") orelse continue;
        const label_prefix = "Link to ";
        if (!std.mem.startsWith(u8, aria_label, label_prefix)) continue;

        try writer.writeAll("<a href=\"");
        try writer.writeAll(href);
        try writer.writeAll("\" class=\"level-");
        try writer.writeByte(level);
        try writer.writeAll("\">");
        try writer.writeAll(aria_label[label_prefix.len..]);
        try writer.writeAll("</a>");
        found = true;
        cursor = heading_end + heading_end_marker.len;
    }
    if (!found) try writer.writeAll("<p class=\"zig-md-toc-empty\">No headings</p>");
}

fn attributeValue(tag: []const u8, name: []const u8) ?[]const u8 {
    var marker_buffer: [64]u8 = undefined;
    if (name.len + 2 > marker_buffer.len) return null;
    @memcpy(marker_buffer[0..name.len], name);
    marker_buffer[name.len] = '=';
    marker_buffer[name.len + 1] = '"';
    const marker = marker_buffer[0 .. name.len + 2];
    const marker_start = std.mem.indexOf(u8, tag, marker) orelse return null;
    const value_start = marker_start + marker.len;
    const value_end = std.mem.indexOfScalarPos(u8, tag, value_start, '"') orelse return null;
    return tag[value_start..value_end];
}

fn writeHtmlEscaped(writer: *std.Io.Writer, value: []const u8) !void {
    var cursor: usize = 0;
    for (value, 0..) |byte, index| {
        const replacement: ?[]const u8 = switch (byte) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&#39;",
            else => null,
        };
        if (replacement) |escaped| {
            try writer.writeAll(value[cursor..index]);
            try writer.writeAll(escaped);
            cursor = index + 1;
        }
    }
    try writer.writeAll(value[cursor..]);
}

test "arguments select native standalone options" {
    const command = try parseArgs(&.{
        "--theme",
        "dark",
        "--wide",
        "--wrap",
        "--no-toc",
        "input.md",
        "-o",
        "output.html",
    });
    const options = command.render;
    try std.testing.expectEqualStrings("input.md", options.input_path);
    try std.testing.expectEqualStrings("output.html", options.output_path.?);
    try std.testing.expectEqual(Theme.dark, options.theme);
    try std.testing.expect(!options.centered);
    try std.testing.expect(!options.toc_visible);
    try std.testing.expect(options.code_wrap);
}

test "help option documents every rendering option" {
    const command = try parseArgs(&.{"--help"});
    try std.testing.expect(command == .help);

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    const usage_writer = &writer.writer;
    try writeUsage(usage_writer);
    const usage = try writer.toOwnedSlice();
    defer std.testing.allocator.free(usage);

    const documented_options: []const []const u8 = &.{
        "--output",
        "--theme",
        "--wide",
        "--wrap",
        "--no-toc",
        "--help",
    };
    for (documented_options) |option| {
        try std.testing.expect(std.mem.indexOf(u8, usage, option) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, usage, "auto   follow") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "input itself") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "one portable HTML file") != null);
}

test "default output replaces Markdown extensions" {
    const output = try defaultOutputPath(std.testing.allocator, "/tmp/example.markdown");
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("/tmp/example.html", output);
}

test "standalone output contains navigation and enhanced code" {
    const document_html =
        "<h2 id=\"example\"><a class=\"zig-md-heading-anchor\" href=\"#example\" " ++
        "aria-label=\"Link to Example\">#</a>Example</h2>\n" ++
        "<pre data-language=\"zig\"><code class=\"language-zig\">const x = 1;</code></pre>\n";
    const html = try buildStandaloneAlloc(std.testing.allocator, "Example.md", document_html, .{
        .input_path = "Example.md",
    });
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.startsWith(u8, html, "<!doctype html>"));
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"level-2\">Example</a>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"zig-md-language\">zig</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"zig-md-copy\">Copy</button>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "--zig-md-syntax-comment: #545454") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "data:font/woff2") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, font_url) == null);
}

test "standalone visual math embeds its font" {
    const html = try buildStandaloneAlloc(
        std.testing.allocator,
        "Math.md",
        "<span class=\"zig-math-composite\"></span>",
        .{ .input_path = "Math.md" },
    );
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "data:font/woff2;base64,d09GMg") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, font_url) == null);
}
