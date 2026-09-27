const std = @import("std");
const changer = @import("changer");
const drive = @import("drive");

const argparse = @import("argparse.zig");

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;
    const args = argparse.argparse(init) catch |e| switch (e) {
        argparse.err.ParseError => {
            std.log.err("Invalid usage", .{});
            const argv = try init.minimal.args.toSlice(init.gpa);
            defer init.gpa.free(argv);
            argparse.help(argv[0]);
            return 1;
        },
        else => {
            return e;
        },
    };
    const device = try std.Io.Dir.openFileAbsolute(init.io, args.device, .{ .mode = .read_write });
    defer device.close(init.io);
    switch (args.op) {
        .load => {
            const c = try changer.create(device.handle);
            try c.load(args.slot, args.drive);
        },
        .store => {
            const c = try changer.create(device.handle);
            try c.store(args.drive, args.slot);
        },
        .seek => {
            const d = try drive.create(device.handle);
            try d.seek(args.block);
        },
        .tell => {
            const d = try drive.create(device.handle);
            try stdout.print("{}", .{try d.tell()});
        },
    }
    return 0;
}
