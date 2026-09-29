const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const library = b.addModule("library", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/library.zig"),
    });

    const tapelib = b.addLibrary(.{
        .name = "tapelibrary",
        .linkage = .dynamic,
        .root_module = library,
    });

    const tape = b.addExecutable(.{ .name = "tape", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/app/main.zig"),
        .imports = &.{
            .{ .name = "library", .module = library },
        },
    }) });

    const bench = b.addExecutable(.{ .name = "bench", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/bench/main.zig"),
        .imports = &.{
            .{ .name = "library", .module = library },
        },
    }) });

    b.installArtifact(tapelib);
    b.installArtifact(tape);
    b.installArtifact(bench);

    const docs = b.addInstallDirectory(.{
        .source_dir = tapelib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&docs.step);
}
