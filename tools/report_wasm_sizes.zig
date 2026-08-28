const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2 or (args.len - 2) % 2 != 0) return usage(init);

    const baseline = try fileSize(init, args[1]);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print("release-small renderer: {d} bytes\n", .{baseline});
    try stdout_writer.interface.writeAll("backend\tmarginal bytes\twithout backend\n");

    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        const excluded_size = try fileSize(init, args[index + 1]);
        const marginal: i128 = @as(i128, baseline) - @as(i128, excluded_size);
        try stdout_writer.interface.print("{s}\t{d}\t{d}\n", .{ args[index], marginal, excluded_size });
    }
    try stdout_writer.interface.flush();
}

fn fileSize(init: std.process.Init, path: []const u8) !u64 {
    const file = std.Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| {
        return fail(init, "cannot open '{s}': {s}", .{ path, @errorName(err) });
    };
    defer file.close(init.io);
    return (try file.stat(init.io)).size;
}

fn usage(init: std.process.Init) noreturn {
    failWithCode(init, 2, "usage: report-wasm-sizes BASELINE [BACKEND EXCLUDED_WASM]...", .{});
}

fn fail(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    failWithCode(init, 1, format, args);
}

fn failWithCode(init: std.process.Init, code: u8, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [512]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("report-wasm-sizes: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(code);
}
