const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const changer = b.addModule("changer", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/changer.zig"),
        .link_libc = true,
    });

    const drive = b.addModule("drive", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/drive.zig"),
        .link_libc = true,
    });

    const library = b.addModule("library", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/library.zig"),
        .imports = &.{
            .{ .name = "changer", .module = changer },
            .{ .name = "drive", .module = drive },
        },
    });

    const tape = b.addExecutable(.{ .name = "tape", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/app/main.zig"),
        .imports = &.{
            .{ .name = "changer", .module = changer },
            .{ .name = "drive", .module = drive },
        },
    }) });

    const bench = b.addExecutable(.{ .name = "bench", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/bench/main.zig"),
        .imports = &.{
            .{ .name = "changer", .module = changer },
            .{ .name = "drive", .module = drive },
            .{ .name = "library", .module = library },
        },
    }) });

    b.installArtifact(tape);
    b.installArtifact(bench);
}
