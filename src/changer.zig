const std = @import("std");

const chio = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("linux/chio.h");
});
const ioctl = chio.ioctl;

const Self = @This();

const ChangerError = error{
    IoctlError,
    InvalidDrive,
    InvalidSlot,
};

/// File handle of the device file
file: std.Io.File,
io: std.Io,
/// Number of drives
n_drives: u32,
/// Number of slots
n_slots: u32,

/// Create a changer object
/// @arg device_path : The absolute path to the device file
pub fn init(device_path: []const u8, io: std.Io) !Self {
    const device_file = try std.Io.Dir.openFileAbsolute(io, device_path, .{ .mode = .read_write });
    var changer_infos: chio.struct_changer_params = undefined;
    const r = ioctl(device_file.handle, chio.CHIOGPARAMS, &changer_infos);
    if (r != 0) {
        return ChangerError.IoctlError;
    }
    return .{
        .file = device_file,
        .io = io,
        .n_drives = @intCast(changer_infos.cp_ndrives),
        .n_slots = @intCast(changer_infos.cp_nslots),
    };
}

pub fn deinit(self: *Self) void {
    self.file.close(self.io);
}

/// Load a tape in a drive
/// @arg slot : Slot number
/// @arg drive : Drive number
pub fn load(self: *const Self, slot: u32, drive: u32) !void {
    if (slot >= self.n_slots) {
        return ChangerError.InvalidSlot;
    }
    if (drive >= self.n_drives) {
        return ChangerError.InvalidDrive;
    }
    std.log.debug(
        "Loading from slot {d} to drive {d}",
        .{ slot, drive },
    );

    var move = std.mem.zeroes(chio.struct_changer_move);
    move.cm_fromtype = chio.CHET_ST;
    move.cm_fromunit = @intCast(slot);
    move.cm_totype = chio.CHET_DT;
    move.cm_tounit = @intCast(drive);
    move.cm_flags = 0;

    const r = ioctl(self.file.handle, chio.CHIOMOVE, &move);
    if (r != 0) {
        return ChangerError.IoctlError;
    }
}

/// Load a tape in a slot
/// @arg drive : Drive number
/// @arg slot : Slot number
pub fn store(self: *const Self, drive: u32, slot: u32) !void {
    if (drive >= self.n_drives) {
        return ChangerError.InvalidDrive;
    }
    if (slot >= self.n_slots) {
        return ChangerError.InvalidSlot;
    }
    std.log.debug(
        "Storing from drive {d} to slot {d}",
        .{ drive, slot },
    );

    var move = std.mem.zeroes(chio.struct_changer_move);
    move.cm_fromtype = chio.CHET_DT;
    move.cm_fromunit = @intCast(drive);
    move.cm_totype = chio.CHET_ST;
    move.cm_tounit = @intCast(slot);
    move.cm_flags = 0;

    const r = ioctl(self.file.handle, chio.CHIOMOVE, &move);
    if (r != 0) {
        return ChangerError.IoctlError;
    }
}
