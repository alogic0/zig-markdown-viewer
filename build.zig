const std = @import("std");

const release_version = "0.5.1";

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const strip_wasm_names = b.addExecutable(.{
        .name = "strip-wasm-metadata",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/strip_wasm_names.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const syntax_exclusions = b.option(
        []const u8,
        "size-analysis-exclude-backends",
        "Comma-separated native syntax backends omitted only for code-size analysis",
    ) orelse "";
    const syntax_inclusions = b.option(
        []const u8,
        "size-analysis-include-backends",
        "Comma-separated experimental syntax backends linked only for code-size analysis",
    ) orelse "";
    const check_wasm_size = b.option(
        bool,
        "check-wasm-size",
        "Compare the test renderer with the checked-in pinned-dependency size baseline",
    ) orelse true;
    const logo_formula = b.option(
        []const u8,
        "logo-formula",
        "Inline math formula rendered into the extension logo",
    ) orelse "$M^{\\,z}$";
    const logo_background = b.option(
        []const u8,
        "logo-background",
        "Six-digit hex background color for the extension logo",
    ) orelse "#2563eb";
    const logo_foreground = b.option(
        []const u8,
        "logo-foreground",
        "Six-digit hex foreground color for the extension logo",
    ) orelse "#f8fafc";

    const formula_logo_generator = b.addExecutable(.{
        .name = "generate-formula-logo",
        .root_module = formulaLogoModule(b, b.graph.host, .safe),
    });
    const run_formula_logo_generator = b.addRunArtifact(formula_logo_generator);
    run_formula_logo_generator.addArgs(&.{ logo_formula, logo_background, logo_foreground });
    const generated_formula_logo = run_formula_logo_generator.addOutputFileArg("favicon.svg");

    const logo_sizes = [_]u16{ 16, 32, 48, 128 };
    var generated_formula_logo_pngs: [logo_sizes.len]std.Build.LazyPath = undefined;
    var previous_rasterize_formula_logo: ?*std.Build.Step = null;
    for (logo_sizes, 0..) |size, index| {
        const rasterize_formula_logo = b.addSystemCommand(&.{"sh"});
        if (previous_rasterize_formula_logo) |previous| {
            rasterize_formula_logo.step.dependOn(previous);
        }
        rasterize_formula_logo.addFileArg(b.path("tools/rasterize_formula_logo.sh"));
        rasterize_formula_logo.addFileArg(generated_formula_logo);
        rasterize_formula_logo.addArg(b.fmt("{d}", .{size}));
        generated_formula_logo_pngs[index] = rasterize_formula_logo.addOutputFileArg(
            b.fmt("icon{d}.png", .{size}),
        );
        previous_rasterize_formula_logo = &rasterize_formula_logo.step;
    }

    const update_formula_logo = b.addUpdateSourceFiles();
    update_formula_logo.addCopyFileToSource(generated_formula_logo, "extension/icons/favicon.svg");
    for (logo_sizes, generated_formula_logo_pngs) |size, generated_png| {
        update_formula_logo.addCopyFileToSource(
            generated_png,
            b.fmt("extension/icons/icon{d}.png", .{size}),
        );
    }
    const update_formula_logo_step = b.step(
        "update-logo",
        "Render and rasterize the configured math formula logo into extension/icons",
    );
    update_formula_logo_step.dependOn(&update_formula_logo.step);

    const renderer = addWasmRenderer(b, strip_wasm_names, "renderer", wasm_target, optimize, syntax_inclusions, syntax_exclusions);
    const checked_renderer = if (optimize == .small)
        renderer
    else
        addWasmRenderer(b, strip_wasm_names, "renderer", wasm_target, .small, syntax_inclusions, syntax_exclusions);
    const baseline_renderer = if (syntax_inclusions.len == 0 and syntax_exclusions.len == 0)
        checked_renderer
    else
        addWasmRenderer(b, strip_wasm_names, "renderer", wasm_target, .small, "", "");

    b.installDirectory(.{
        .source_dir = b.path("extension"),
        .install_dir = .prefix,
        .install_subdir = "extension",
    });
    const install_renderer = b.addInstallFile(
        checked_renderer,
        "extension/renderer.wasm",
    );
    b.getInstallStep().dependOn(&install_renderer.step);

    const run_chromium_math_e2e = b.addSystemCommand(&.{"sh"});
    run_chromium_math_e2e.addFileArg(b.path("tools/run_chromium_math_e2e.sh"));
    run_chromium_math_e2e.addDirectoryArg(b.path("extension"));
    run_chromium_math_e2e.addFileArg(checked_renderer);
    run_chromium_math_e2e.addFileArg(b.path("tests/browser/visual-math-e2e.html"));
    const chromium_math_e2e_step = b.step(
        "chromium-math-e2e",
        "Run the visual-math Wasm, sanitizer, font, geometry, and export test in Chromium",
    );
    chromium_math_e2e_step.dependOn(&run_chromium_math_e2e.step);

    const run_chromium_source_e2e = b.addSystemCommand(&.{"sh"});
    run_chromium_source_e2e.addFileArg(b.path("tools/run_chromium_source_e2e.sh"));
    run_chromium_source_e2e.addDirectoryArg(b.path("extension"));
    run_chromium_source_e2e.addFileArg(checked_renderer);
    run_chromium_source_e2e.addFileArg(b.path("tests/browser/source-server.cjs"));
    const chromium_source_e2e_step = b.step(
        "chromium-source-e2e",
        "Verify attachment-style source navigation and highlighting in Chromium",
    );
    chromium_source_e2e_step.dependOn(&run_chromium_source_e2e.step);

    const size_checker = b.addExecutable(.{
        .name = "check-wasm-size",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_wasm_size.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_size_checker = b.addRunArtifact(size_checker);
    run_size_checker.addFileArg(baseline_renderer);
    run_size_checker.addFileArg(b.path("tools/renderer_wasm_size.txt"));
    const size_step = b.step("check-wasm-size", "Compare the release-small renderer Wasm size with its checked-in baseline");
    size_step.dependOn(&run_size_checker.step);

    const write_size_baseline = b.addRunArtifact(size_checker);
    write_size_baseline.addArg("--write");
    write_size_baseline.addFileArg(baseline_renderer);
    const generated_size_baseline = write_size_baseline.captureStdOut(.{});
    const update_size_baseline = b.addUpdateSourceFiles();
    update_size_baseline.addCopyFileToSource(generated_size_baseline, "tools/renderer_wasm_size.txt");
    update_size_baseline.step.dependOn(&write_size_baseline.step);
    const update_size_step = b.step(
        "update-wasm-size-baseline",
        "Update the checked-in renderer Wasm size after reviewing an intentional change",
    );
    update_size_step.dependOn(&update_size_baseline.step);

    const extension_packager = b.addExecutable(.{
        .name = "package-extension",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/package_extension.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    const run_extension_packager = b.addRunArtifact(extension_packager);
    // The packager discovers extension assets recursively, so it must run even
    // when the build graph cannot enumerate a directory's changed children.
    run_extension_packager.has_side_effects = true;
    run_extension_packager.addArg(release_version);
    run_extension_packager.addDirectoryArg(b.path("extension"));
    run_extension_packager.addFileArg(checked_renderer);
    const extension_archive = run_extension_packager.addOutputFileArg(b.fmt(
        "zig-markdown-viewer-{s}.zip",
        .{release_version},
    ));
    const install_extension_archive = b.addInstallFile(
        extension_archive,
        b.fmt("dist/zig-markdown-viewer-{s}.zip", .{release_version}),
    );
    const package_extension_step = b.step(
        "package-extension",
        "Build a deterministic, validated Chrome extension ZIP",
    );
    package_extension_step.dependOn(&install_extension_archive.step);

    const size_report_backends = b.option(
        []const u8,
        "size-report-backends",
        "Comma-separated core backends included in the Wasm contribution report",
    ) orelse "php,objc,nix,fish,gdscript,nu,awk,typst,elixir,julia,haskell,perl,ocaml,fsharp";
    const size_report_groups = b.option(
        []const u8,
        "size-report-groups",
        "Semicolon-separated LABEL=BACKEND+BACKEND groups included in the Wasm contribution report",
    ) orelse "";
    const report_tool = b.addExecutable(.{
        .name = "report-wasm-sizes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/report_wasm_sizes.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_size_report = b.addRunArtifact(report_tool);
    const report_baseline = addWasmRenderer(b, strip_wasm_names, "renderer", wasm_target, .small, syntax_inclusions, "");
    run_size_report.addFileArg(report_baseline);
    var backend_names = std.mem.splitScalar(u8, size_report_backends, ',');
    while (backend_names.next()) |raw_name| {
        const name = std.mem.trim(u8, raw_name, " \t");
        if (name.len == 0) continue;
        const variant = addWasmRenderer(
            b,
            strip_wasm_names,
            "renderer",
            wasm_target,
            .small,
            syntax_inclusions,
            name,
        );
        run_size_report.addArg(name);
        run_size_report.addFileArg(variant);
    }
    var backend_groups = std.mem.splitScalar(u8, size_report_groups, ';');
    while (backend_groups.next()) |raw_group| {
        const group = std.mem.trim(u8, raw_group, " \t");
        if (group.len == 0) continue;
        const separator = std.mem.indexOfScalar(u8, group, '=') orelse
            std.process.fatal("invalid size report group '{s}': expected LABEL=BACKEND+BACKEND", .{group});
        const label = std.mem.trim(u8, group[0..separator], " \t");
        const members = std.mem.trim(u8, group[separator + 1 ..], " \t");
        if (label.len == 0 or members.len == 0)
            std.process.fatal("invalid size report group '{s}': label and backends must not be empty", .{group});
        const exclusions = b.allocator.dupe(u8, members) catch @panic("out of memory");
        for (exclusions) |*byte| if (byte.* == '+') {
            byte.* = ',';
        };
        const variant = addWasmRenderer(
            b,
            strip_wasm_names,
            "renderer",
            wasm_target,
            .small,
            syntax_inclusions,
            exclusions,
        );
        run_size_report.addArg(label);
        run_size_report.addFileArg(variant);
    }
    const size_report_step = b.step("wasm-size-report", "Measure marginal Wasm bytes for selected syntax backends and groups");
    size_report_step.dependOn(&run_size_report.step);

    const renderer_core = rendererCoreModule(b, b.graph.host, optimize, syntax_inclusions, syntax_exclusions);
    const assets_module = b.createModule(.{
        .root_source_file = b.path("viewer_assets.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
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

    const tests = b.addTest(.{ .root_module = rendererCoreModule(b, b.graph.host, .debug, syntax_inclusions, syntax_exclusions) });
    const test_step = b.step("test", "Run renderer tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const formula_logo_tests = b.addTest(.{
        .root_module = formulaLogoModule(b, b.graph.host, .debug),
    });
    test_step.dependOn(&b.addRunArtifact(formula_logo_tests).step);
    const install_test_renderer = b.addInstallFile(checked_renderer, "extension/renderer.wasm");
    test_step.dependOn(&install_test_renderer.step);
    if (check_wasm_size) test_step.dependOn(&run_size_checker.step);
    const strip_wasm_names_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/strip_wasm_names.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(strip_wasm_names_tests).step);
    const size_checker_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_wasm_size.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(size_checker_tests).step);

    const extension_packager_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/package_extension.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(extension_packager_tests).step);

    const pin_math_dependency_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/pin_math_dependency.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(pin_math_dependency_tests).step);

    const package_version_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/package_version.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(package_version_tests).step);

    const render_html_tests_root = b.createModule(.{
        .root_source_file = b.path("tools/render_html.zig"),
        .target = b.graph.host,
        .optimize = .debug,
        .imports = &.{
            .{ .name = "renderer_core", .module = rendererCoreModule(b, b.graph.host, .debug, syntax_inclusions, syntax_exclusions) },
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

fn formulaLogoModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const math_typesetter = b.dependency("math_typesetter", .{
        .target = target,
        .optimize = optimize,
    }).module("math_typesetter");
    return b.createModule(.{
        .root_source_file = b.path("tools/generate_formula_logo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "math_typesetter", .module = math_typesetter }},
    });
}

fn addWasmRenderer(
    b: *std.Build,
    strip_wasm_names: *std.Build.Step.Compile,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    syntax_inclusions: []const u8,
    syntax_exclusions: []const u8,
) std.Build.LazyPath {
    const markdown = b.dependency("markdown_parser", .{
        .target = target,
        .optimize = optimize,
    }).module("markdown");
    const math_typesetter = b.dependency("math_typesetter", .{
        .target = target,
        .optimize = optimize,
    }).module("math_typesetter");
    const native_syntax = nativeSyntaxDependency(b, target, optimize, syntax_inclusions, syntax_exclusions);
    const renderer_module = b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = optimize != .debug,
        .imports = rendererImports(b, markdown, math_typesetter, native_syntax),
    });
    renderer_module.export_symbol_names = &.{
        "allocateSource",
        "renderMarkdown",
        "renderSource",
        "renderedLength",
        "errorCode",
        "releaseSource",
        "releaseOutput",
    };
    const renderer = b.addExecutable(.{
        .name = name,
        .root_module = renderer_module,
    });
    renderer.entry = .disabled;
    if (optimize == .debug) return renderer.getEmittedBin();

    const run_strip = b.addRunArtifact(strip_wasm_names);
    run_strip.addFileArg(renderer.getEmittedBin());
    return run_strip.addOutputFileArg(b.fmt("{s}.wasm", .{name}));
}

fn rendererCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    syntax_inclusions: []const u8,
    syntax_exclusions: []const u8,
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
            b.dependency("math_typesetter", .{
                .target = target,
                .optimize = optimize,
            }).module("math_typesetter"),
            nativeSyntaxDependency(b, target, optimize, syntax_inclusions, syntax_exclusions),
        ),
    });
}

fn nativeSyntaxDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    syntax_inclusions: []const u8,
    syntax_exclusions: []const u8,
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
        .@"size-analysis-include-backends" = syntax_inclusions,
        .@"size-analysis-exclude-backends" = syntax_exclusions,
    });
}

fn rendererImports(
    b: *std.Build,
    markdown: *std.Build.Module,
    math_typesetter: *std.Build.Module,
    native_syntax: *std.Build.Dependency,
) []const std.Build.Module.Import {
    return b.allocator.dupe(std.Build.Module.Import, &.{
        .{ .name = "markdown", .module = markdown },
        .{ .name = "math_typesetter", .module = math_typesetter },
        .{ .name = "native_syntax", .module = native_syntax.module("native_syntax") },
        .{ .name = "native_syntax_registry", .module = native_syntax.module("native_syntax_registry") },
    }) catch @panic("out of memory");
}
