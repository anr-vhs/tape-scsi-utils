const std = @import("std");
const Changer = @import("changer");
const Drive = @import("drive");
const Library = @import("library");

const rstopwatch = @import("rstopwatch.zig");

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    var drive_files = try std.ArrayList([]const u8).initCapacity(init.gpa, args.len - 2);
    for (2..args.len) |i| {
        try drive_files.append(init.gpa, args[i]);
    }
    defer drive_files.deinit(init.gpa);

    var library = try Library.init(args[1], drive_files.items, init.io, init.gpa);
    defer library.deinit();

    std.log.debug("Starting benchmarks", .{});

    var stopwatch = try rstopwatch.init(std.Io.Clock.real, init.io, init.gpa);
    defer stopwatch.deinit();

    try stopwatch.take_snapshot();
    try library.load(0, 0);
    try stopwatch.take_snapshot();
    try library.store(0, 0);
    try stopwatch.take_snapshot();

    try stdout.print("Time spent in I/O\n" ++
        "    Load  : {}\n" ++
        "    Store : {}\n", .{
        (try stopwatch.get_lap(0)).iotime(),
        (try stopwatch.get_lap(1)).iotime(),
    });

    return 0;
}
