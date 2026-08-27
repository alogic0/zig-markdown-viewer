const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const renderer = addWasmRenderer(b, "renderer", wasm_target, optimize);
    const checked_renderer = if (optimize == .small)
        renderer
    else
        addWasmRenderer(b, "renderer", wasm_target, .small);

    b.installDirectory(.{
        .source_dir = b.path("extension"),
        .install_dir = .prefix,
        .install_subdir = "extension",
    });
    const install_renderer = b.addInstallFile(
        renderer.getEmittedBin(),
        "extension/renderer.wasm",
    );
    b.getInstallStep().dependOn(&install_renderer.step);

    const size_checker = b.addExecutable(.{
        .name = "check-wasm-size",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_wasm_size.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_size_checker = b.addRunArtifact(size_checker);
    run_size_checker.addFileArg(checked_renderer.getEmittedBin());
    run_size_checker.addArg("575000");
    const size_step = b.step("check-wasm-size", "Enforce the release-small renderer Wasm size budget");
    size_step.dependOn(&run_size_checker.step);

    const renderer_core = rendererCoreModule(b, b.graph.host, optimize);
    const assets = b.addOptions();
    var css_file = b.root.openFile(
        b.graph.io,
        "extension/css/content.css",
        .{ .mode = .read_only },
    ) catch @panic("unable to open extension/css/content.css");
    defer css_file.close(b.graph.io);
    var css_reader = css_file.reader(b.graph.io, &.{});
    const content_css = css_reader.interface.allocRemaining(
        b.allocator,
        .limited(1024 * 1024),
    ) catch @panic("unable to read extension/css/content.css");
    assets.addOption([]const u8, "content_css", content_css);
    const assets_module = assets.createModule();
    const render_html_root = b.createModule(.{
        .root_source_file = b.path("tools/render_html.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "renderer_core", .module = renderer_core },
            .{ .name = "viewer_assets", .module = assets_module },
        },
    });
    const render_html = b.addExecutable(.{
        .name = "zig-md-render",
        .root_module = render_html_root,
    });
    b.installArtifact(render_html);

    const run_render_html = b.addRunArtifact(render_html);
    run_render_html.addPassthruArgs();
    const render_html_step = b.step("render-html", "Render Markdown as standalone HTML");
    render_html_step.dependOn(&run_render_html.step);

    const tests = b.addTest(.{ .root_module = rendererCoreModule(b, b.graph.host, .debug) });
    const test_step = b.step("test", "Run renderer tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const install_test_renderer = b.addInstallFile(checked_renderer.getEmittedBin(), "extension/renderer.wasm");
    test_step.dependOn(&install_test_renderer.step);
    test_step.dependOn(&run_size_checker.step);

    const render_html_tests_root = b.createModule(.{
        .root_source_file = b.path("tools/render_html.zig"),
        .target = b.graph.host,
        .optimize = .debug,
        .imports = &.{
            .{ .name = "renderer_core", .module = rendererCoreModule(b, b.graph.host, .debug) },
            .{ .name = "viewer_assets", .module = assets_module },
        },
    });
    const render_html_tests = b.addTest(.{ .root_module = render_html_tests_root });
    test_step.dependOn(&b.addRunArtifact(render_html_tests).step);

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

fn addWasmRenderer(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const markdown = b.dependency("markdown_parser", .{
        .target = target,
        .optimize = optimize,
    }).module("markdown");
    const native_syntax = nativeSyntaxDependency(b, target, optimize);
    const renderer = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/renderer.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .strip = optimize != .debug,
            .imports = rendererImports(b, markdown, native_syntax),
        }),
    });
    renderer.rdynamic = true;
    renderer.entry = .disabled;
    return renderer;
}

fn rendererCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = rendererImports(
            b,
            b.dependency("markdown_parser", .{
                .target = target,
                .optimize = optimize,
            }).module("markdown"),
            nativeSyntaxDependency(b, target, optimize),
        ),
    });
}

fn nativeSyntaxDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    return b.dependency("native_syntax", .{
        .target = target,
        .optimize = optimize,
        .@"backend-ziggy" = true,
        .@"backend-ziggy-schema" = true,
        .@"backend-scripty" = true,
        .@"backend-html" = true,
        .@"backend-xml" = true,
        .@"backend-css" = true,
        .@"backend-superhtml" = true,
        .@"backend-markdown" = true,
    });
}

fn rendererImports(
    b: *std.Build,
    markdown: *std.Build.Module,
    native_syntax: *std.Build.Dependency,
) []const std.Build.Module.Import {
    return b.allocator.dupe(std.Build.Module.Import, &.{
        .{ .name = "markdown", .module = markdown },
        .{ .name = "native_syntax", .module = native_syntax.module("native_syntax") },
        .{ .name = "native_syntax_registry", .module = native_syntax.module("native_syntax_registry") },
    }) catch @panic("out of memory");
}
