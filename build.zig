const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const markdown = b.dependency("markdown_parser", .{
        .target = wasm_target,
        .optimize = optimize,
    }).module("markdown");

    const renderer = b.addExecutable(.{
        .name = "renderer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/renderer.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .single_threaded = true,
            .strip = optimize != .debug,
            .imports = &.{.{ .name = "markdown", .module = markdown }},
        }),
    });
    renderer.rdynamic = true;
    renderer.entry = .disabled;

    b.installDirectory(.{
        .source_dir = b.path("extension"),
        .install_dir = .prefix,
        .install_subdir = "extension",
    });
    b.getInstallStep().dependOn(&b.addInstallFile(
        renderer.getEmittedBin(),
        "extension/renderer.wasm",
    ).step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/renderer.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{.{
                .name = "markdown",
                .module = b.dependency("markdown_parser", .{
                    .target = b.graph.host,
                    .optimize = .debug,
                }).module("markdown"),
            }},
        }),
    });
    const test_step = b.step("test", "Run renderer tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const unicode_generator = b.addExecutable(.{
        .name = "generate-unicode-slug-data",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_unicode_slug_data.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_unicode_generator = b.addRunArtifact(unicode_generator);
    run_unicode_generator.setCwd(b.path("."));
    const unicode_step = b.step("generate-unicode", "Regenerate focused Unicode slug tables");
    unicode_step.dependOn(&run_unicode_generator.step);
}
