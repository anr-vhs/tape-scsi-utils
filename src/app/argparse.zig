const std = @import("std");

pub const op = enum {
    load,
    store,
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
pub const err = error{ParseError};

pub fn argparse(init: std.process.Init) !op_args {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    if (args.len == 1) {
        return err.ParseError;
    }
    const op_arg = args[1];
    if (std.mem.eql(u8, op_arg, "help")) {
        help(args[0]);
        std.process.exit(0);
    }
    if (std.mem.eql(u8, op_arg, "load")) {
        if (args.len < 4) {
            return err.ParseError;
        }
        return .{
            .op = .load,
            .slot = std.fmt.parseInt(u32, args[2], 10) catch {
                return err.ParseError;
            },
            .drive = std.fmt.parseInt(u32, args[3], 10) catch {
                return err.ParseError;
            },
            .device = if (args.len == 4) "/dev/sch0" else args[5],
        };
    }
    if (std.mem.eql(u8, op_arg, "store")) {
        if (args.len < 4) {
            return err.ParseError;
        }
        return .{
            .op = .store,
            .drive = std.fmt.parseInt(u32, args[2], 10) catch {
                return err.ParseError;
            },
            .slot = std.fmt.parseInt(u32, args[3], 10) catch {
                return err.ParseError;
            },
            .device = if (args.len == 4) "/dev/sch0" else args[5],
        };
    }
    if (std.mem.eql(u8, op_arg, "seek")) {
        if (args.len < 4) {
            return err.ParseError;
        }
        return .{
            .op = .seek,
            .device = args[2],
            .block = std.fmt.parseInt(u128, args[3], 10) catch {
                return err.ParseError;
            },
        };
    }
    if (std.mem.eql(u8, op_arg, "tell")) {
        if (args.len < 3) {
            return err.ParseError;
        }
        return .{
            .op = .tell,
            .device = args[2],
        };
    }
    return err.ParseError;
}

pub fn help(cmd: []const u8) void {
    std.debug.print("Help :\n" ++
        "{s} <operation> [args]...\n\n" ++
        "Available operations :\n" ++
        "    help : Show this message and exit" ++
        "  Changer operations\n" ++
        "    load <slot> <drive> [device] : Load a tape from a slot to a drive\n" ++
        "    store <drive> <slot> [device] : Store a tape from a drive to a slot\n" ++
        "  Tape drive operations\n" ++
        "    tell <device> : Tell at which block the reader is in the tape\n" ++
        "    seek <device> <block> : Seek to the block\n", .{cmd});
}
