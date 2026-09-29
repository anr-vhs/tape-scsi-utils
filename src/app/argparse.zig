const std = @import("std");

pub const op = enum {
    load,
    store,
    contents,
    seek,
    tell,
};
pub const op_args = struct {
    op: op,
    device: []const u8,
    slot: u32 = 0,
    drive: u32 = 0,
    block: u128 = 0,
};
pub const Error = error{ParseError};

pub fn argparse(init: std.process.Init) !op_args {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    if (args.len == 1) {
        return Error.ParseError;
    }
    const op_arg = args[1];
    if (std.mem.eql(u8, op_arg, "help")) {
        help(args[0]);
        std.process.exit(0);
    }
    if (std.mem.eql(u8, op_arg, "load")) {
        if (args.len < 4) {
            return Error.ParseError;
        }
        return .{
            .op = .load,
            .slot = std.fmt.parseInt(u32, args[2], 10) catch {
                return Error.ParseError;
            },
            .drive = std.fmt.parseInt(u32, args[3], 10) catch {
                return Error.ParseError;
            },
            .device = if (args.len == 4) "/dev/sch0" else args[5],
        };
    }
    if (std.mem.eql(u8, op_arg, "store")) {
        if (args.len < 4) {
            return Error.ParseError;
        }
        return .{
            .op = .store,
            .drive = std.fmt.parseInt(u32, args[2], 10) catch {
                return Error.ParseError;
            },
            .slot = std.fmt.parseInt(u32, args[3], 10) catch {
                return Error.ParseError;
            },
            .device = if (args.len == 4) "/dev/sch0" else args[5],
        };
    }
    if (std.mem.eql(u8, op_arg, "contents")) {
        return .{
            .op = .contents,
            .device = if (args.len == 2) "/dev/sch0" else args[2],
        };
    }
    if (std.mem.eql(u8, op_arg, "seek")) {
        if (args.len < 4) {
            return Error.ParseError;
        }
        return .{
            .op = .seek,
            .device = args[2],
            .block = std.fmt.parseInt(u128, args[3], 10) catch {
                return Error.ParseError;
            },
        };
    }
    if (std.mem.eql(u8, op_arg, "tell")) {
        if (args.len < 3) {
            return Error.ParseError;
        }
        return .{
            .op = .tell,
            .device = args[2],
        };
    }
    return Error.ParseError;
}

pub fn help(cmd: []const u8) void {
    std.debug.print("Help :\n" ++
        "{s} <operation> [args]...\n\n" ++
        "Available operations :\n" ++
        "    help : Show this message and exit" ++
        "  Changer operations\n" ++
        "    load <slot> <drive> [device] : Load a tape from a slot to a drive\n" ++
        "    store <drive> <slot> [device] : Store a tape from a drive to a slot\n" ++
        "    contents [device] : Get the contents of each drive and slot\n" ++
        "  Tape drive operations\n" ++
        "    tell <device> : Tell at which block the reader is in the tape\n" ++
        "    seek <device> <block> : Seek to the block\n", .{cmd});
}
