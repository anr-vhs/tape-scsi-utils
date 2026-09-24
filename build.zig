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

    const load = b.addExecutable(.{ .name = "load", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/apps/load.zig"),
        .imports = &.{
            .{ .name = "changer", .module = changer },
        },
    }) });
    const store = b.addExecutable(.{ .name = "store", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/apps/store.zig"),
        .imports = &.{
            .{ .name = "changer", .module = changer },
        },
    }) });

    b.installArtifact(load);
    b.installArtifact(store);
}
