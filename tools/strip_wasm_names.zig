const std = @import("std");

const Error = error{
    InvalidHeader,
    InvalidSection,
    IntegerOverflow,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return fatal(init, "usage: strip-wasm-names INPUT OUTPUT", .{});

    const input = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        init.gpa,
        .limited(64 * 1024 * 1024),
    ) catch |err| return fatal(init, "cannot read '{s}': {s}", .{ args[1], @errorName(err) });
    defer init.gpa.free(input);

    const output = stripNameSection(init.gpa, input) catch |err| {
        return fatal(init, "cannot process '{s}': {s}", .{ args[1], @errorName(err) });
    };
    defer init.gpa.free(output);

    var file = std.Io.Dir.cwd().createFile(init.io, args[2], .{}) catch |err| {
        return fatal(init, "cannot create '{s}': {s}", .{ args[2], @errorName(err) });
    };
    defer file.close(init.io);
    file.writeStreamingAll(init.io, output) catch |err| {
        return fatal(init, "cannot write '{s}': {s}", .{ args[2], @errorName(err) });
    };
}

fn stripNameSection(allocator: std.mem.Allocator, input: []const u8) (Error || std.Io.Writer.Error || std.mem.Allocator.Error)![]u8 {
    if (input.len < 8 or !std.mem.eql(u8, input[0..8], "\x00asm\x01\x00\x00\x00")) {
        return error.InvalidHeader;
    }

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try output.writer.writeAll(input[0..8]);

    var cursor: usize = 8;
    while (cursor < input.len) {
        const section_start = cursor;
        cursor += 1;
        const size = try readUleb(input, &cursor);
        const section_end = std.math.add(usize, cursor, size) catch return error.InvalidSection;
        if (section_end > input.len) return error.InvalidSection;

        const remove = input[section_start] == 0 and try isNameSection(input[cursor..section_end]);
        if (!remove) try output.writer.writeAll(input[section_start..section_end]);
        cursor = section_end;
    }
    return output.toOwnedSlice();
}

fn isNameSection(payload: []const u8) Error!bool {
    var cursor: usize = 0;
    const name_len = try readUleb(payload, &cursor);
    const name_end = std.math.add(usize, cursor, name_len) catch return error.InvalidSection;
    if (name_end > payload.len) return error.InvalidSection;
    return std.mem.eql(u8, payload[cursor..name_end], "name");
}

fn readUleb(bytes: []const u8, cursor: *usize) Error!usize {
    var value: u64 = 0;
    var shift: std.math.Log2Int(u64) = 0;
    while (cursor.* < bytes.len) {
        const byte = bytes[cursor.*];
        cursor.* += 1;
        const payload = byte & 0x7f;
        if (shift == 63 and payload > 1) return error.IntegerOverflow;
        value |= @as(u64, payload) << shift;
        if (byte & 0x80 == 0) return std.math.cast(usize, value) orelse error.IntegerOverflow;
        if (shift > 56) return error.IntegerOverflow;
        shift += 7;
    }
    return error.InvalidSection;
}

fn fatal(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [512]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("strip-wasm-names: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

test "removes only the name custom section" {
    const input =
        "\x00asm\x01\x00\x00\x00" ++
        "\x00\x05\x04name" ++
        "\x00\x0a\x09producers" ++
        "\x01\x01\x00";
    const expected =
        "\x00asm\x01\x00\x00\x00" ++
        "\x00\x0a\x09producers" ++
        "\x01\x01\x00";
    const output = try stripNameSection(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualSlices(u8, expected, output);
}

test "rejects malformed modules" {
    try std.testing.expectError(error.InvalidHeader, stripNameSection(std.testing.allocator, "not wasm"));
    try std.testing.expectError(
        error.InvalidSection,
        stripNameSection(std.testing.allocator, "\x00asm\x01\x00\x00\x00\x00\x05\x04na"),
    );
}
