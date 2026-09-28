const std = @import("std");
const changer = @import("changer");
const drive = @import("drive");

const rstopwatch = @import("rstopwatch.zig");

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    var changer_controller = try changer.init(args[1], init.io);
    defer changer_controller.deinit();

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
    try changer_controller.load(0, 0);
    try stopwatch.take_snapshot();
    try changer_controller.store(0, 0);
    try stopwatch.take_snapshot();

    try stdout.print("Time spent in I/O\n" ++
        "    Load  : {}\n" ++
        "    Store : {}\n", .{
        (try stopwatch.get_lap(0)).iotime(),
        (try stopwatch.get_lap(1)).iotime(),
    });

    return 0;
}
