const std = @import("std");

const typesetter_path = "../zig-math-typesetter";
const typesetter_remote = "git+https://github.com/alogic0/zig-math-typesetter.git";
const max_command_output = 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return fatal(init, "usage: pin-math-dependency ZIG_EXE", .{});
    const zig_exe = args[1];

    const status = runChecked(init, &.{
        "git", "-C", typesetter_path, "status", "--porcelain",
    }, "inspect the typesetter worktree");
    defer init.gpa.free(status);
    if (std.mem.trim(u8, status, " \t\r\n").len != 0) {
        return fatal(
            init,
            "{s} has uncommitted changes; commit them before pinning",
            .{typesetter_path},
        );
    }

    const revision_output = runChecked(init, &.{
        "git", "-C", typesetter_path, "rev-parse", "HEAD",
    }, "read the typesetter revision");
    defer init.gpa.free(revision_output);
    const revision = std.mem.trim(u8, revision_output, " \t\r\n");
    if (!isFullRevision(revision)) {
        return fatal(init, "git returned an invalid typesetter revision: '{s}'", .{revision});
    }

    const remote_refs = runChecked(init, &.{
        "git", "-C", typesetter_path, "ls-remote", "--heads", "--tags", "origin",
    }, "read origin refs");
    defer init.gpa.free(remote_refs);
    if (!remoteContainsRevision(remote_refs, revision)) {
        return fatal(
            init,
            "typesetter commit {s} is not on an origin branch or tag; push it first",
            .{revision},
        );
    }

    const url = try std.fmt.allocPrint(init.gpa, "{s}#{s}", .{ typesetter_remote, revision });
    defer init.gpa.free(url);
    const fetch_output = runChecked(init, &.{
        zig_exe,
        "fetch",
        "--save-exact=math_typesetter",
        url,
    }, "pin the typesetter dependency");
    defer init.gpa.free(fetch_output);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print(
        "pinned math_typesetter to {s}\n",
        .{revision},
    );
    try stdout_writer.interface.flush();
}

fn runChecked(
    init: std.process.Init,
    argv: []const []const u8,
    operation: []const u8,
) []u8 {
    const result = std.process.run(init.gpa, init.io, .{
        .argv = argv,
        .stdout_limit = .limited(max_command_output),
        .stderr_limit = .limited(max_command_output),
    }) catch |err| return fatal(
        init,
        "cannot {s}: {s}",
        .{ operation, @errorName(err) },
    );
    if (!result.term.success()) {
        return fatal(
            init,
            "cannot {s}: {s}",
            .{ operation, std.mem.trim(u8, result.stderr, " \t\r\n") },
        );
    }
    init.gpa.free(result.stderr);
    return result.stdout;
}

fn isFullRevision(revision: []const u8) bool {
    if (revision.len != 40) return false;
    for (revision) |byte| if (!std.ascii.isHex(byte)) return false;
    return true;
}

fn remoteContainsRevision(refs: []const u8, revision: []const u8) bool {
    var lines = std.mem.splitScalar(u8, refs, '\n');
    while (lines.next()) |line| {
        if (line.len > revision.len and
            line[revision.len] == '\t' and
            std.mem.eql(u8, line[0..revision.len], revision)) return true;
    }
    return false;
}

fn fatal(init: std.process.Init, comptime format: []const u8, args: anytype) noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    stderr_writer.interface.print("pin-math: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

test "accepts only full hexadecimal revisions" {
    try std.testing.expect(isFullRevision("ed998db1283da18498581d1e6efa6307cb88ac91"));
    try std.testing.expect(!isFullRevision("ed998db"));
    try std.testing.expect(!isFullRevision("gd998db1283da18498581d1e6efa6307cb88ac91"));
}

test "finds revisions only at the start of complete remote ref lines" {
    const revision = "ed998db1283da18498581d1e6efa6307cb88ac91";
    const refs =
        "1111111111111111111111111111111111111111\trefs/heads/old\n" ++
        revision ++ "\trefs/heads/main\n";
    try std.testing.expect(remoteContainsRevision(refs, revision));
    try std.testing.expect(!remoteContainsRevision(refs, "2222222222222222222222222222222222222222"));
    try std.testing.expect(!remoteContainsRevision(revision, revision));
}
