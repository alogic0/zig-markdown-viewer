const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return usage(init);

    const maximum = std.fmt.parseInt(u64, args[2], 10) catch return usage(init);
    const file = std.Io.Dir.cwd().openFile(init.io, args[1], .{}) catch |err| {
        return fail(init, "cannot open '{s}': {s}", .{ args[1], @errorName(err) });
    };
    defer file.close(init.io);
    const actual = (try file.stat(init.io)).size;

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print("renderer Wasm: {d} bytes (budget {d})\n", .{ actual, maximum });
    try stdout_writer.interface.flush();

    if (actual > maximum) {
        return fail(init, "renderer Wasm exceeds its budget by {d} bytes", .{actual - maximum});
    }
}

fn usage(init: std.process.Init) noreturn {
    failWithCode(init, 2, "usage: check-wasm-size PATH MAX_BYTES", .{});
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
