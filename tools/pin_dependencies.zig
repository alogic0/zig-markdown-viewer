const std = @import("std");

const Dependency = struct {
    key: []const u8,
    path: []const u8,
    remote: []const u8,
};

const dependencies = [_]Dependency{
    .{
        .key = "markdown_parser",
        .path = "../zig-markdown-parser",
        .remote = "git+https://github.com/alogic0/zig-markdown-parser.git",
    },
    .{
        .key = "math_typesetter",
        .path = "../zig-math-typesetter",
        .remote = "git+https://github.com/alogic0/zig-math-typesetter.git",
    },
    .{
        .key = "native_syntax",
        .path = "../zig-native-syntax",
        .remote = "git+https://github.com/alogic0/zig-native-syntax.git",
    },
};

const max_command_output = 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return fatal(init, "usage: pin-dependencies ZIG_EXE", .{});
    const zig_exe = args[1];

    var revisions: [dependencies.len][]u8 = undefined;
    var revision_count: usize = 0;
    defer for (revisions[0..revision_count]) |revision| init.gpa.free(revision);

    for (dependencies, 0..) |dependency, index| {
        revisions[index] = preflightDependency(init, dependency);
        revision_count += 1;
    }

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    for (dependencies, revisions) |dependency, revision| {
        const url = std.fmt.allocPrint(
            init.gpa,
            "{s}#{s}",
            .{ dependency.remote, revision },
        ) catch |err| return fatal(
            init,
            "cannot create the {s} dependency URL: {s}",
            .{ dependency.key, @errorName(err) },
        );
        defer init.gpa.free(url);

        const save_exact = std.fmt.allocPrint(
            init.gpa,
            "--save-exact={s}",
            .{dependency.key},
        ) catch |err| return fatal(
            init,
            "cannot create the {s} fetch option: {s}",
            .{ dependency.key, @errorName(err) },
        );
        defer init.gpa.free(save_exact);

        const fetch_output = runChecked(init, &.{
            zig_exe,
            "fetch",
            save_exact,
            url,
        }, "pin a dependency");
        defer init.gpa.free(fetch_output);

        try stdout_writer.interface.print(
            "pinned {s} to {s}\n",
            .{ dependency.key, revision },
        );
    }
    try stdout_writer.interface.flush();
}

fn preflightDependency(init: std.process.Init, dependency: Dependency) []u8 {
    const status = runChecked(init, &.{
        "git", "-C", dependency.path, "status", "--porcelain",
    }, "inspect a dependency worktree");
    defer init.gpa.free(status);
    if (std.mem.trim(u8, status, " \t\r\n").len != 0) {
        return fatal(
            init,
            "{s} has uncommitted changes; commit them before pinning",
            .{dependency.path},
        );
    }

    const revision_output = runChecked(init, &.{
        "git", "-C", dependency.path, "rev-parse", "HEAD",
    }, "read a dependency revision");
    defer init.gpa.free(revision_output);
    const revision = std.mem.trim(u8, revision_output, " \t\r\n");
    if (!isFullRevision(revision)) {
        return fatal(
            init,
            "git returned an invalid revision for {s}: '{s}'",
            .{ dependency.path, revision },
        );
    }

    const remote_refs = runChecked(init, &.{
        "git", "-C", dependency.path, "ls-remote", "--heads", "--tags", "origin",
    }, "read dependency origin refs");
    defer init.gpa.free(remote_refs);
    if (!remoteContainsRevision(remote_refs, revision)) {
        return fatal(
            init,
            "{s} commit {s} is not on an origin branch or tag; push it first",
            .{ dependency.path, revision },
        );
    }

    return init.gpa.dupe(u8, revision) catch |err| fatal(
        init,
        "cannot retain the {s} revision: {s}",
        .{ dependency.key, @errorName(err) },
    );
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
    stderr_writer.interface.print("pin-deps: " ++ format ++ "\n", args) catch {};
    stderr_writer.interface.flush() catch {};
    std.process.exit(1);
}

test "defines every local viewer dependency" {
    try std.testing.expectEqual(@as(usize, 3), dependencies.len);
    try std.testing.expectEqualStrings("markdown_parser", dependencies[0].key);
    try std.testing.expectEqualStrings("../zig-markdown-parser", dependencies[0].path);
    try std.testing.expectEqualStrings("math_typesetter", dependencies[1].key);
    try std.testing.expectEqualStrings("../zig-math-typesetter", dependencies[1].path);
    try std.testing.expectEqualStrings("native_syntax", dependencies[2].key);
    try std.testing.expectEqualStrings("../zig-native-syntax", dependencies[2].path);
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
