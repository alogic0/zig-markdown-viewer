const std = @import("std");

const max_asset_size = 64 * 1024 * 1024;
const utf8_flag: u16 = 1 << 11;
const dos_epoch_date: u16 = 0x0021;

const InputFile = struct {
    name: []const u8,
    data: []const u8,
    local_header_offset: u32 = 0,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return fatal(
        init,
        "usage: package-extension VERSION EXTENSION_DIR RENDERER_WASM OUTPUT_ZIP",
        .{},
    );

    var files: std.ArrayList(InputFile) = .empty;
    defer {
        for (files.items) |file| {
            init.gpa.free(file.name);
            init.gpa.free(file.data);
        }
        files.deinit(init.gpa);
    }

    collectExtensionFiles(init, &files, args[2]) catch |err| {
        return fatal(init, "cannot collect extension assets: {s}", .{@errorName(err)});
    };
    appendFile(init, &files, "renderer.wasm", args[3]) catch |err| {
        return fatal(init, "cannot read renderer Wasm: {s}", .{@errorName(err)});
    };
    std.mem.sort(InputFile, files.items, {}, lessThanName);

    validateFiles(init.gpa, files.items, args[1]) catch |err| {
        return fatal(init, "invalid extension package: {s}", .{@errorName(err)});
    };
    const archive = buildArchive(init.gpa, files.items) catch |err| {
        return fatal(init, "cannot build extension archive: {s}", .{@errorName(err)});
    };
    defer init.gpa.free(archive);

    var output = std.Io.Dir.cwd().createFile(init.io, args[4], .{}) catch |err| {
        return fatal(init, "cannot create '{s}': {s}", .{ args[4], @errorName(err) });
    };
    defer output.close(init.io);
    output.writeStreamingAll(init.io, archive) catch |err| {
        return fatal(init, "cannot write '{s}': {s}", .{ args[4], @errorName(err) });
    };
}

fn collectExtensionFiles(
    init: std.process.Init,
    files: *std.ArrayList(InputFile),
    root_path: []const u8,
) !void {
    var root = try std.Io.Dir.cwd().openDir(init.io, root_path, .{ .iterate = true });
    defer root.close(init.io);
    var walker = try root.walk(init.gpa);
    defer walker.deinit();

    while (try walker.next(init.io)) |entry| switch (entry.kind) {
        .directory => {},
        .file => {
            const disk_path = try std.fs.path.join(init.gpa, &.{ root_path, entry.path });
            defer init.gpa.free(disk_path);
            const archive_name = try normalizeArchiveName(init.gpa, entry.path);
            errdefer init.gpa.free(archive_name);
            if (std.mem.eql(u8, archive_name, "renderer.wasm")) return error.DuplicateRenderer;
            const data = try std.Io.Dir.cwd().readFileAlloc(
                init.io,
                disk_path,
                init.gpa,
                .limited(max_asset_size),
            );
            errdefer init.gpa.free(data);
            try files.append(init.gpa, .{ .name = archive_name, .data = data });
        },
        else => return error.UnsupportedFileType,
    };
}

fn appendFile(
    init: std.process.Init,
    files: *std.ArrayList(InputFile),
    archive_name: []const u8,
    disk_path: []const u8,
) !void {
    const name = try init.gpa.dupe(u8, archive_name);
    errdefer init.gpa.free(name);
    const data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        disk_path,
        init.gpa,
        .limited(max_asset_size),
    );
    errdefer init.gpa.free(data);
    try files.append(init.gpa, .{ .name = name, .data = data });
}

fn normalizeArchiveName(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return error.UnsafeArchivePath;
    const normalized = try allocator.dupe(u8, path);
    errdefer allocator.free(normalized);
    for (normalized) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    var components = std.mem.splitScalar(u8, normalized, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, "..")) return error.UnsafeArchivePath;
    }
    return normalized;
}

fn lessThanName(_: void, lhs: InputFile, rhs: InputFile) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn validateFiles(allocator: std.mem.Allocator, files: []const InputFile, version: []const u8) !void {
    if (files.len == 0 or files.len > std.math.maxInt(u16)) return error.InvalidFileCount;
    var manifest: ?[]const u8 = null;
    var has_renderer = false;
    for (files, 0..) |file, index| {
        if (file.name.len == 0 or file.name.len > std.math.maxInt(u16)) return error.InvalidFileName;
        if (file.data.len > std.math.maxInt(u32)) return error.FileTooLarge;
        if (index > 0 and std.mem.eql(u8, files[index - 1].name, file.name)) return error.DuplicateFile;
        if (std.mem.eql(u8, file.name, "manifest.json")) manifest = file.data;
        if (std.mem.eql(u8, file.name, "renderer.wasm")) has_renderer = true;
    }
    if (manifest == null) return error.MissingManifest;
    if (!has_renderer) return error.MissingRenderer;

    const Manifest = struct { version: []const u8 };
    var parsed = std.json.parseFromSlice(
        Manifest,
        allocator,
        manifest.?,
        .{ .ignore_unknown_fields = true },
    ) catch return error.InvalidManifest;
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.version, version)) return error.VersionMismatch;
}

fn buildArchive(allocator: std.mem.Allocator, files: []InputFile) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;

    for (files) |*file| {
        file.local_header_offset = std.math.cast(u32, output.written().len) orelse
            return error.ArchiveTooLarge;
        const size = std.math.cast(u32, file.data.len) orelse return error.FileTooLarge;
        const name_len = std.math.cast(u16, file.name.len) orelse return error.InvalidFileName;
        try writer.writeInt(u32, 0x04034b50, .little);
        try writer.writeInt(u16, 20, .little);
        try writer.writeInt(u16, utf8_flag, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, dos_epoch_date, .little);
        try writer.writeInt(u32, std.hash.Crc32.hash(file.data), .little);
        try writer.writeInt(u32, size, .little);
        try writer.writeInt(u32, size, .little);
        try writer.writeInt(u16, name_len, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeAll(file.name);
        try writer.writeAll(file.data);
    }

    const central_offset = std.math.cast(u32, output.written().len) orelse
        return error.ArchiveTooLarge;
    for (files) |file| {
        const size = std.math.cast(u32, file.data.len) orelse return error.FileTooLarge;
        const name_len = std.math.cast(u16, file.name.len) orelse return error.InvalidFileName;
        try writer.writeInt(u32, 0x02014b50, .little);
        try writer.writeInt(u16, 20, .little);
        try writer.writeInt(u16, 20, .little);
        try writer.writeInt(u16, utf8_flag, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, dos_epoch_date, .little);
        try writer.writeInt(u32, std.hash.Crc32.hash(file.data), .little);
        try writer.writeInt(u32, size, .little);
        try writer.writeInt(u32, size, .little);
        try writer.writeInt(u16, name_len, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u16, 0, .little);
        try writer.writeInt(u32, 0, .little);
        try writer.writeInt(u32, file.local_header_offset, .little);
        try writer.writeAll(file.name);
    }
    const central_size = std.math.cast(u32, output.written().len - central_offset) orelse
        return error.ArchiveTooLarge;
    const file_count = std.math.cast(u16, files.len) orelse return error.InvalidFileCount;
    try writer.writeInt(u32, 0x06054b50, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u16, file_count, .little);
    try writer.writeInt(u16, file_count, .little);
    try writer.writeInt(u32, central_size, .little);
    try writer.writeInt(u32, central_offset, .little);
    try writer.writeInt(u16, 0, .little);
    return output.toOwnedSlice();
}

fn fatal(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("package-extension: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

test "builds deterministic ZIP archives with manifest at the root" {
    var files = [_]InputFile{
        .{ .name = "manifest.json", .data = "{\"version\":\"0.2.0\"}" },
        .{ .name = "renderer.wasm", .data = "\x00asm" },
    };
    try validateFiles(std.testing.allocator, &files, "0.2.0");
    const first = try buildArchive(std.testing.allocator, &files);
    defer std.testing.allocator.free(first);
    const second = try buildArchive(std.testing.allocator, &files);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expectEqualSlices(u8, "PK\x03\x04", first[0..4]);
    try std.testing.expect(std.mem.indexOf(u8, first, "manifest.json") != null);
    try std.testing.expectEqualSlices(u8, "PK\x05\x06", first[first.len - 22 ..][0..4]);
}

test "rejects manifest version mismatches" {
    const files = [_]InputFile{
        .{ .name = "manifest.json", .data = "{\"version\":\"0.1.0\"}" },
        .{ .name = "renderer.wasm", .data = "\x00asm" },
    };
    try std.testing.expectError(
        error.VersionMismatch,
        validateFiles(std.testing.allocator, &files, "0.2.0"),
    );
}

test "rejects unsafe archive paths" {
    try std.testing.expectError(
        error.UnsafeArchivePath,
        normalizeArchiveName(std.testing.allocator, "../manifest.json"),
    );
}
