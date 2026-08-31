const std = @import("std");

const max_file_size = 1024 * 1024;
const max_component = 65535;

const Pattern = struct {
    prefix: []const u8,
    suffix: []const u8,
};

const FileSpec = struct {
    path: []const u8,
    patterns: []const Pattern,
};

const files = [_]FileSpec{
    .{
        .path = "build.zig.zon",
        .patterns = &.{.{ .prefix = "    .version = \"", .suffix = "\"," }},
    },
    .{
        .path = "build.zig",
        .patterns = &.{.{ .prefix = "const release_version = \"", .suffix = "\";" }},
    },
    .{
        .path = "extension/manifest.json",
        .patterns = &.{.{ .prefix = "  \"version\": \"", .suffix = "\"," }},
    },
    .{
        .path = "README.md",
        .patterns = &.{.{ .prefix = "`zig-out/dist/zig-markdown-viewer-", .suffix = ".zip`" }},
    },
    .{
        .path = "docs/CHROME_WEB_STORE.md",
        .patterns = &.{.{ .prefix = "canonical copy and disclosures for the `", .suffix = "`" }},
    },
    .{
        .path = "docs/RELEASING.md",
        .patterns = &.{
            .{ .prefix = "unzip -t zig-out/dist/zig-markdown-viewer-", .suffix = ".zip" },
            .{ .prefix = "sha256sum zig-out/dist/zig-markdown-viewer-", .suffix = ".zip" },
        },
    },
};

const LoadedFile = struct {
    spec: *const FileSpec,
    contents: []u8,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return usage(init);

    var loaded: [files.len]LoadedFile = undefined;
    var loaded_count: usize = 0;
    defer for (loaded[0..loaded_count]) |file| init.gpa.free(file.contents);

    for (&files, 0..) |*spec, index| {
        const contents = std.Io.Dir.cwd().readFileAlloc(
            init.io,
            spec.path,
            init.gpa,
            .limited(max_file_size),
        ) catch |err| return fatal(
            init,
            "cannot read '{s}': {s}",
            .{ spec.path, @errorName(err) },
        );
        loaded[index] = .{ .spec = spec, .contents = contents };
        loaded_count += 1;
    }

    const current = synchronizedVersion(&loaded) catch |err| return fatal(
        init,
        "cannot determine a synchronized package version: {s}",
        .{@errorName(err)},
    );

    if (std.mem.eql(u8, args[1], "get")) {
        if (args.len != 2) return usage(init);
        return printVersion(init, "{s}\n", .{current});
    }
    if (!std.mem.eql(u8, args[1], "set") or args.len != 3) return usage(init);

    const next = args[2];
    validateVersion(next) catch return fatal(
        init,
        "invalid version '{s}': expected canonical MAJOR.MINOR.PATCH with components from 0 to {d}",
        .{ next, max_component },
    );
    if (std.mem.eql(u8, current, next)) {
        return printVersion(init, "package version is already {s}\n", .{current});
    }

    var replacements: [files.len][]u8 = undefined;
    var replacement_count: usize = 0;
    defer for (replacements[0..replacement_count]) |contents| init.gpa.free(contents);

    for (loaded[0..loaded_count], 0..) |file, index| {
        var updated = try init.gpa.dupe(u8, file.contents);
        errdefer init.gpa.free(updated);
        for (file.spec.patterns) |pattern| {
            const replacement = replaceVersion(init.gpa, updated, pattern, current, next) catch |err| {
                init.gpa.free(updated);
                return fatal(
                    init,
                    "cannot update '{s}': {s}",
                    .{ file.spec.path, @errorName(err) },
                );
            };
            init.gpa.free(updated);
            updated = replacement;
        }
        replacements[index] = updated;
        replacement_count += 1;
    }

    var written: usize = 0;
    while (written < loaded_count) : (written += 1) {
        writeAtomic(init, loaded[written].spec.path, replacements[written]) catch |err| {
            rollback(init, loaded[0..written]) catch |rollback_err| return fatal(
                init,
                "cannot update '{s}': {s}; rollback also failed: {s}",
                .{ loaded[written].spec.path, @errorName(err), @errorName(rollback_err) },
            );
            return fatal(
                init,
                "cannot update '{s}': {s}; earlier writes were rolled back",
                .{ loaded[written].spec.path, @errorName(err) },
            );
        };
    }

    return printVersion(init, "package version: {s} -> {s}\n", .{ current, next });
}

fn synchronizedVersion(loaded: []const LoadedFile) ![]const u8 {
    var current: ?[]const u8 = null;
    for (loaded) |file| {
        for (file.spec.patterns) |pattern| {
            const found = try extractVersion(file.contents, pattern);
            try validateVersion(found);
            if (current) |expected| {
                if (!std.mem.eql(u8, expected, found)) return error.InconsistentVersion;
            } else {
                current = found;
            }
        }
    }
    return current orelse error.MissingVersion;
}

fn extractVersion(contents: []const u8, pattern: Pattern) ![]const u8 {
    const prefix_index = std.mem.indexOf(u8, contents, pattern.prefix) orelse
        return error.MissingVersion;
    const value_start = prefix_index + pattern.prefix.len;
    const suffix_offset = std.mem.indexOf(u8, contents[value_start..], pattern.suffix) orelse
        return error.MissingVersion;
    if (std.mem.indexOf(u8, contents[value_start..], pattern.prefix) != null)
        return error.DuplicateVersionMarker;
    const value = contents[value_start .. value_start + suffix_offset];
    if (value.len == 0) return error.InvalidVersion;
    return value;
}

fn validateVersion(text: []const u8) !void {
    const parsed = std.SemanticVersion.parse(text) catch return error.InvalidVersion;
    if (parsed.pre != null or parsed.build != null or
        parsed.major > max_component or parsed.minor > max_component or parsed.patch > max_component)
        return error.InvalidVersion;

    var canonical_buffer: [32]u8 = undefined;
    const canonical = std.fmt.bufPrint(
        &canonical_buffer,
        "{d}.{d}.{d}",
        .{ parsed.major, parsed.minor, parsed.patch },
    ) catch return error.InvalidVersion;
    if (!std.mem.eql(u8, canonical, text)) return error.InvalidVersion;
}

fn replaceVersion(
    allocator: std.mem.Allocator,
    contents: []const u8,
    pattern: Pattern,
    expected: []const u8,
    replacement: []const u8,
) ![]u8 {
    const found = try extractVersion(contents, pattern);
    if (!std.mem.eql(u8, found, expected)) return error.InconsistentVersion;
    const value_start = @intFromPtr(found.ptr) - @intFromPtr(contents.ptr);
    const new_len = std.math.sub(usize, contents.len, found.len) catch return error.FileTooLarge;
    const final_len = std.math.add(usize, new_len, replacement.len) catch return error.FileTooLarge;
    const updated = try allocator.alloc(u8, final_len);
    @memcpy(updated[0..value_start], contents[0..value_start]);
    @memcpy(updated[value_start .. value_start + replacement.len], replacement);
    @memcpy(
        updated[value_start + replacement.len ..],
        contents[value_start + found.len ..],
    );
    return updated;
}

fn writeAtomic(init: std.process.Init, path: []const u8, contents: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const permissions = permissions: {
        const original = try cwd.openFile(init.io, path, .{});
        defer original.close(init.io);
        break :permissions (try original.stat(init.io)).permissions;
    };

    var atomic = try cwd.createFileAtomic(init.io, path, .{
        .permissions = permissions,
        .replace = true,
    });
    defer atomic.deinit(init.io);
    try atomic.file.writeStreamingAll(init.io, contents);
    try atomic.replace(init.io);
}

fn rollback(init: std.process.Init, written: []const LoadedFile) !void {
    var index = written.len;
    while (index > 0) {
        index -= 1;
        try writeAtomic(init, written[index].spec.path, written[index].contents);
    }
}

fn printVersion(init: std.process.Init, comptime format: []const u8, args: anytype) !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print(format, args);
    try stdout_writer.interface.flush();
}

fn usage(init: std.process.Init) noreturn {
    fatal(
        init,
        "usage: package-version get\n       package-version set MAJOR.MINOR.PATCH",
        .{},
    );
}

fn fatal(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("package-version: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

test "accepts only canonical Chrome-compatible release versions" {
    try validateVersion("0.3.1");
    try validateVersion("65535.0.42");
    try std.testing.expectError(error.InvalidVersion, validateVersion("1.2"));
    try std.testing.expectError(error.InvalidVersion, validateVersion("01.2.3"));
    try std.testing.expectError(error.InvalidVersion, validateVersion("1.2.3-beta.1"));
    try std.testing.expectError(error.InvalidVersion, validateVersion("1.2.65536"));
}

test "extracts and replaces one marked version" {
    const pattern: Pattern = .{ .prefix = "version = \"", .suffix = "\";" };
    const source = "const version = \"0.3.1\";\n";
    try std.testing.expectEqualStrings("0.3.1", try extractVersion(source, pattern));

    const updated = try replaceVersion(std.testing.allocator, source, pattern, "0.3.1", "0.4.0");
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("const version = \"0.4.0\";\n", updated);
}

test "rejects missing duplicate and inconsistent version markers" {
    const pattern: Pattern = .{ .prefix = "version = \"", .suffix = "\";" };
    try std.testing.expectError(error.MissingVersion, extractVersion("name = \"viewer\";", pattern));
    try std.testing.expectError(
        error.DuplicateVersionMarker,
        extractVersion("version = \"1.0.0\"; version = \"1.0.0\";", pattern),
    );
    try std.testing.expectError(
        error.InconsistentVersion,
        replaceVersion(std.testing.allocator, "version = \"1.0.0\";", pattern, "1.0.1", "1.0.2"),
    );
}
