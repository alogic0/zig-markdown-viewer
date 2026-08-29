const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return usage(init);

    if (std.mem.eql(u8, args[1], "--write")) {
        const actual = fileSize(init, args[2]) catch |err| {
            return fail(init, "cannot inspect '{s}': {s}", .{ args[2], @errorName(err) });
        };
        var stdout_buffer: [64]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        try stdout_writer.interface.print("{d}\n", .{actual});
        try stdout_writer.interface.flush();
        return;
    }

    const actual = fileSize(init, args[1]) catch |err| {
        return fail(init, "cannot inspect '{s}': {s}", .{ args[1], @errorName(err) });
    };
    const baseline_text = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[2],
        init.gpa,
        .limited(128),
    ) catch |err| {
        return fail(init, "cannot read baseline '{s}': {s}", .{ args[2], @errorName(err) });
    };
    defer init.gpa.free(baseline_text);
    const baseline = parseBaseline(baseline_text) catch |err| {
        return fail(init, "invalid baseline '{s}': {s}", .{ args[2], @errorName(err) });
    };

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try writeReport(&stdout_writer.interface, actual, baseline);
    try stdout_writer.interface.flush();

    if (actual != baseline) {
        const delta = difference(actual, baseline);
        return fail(
            init,
            "renderer Wasm differs from its checked-in baseline by {s}{d} bytes; review './build.sh wasm-size-report', then run './build.sh update-wasm-size-baseline' for an intentional change",
            .{ sign(delta), delta },
        );
    }
}

fn fileSize(init: std.process.Init, path: []const u8) !u64 {
    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer file.close(init.io);
    return (try file.stat(init.io)).size;
}

fn parseBaseline(text: []const u8) std.fmt.ParseIntError!u64 {
    return std.fmt.parseInt(u64, std.mem.trim(u8, text, " \t\r\n"), 10);
}

fn difference(actual: u64, baseline: u64) i128 {
    return @as(i128, actual) - @as(i128, baseline);
}

fn sign(delta: i128) []const u8 {
    return if (delta >= 0) "+" else "";
}

fn writeReport(writer: *std.Io.Writer, actual: u64, baseline: u64) std.Io.Writer.Error!void {
    const delta = difference(actual, baseline);
    try writer.print(
        "renderer Wasm: {d} bytes (baseline {d}, change {s}{d} bytes)\n",
        .{ actual, baseline, sign(delta), delta },
    );
}

fn usage(init: std.process.Init) noreturn {
    failWithCode(init, 2, "usage: check-wasm-size PATH BASELINE_FILE\n       check-wasm-size --write PATH", .{});
}

fn fail(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    failWithCode(init, 1, format, args);
}

fn failWithCode(init: std.process.Init, code: u8, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [512]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("check-wasm-size: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(code);
}

test "size report shows matching baseline" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeReport(&output.writer, 632145, 632145);

    try std.testing.expectEqualStrings(
        "renderer Wasm: 632145 bytes (baseline 632145, change +0 bytes)\n",
        output.written(),
    );
}

test "size report shows signed growth" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeReport(&output.writer, 632177, 632145);

    try std.testing.expectEqualStrings(
        "renderer Wasm: 632177 bytes (baseline 632145, change +32 bytes)\n",
        output.written(),
    );
}

test "size report shows signed shrinkage" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeReport(&output.writer, 632000, 632145);

    try std.testing.expectEqualStrings(
        "renderer Wasm: 632000 bytes (baseline 632145, change -145 bytes)\n",
        output.written(),
    );
}

test "baseline accepts surrounding whitespace" {
    try std.testing.expectEqual(@as(u64, 632145), try parseBaseline(" 632145\n"));
}
