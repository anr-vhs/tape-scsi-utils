const std = @import("std");
const tapelib = @import("library");
const Library = tapelib.Library;
const Changer = tapelib.Changer;
const Drive = tapelib.Drive;

const argparse = @import("argparse.zig");

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;
    const args = argparse.argparse(init) catch |e| switch (e) {
        argparse.Error.ParseError => {
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
            var changer = try Changer.init(args.device, init.io);
            defer changer.deinit();
            try changer.load(args.slot, args.drive);
        },
        .store => {
            var changer = try Changer.init(args.device, init.io);
            defer changer.deinit();
            try changer.store(args.drive, args.slot);
        },
        .contents => {
            var changer = try Changer.init(args.device, init.io);
            defer changer.deinit();
            var drive_contents = try changer.get_drives_contents(init.gpa);
            defer drive_contents.deinit(init.gpa);
            for (drive_contents.items, 0..) |drive, i| {
                try stdout.print("Drive {}: ", .{i});
                if (drive) |tag| {
                    try stdout.print("{s}\n", .{tag});
                } else {
                    try stdout.print("Empty\n", .{});
                }
            }
            var slots_contents = try changer.get_slots_contents(init.gpa);
            defer slots_contents.deinit(init.gpa);
            for (slots_contents.items, 0..) |slot, i| {
                try stdout.print("Slot {}: ", .{i});
                if (slot) |tag| {
                    try stdout.print("{s}\n", .{tag});
                } else {
                    try stdout.print("Empty\n", .{});
                }
            }
        },
        .seek => {
            var drive = try Drive.init(args.device, init.io);
            defer drive.deinit();
            try drive.seek(args.block);
        },
        .tell => {
            var drive = try Drive.init(args.device, init.io);
            defer drive.deinit();
            try stdout.print("{}", .{try drive.tell()});
        },
    }
    return 0;
}
