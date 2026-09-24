const std = @import("std");
const changer = @import("changer");

const load_args = struct { path: []const u8, slot: u32, drive: u32 };
const e = error{ParseError};

fn argparse(init: std.process.Init) !load_args {
    const args = try init.minimal.args.toSlice(init.arena.child_allocator);
    var parsed_args: load_args = .{
        .path = "/dev/sch0",
        .slot = undefined,
        .drive = undefined,
    };
    var slot_set = false;
    var drive_set = false;
    var i: u8 = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-f")) {
            i += 1;
            parsed_args.path = args[i];
        } else if (!slot_set) {
            parsed_args.slot = try std.fmt.parseInt(u32, args[i], 10);
            slot_set = true;
        } else if (!drive_set) {
            parsed_args.drive = try std.fmt.parseInt(u32, args[i], 10);
            drive_set = true;
        } else {
            return e.ParseError;
        }
    }
    if (!slot_set or !drive_set) {
        return e.ParseError;
    }
    return parsed_args;
}

pub fn main(init: std.process.Init) !void {
    const args = try argparse(init);
    const changer_file = try std.Io.Dir.openFileAbsolute(init.io, args.path, .{ .mode = .read_write });
    defer changer_file.close(init.io);
    const c = try changer.create(changer_file.handle);
    try c.load(args.slot, args.drive);
}
