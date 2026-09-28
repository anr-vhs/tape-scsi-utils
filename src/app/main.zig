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
    switch (args.op) {
        .load => {
            var c = try changer.init(args.device, init.io);
            defer c.deinit();
            try c.load(args.slot, args.drive);
        },
        .store => {
            var c = try changer.init(args.device, init.io);
            defer c.deinit();
            try c.store(args.drive, args.slot);
        },
        .seek => {
            var d = try drive.init(args.device, init.io);
            defer d.deinit();
            try d.seek(args.block);
        },
        .tell => {
            var d = try drive.init(args.device, init.io);
            defer d.deinit();
            try stdout.print("{}", .{try d.tell()});
        },
    }
    return 0;
}
