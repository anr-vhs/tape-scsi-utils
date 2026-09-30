const std = @import("std");

const chio = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("linux/chio.h");
});

const ioctl = @import("ioctl.zig").ioctl;

const Self = @This();

pub const Error = error{
    InvalidDrive,
    InvalidSlot,
};

pub const ElementKind = enum(c_int) {
    Drive = chio.CHET_DT,
    Slot = chio.CHET_ST,
};

/// File handle of the device file
file: std.Io.File,
/// Number of drives
n_drives: u32,
/// Number of slots
n_slots: u32,

io: std.Io,

/// Create a changer object
/// @arg device_path : The absolute path to the device file
pub fn init(device_path: []const u8, io: std.Io) !Self {
    const device_file = try std.Io.Dir.openFileAbsolute(io, device_path, .{ .mode = .read_write });
    var changer_infos: chio.struct_changer_params = undefined;
    try ioctl(device_file.handle, chio.CHIOGPARAMS, &changer_infos);
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
pub fn load(self: *const Self, slot: usize, drive: usize) !void {
    if (slot >= self.n_slots) {
        return Error.InvalidSlot;
    }
    if (drive >= self.n_drives) {
        return Error.InvalidDrive;
    }
    std.log.debug(
        "Loading from slot {d} to drive {d}",
        .{ slot, drive },
    );

    var move: chio.struct_changer_move = .{
        .cm_fromtype = @intFromEnum(ElementKind.Slot),
        .cm_fromunit = @intCast(slot),
        .cm_totype = @intFromEnum(ElementKind.Drive),
        .cm_tounit = @intCast(drive),
        .cm_flags = 0,
    };

    try ioctl(self.file.handle, chio.CHIOMOVE, &move);
}

/// Store a tape in a slot
/// @arg drive : Drive number
/// @arg slot : Slot number
pub fn store(self: *const Self, drive: usize, slot: usize) !void {
    if (drive >= self.n_drives) {
        return Error.InvalidDrive;
    }
    if (slot >= self.n_slots) {
        return Error.InvalidSlot;
    }
    std.log.debug(
        "Storing from drive {d} to slot {d}",
        .{ drive, slot },
    );

    var move: chio.struct_changer_move = .{
        .cm_fromtype = @intFromEnum(ElementKind.Drive),
        .cm_fromunit = @intCast(drive),
        .cm_totype = @intFromEnum(ElementKind.Slot),
        .cm_tounit = @intCast(slot),
        .cm_flags = 0,
    };

    try ioctl(self.file.handle, chio.CHIOMOVE, &move);
}

/// Get the contents of the drives
/// @returns An array of volume tags or null depending on wether the drive is full or not
pub fn get_drives_contents(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(?[36]u8) {
    var res = try std.ArrayList(?[36]u8).initCapacity(allocator, self.n_drives);

    var data = try std.ArrayList(u8).initCapacity(allocator, self.n_drives);
    defer data.deinit(allocator);
    try data.appendNTimes(allocator, 0, self.n_drives);
    var status: chio.changer_element_status = .{
        .ces_type = @intFromEnum(ElementKind.Drive),
        .ces_data = data.items.ptr,
    };
    try ioctl(self.file.handle, chio.CHIOGSTATUS, &status);

    for (data.items, 0..) |element_status, i| {
        if (element_status & chio.CESTATUS_FULL != 0) {
            var element: chio.changer_get_element = .{
                .cge_type = @intFromEnum(ElementKind.Drive),
                .cge_unit = @intCast(i),
            };
            try ioctl(self.file.handle, chio.CHIOGELEM, &element);
            try res.append(allocator, element.cge_pvoltag);
        } else {
            try res.append(allocator, null);
        }
    }

    return res;
}

/// Get the contents of the storage slots
/// @returns An array of volume tags or null depending on wether the slot is full or not
pub fn get_slots_contents(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(?[36]u8) {
    var res = try std.ArrayList(?[36]u8).initCapacity(allocator, self.n_slots);

    var data = try std.ArrayList(u8).initCapacity(allocator, self.n_slots);
    defer data.deinit(allocator);
    try data.appendNTimes(allocator, 0, self.n_slots);
    var status: chio.changer_element_status = .{
        .ces_type = @intFromEnum(ElementKind.Slot),
        .ces_data = data.items.ptr,
    };
    try ioctl(self.file.handle, chio.CHIOGSTATUS, &status);

    for (data.items, 0..) |element_status, i| {
        if (element_status & chio.CESTATUS_FULL != 0) {
            var element: chio.changer_get_element = .{
                .cge_type = @intFromEnum(ElementKind.Slot),
                .cge_unit = @intCast(i),
            };
            try ioctl(self.file.handle, chio.CHIOGELEM, &element);
            try res.append(allocator, element.cge_pvoltag);
        } else {
            try res.append(allocator, null);
        }
    }

    return res;
}

/// Move the robot arm to a position
/// @arg element_kind : The kind of element the target is (drive or slot)
/// @arg position : The number of the drive or slot to move to
pub fn move_arm(self: *const Self, element_kind: ElementKind, position: usize) !void {
    if (element_kind == ElementKind.Drive and position >= self.n_drives) {
        return Error.InvalidDrive;
    }
    if (element_kind == ElementKind.Slot and position >= self.n_slots) {
        return Error.InvalidSlot;
    }

    std.log.debug("Moving arm to {s} {}", .{ switch (element_kind) {
        .Drive => "Drive",
        .Slot => "Slot",
    }, position });

    var move: chio.changer_position = .{
        .cp_type = @intFromEnum(element_kind),
        .cp_unit = @intCast(position),
        .cp_flags = 0,
    };

    try ioctl(self.file.handle, chio.CHIOPOSITION, &move);
}
