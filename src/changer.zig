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
    if (ioctl(device_file.handle, chio.CHIOGPARAMS, &changer_infos) != 0) {
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

    var move: chio.struct_changer_move = .{
        .cm_fromtype = chio.CHET_ST,
        .cm_fromunit = @intCast(slot),
        .cm_totype = chio.CHET_DT,
        .cm_tounit = @intCast(drive),
        .cm_flags = 0,
    };

    if (ioctl(self.file.handle, chio.CHIOMOVE, &move) != 0) {
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

    var move: chio.struct_changer_move = .{
        .cm_fromtype = chio.CHET_DT,
        .cm_fromunit = @intCast(drive),
        .cm_totype = chio.CHET_ST,
        .cm_tounit = @intCast(slot),
        .cm_flags = 0,
    };

    if (ioctl(self.file.handle, chio.CHIOMOVE, &move) != 0) {
        return ChangerError.IoctlError;
    }
}

pub fn get_drives_contents(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(?[36]u8) {
    var res = try std.ArrayList(?[36]u8).initCapacity(allocator, self.n_drives);

    var data = try std.ArrayList(u8).initCapacity(allocator, self.n_drives);
    defer data.deinit(allocator);
    try data.appendNTimes(allocator, 0, self.n_drives);
    var status: chio.changer_element_status = .{
        .ces_type = chio.CHET_DT,
        .ces_data = data.items.ptr,
    };
    if (ioctl(self.file.handle, chio.CHIOGSTATUS, &status) != 0) {
        return ChangerError.IoctlError;
    }

    for (data.items, 0..) |element_status, i| {
        if (element_status & chio.CESTATUS_FULL != 0) {
            var element: chio.changer_get_element = .{
                .cge_type = chio.CHET_DT,
                .cge_unit = @intCast(i),
            };
            if (ioctl(self.file.handle, chio.CHIOGELEM, &element) != 0) {
                return ChangerError.IoctlError;
            }
            try res.append(allocator, element.cge_pvoltag);
        } else {
            try res.append(allocator, null);
        }
    }

    return res;
}

pub fn get_slots_contents(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(?[36]u8) {
    var res = try std.ArrayList(?[36]u8).initCapacity(allocator, self.n_slots);

    var data = try std.ArrayList(u8).initCapacity(allocator, self.n_slots);
    defer data.deinit(allocator);
    try data.appendNTimes(allocator, 0, self.n_slots);
    var status: chio.changer_element_status = .{
        .ces_type = chio.CHET_ST,
        .ces_data = data.items.ptr,
    };
    if (ioctl(self.file.handle, chio.CHIOGSTATUS, &status) != 0) {
        return ChangerError.IoctlError;
    }

    for (data.items, 0..) |element_status, i| {
        if (element_status & chio.CESTATUS_FULL != 0) {
            var element: chio.changer_get_element = .{
                .cge_type = chio.CHET_ST,
                .cge_unit = @intCast(i),
            };
            if (ioctl(self.file.handle, chio.CHIOGELEM, &element) != 0) {
                return ChangerError.IoctlError;
            }
            try res.append(allocator, element.cge_pvoltag);
        } else {
            try res.append(allocator, null);
        }
    }

    return res;
}
