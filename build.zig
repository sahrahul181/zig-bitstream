const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Public library module ─────────────────────────────────────────────
    const mod = b.addModule("zig_bitstream", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // ── Unit tests: library module (src/root.zig and its imports) ─────────
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // ── Integration tests: test.zig (black-box, imports public module) ─────
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_bitstream", .module = mod },
        },
    });
    const integration_tests = b.addTest(.{
        .root_module = integration_mod,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    // ── Examples step ────────────────────────────────────────────────────────
    const examples_exe = b.addExecutable(.{
        .name = "examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    examples_exe.root_module.addImport("zig_bitstream", mod);

    const run_examples = b.addRunArtifact(examples_exe);
    const examples_step = b.step("run-examples", "Run the bitstream examples binary");
    examples_step.dependOn(&run_examples.step);

    // ── Aggregate test step ───────────────────────────────────────────────────
    const test_step = b.step("test", "Run all tests (unit + integration)");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
