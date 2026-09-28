const std = @import("std");
const Changer = @import("changer");
const Drive = @import("drive");

const rstopwatch = @import("rstopwatch.zig");

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    var changer = try Changer.init(args[1], init.io);
    defer changer.deinit();

    var drive_files = try std.ArrayList([]const u8).initCapacity(init.gpa, args.len - 2);
    var i: u8 = 2;
    while (i < args.len) : (i += 1) {
        try drive_files.append(init.gpa, args[i]);
    }
    defer drive_files.deinit(init.gpa);

    std.log.debug("Starting benchmarks", .{});

    var stopwatch = try rstopwatch.init(std.Io.Clock.real, init.io, init.gpa);
    defer stopwatch.deinit();

    try stopwatch.take_snapshot();
    try changer.load(0, 0);
    try stopwatch.take_snapshot();
    try changer.store(0, 0);
    try stopwatch.take_snapshot();

    try stdout.print("Time spent in I/O\n" ++
        "    Load  : {}\n" ++
        "    Store : {}\n", .{
        (try stopwatch.get_lap(0)).iotime(),
        (try stopwatch.get_lap(1)).iotime(),
    });

    return 0;
}
