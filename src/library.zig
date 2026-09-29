const std = @import("std");
pub const Changer = @import("changer.zig");
pub const Drive = @import("drive.zig");

const Tape = struct {
    volume_tag: [36]u8,
};

const DriveInterface = struct {
    path: []const u8,
    drive: ?Drive,
    content: ?Tape,
};

const Slot = struct {
    content: ?Tape,
};

pub const Error = error{
    InvalidPathAmount,
    SourceEmpty,
    DestinationFull,
};

const Self = @This();

changer: Changer,
drives: std.ArrayList(DriveInterface),
slots: std.ArrayList(Slot),
io: std.Io,
allocator: std.mem.Allocator,

/// Create a library controller object
/// @arg changer_path : Path to the changer device file
/// @arg drive_paths : Array of paths to the drive devices
pub fn init(changer_path: []const u8, drive_paths: [][]const u8, io: std.Io, allocator: std.mem.Allocator) !Self {
    const changer = try Changer.init(changer_path, io);
    if (changer.n_drives != drive_paths.len) {
        return Error.InvalidPathAmount;
    }
    var drives = try std.ArrayList(DriveInterface).initCapacity(allocator, drive_paths.len);
    var drive_contents = try changer.get_drives_contents(allocator);
    defer drive_contents.deinit(allocator);
    for (drive_paths, drive_contents.items) |drive_path, content| {
        if (content) |tag| {
            try drives.append(allocator, .{
                .path = drive_path,
                .drive = try Drive.init(drive_path, io),
                .content = .{ .volume_tag = tag },
            });
        } else {
            try drives.append(allocator, .{
                .path = drive_path,
                .drive = null,
                .content = null,
            });
        }
    }
    var slots = try std.ArrayList(Slot).initCapacity(allocator, changer.n_slots);
    var slot_contents = try changer.get_slots_contents(allocator);
    defer slot_contents.deinit(allocator);
    for (slot_contents.items) |content| {
        if (content) |tag| {
            try slots.append(allocator, .{
                .content = .{ .volume_tag = tag },
            });
        } else {
            try slots.append(allocator, .{
                .content = null,
            });
        }
    }
    return .{
        .changer = changer,
        .drives = drives,
        .slots = slots,
        .io = io,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.changer.deinit();
    for (self.drives.items) |drive_interface| {
        if (drive_interface.drive) |drive| {
            @constCast(&drive).deinit();
        }
    }
    self.drives.deinit(self.allocator);
    self.slots.deinit(self.allocator);
}

/// Load a tape in a drive
/// @arg slot : Slot number
/// @arg drive : Drive number
pub fn load(self: *Self, slot: u32, drive: u32) !void {
    if (slot >= self.changer.n_slots) {
        return Changer.Error.InvalidSlot;
    }
    if (drive >= self.changer.n_drives) {
        return Changer.Error.InvalidDrive;
    }
    if (self.slots.items[slot].content == null) {
        return Error.SourceEmpty;
    }
    if (self.drives.items[drive].content != null) {
        return Error.DestinationFull;
    }

    try self.changer.load(slot, drive);

    self.drives.items[drive].drive = try Drive.init(self.drives.items[drive].path, self.io);
    self.drives.items[drive].content = self.slots.items[slot].content;
    self.slots.items[slot].content = null;
}

/// Store a tape in a slot
/// @arg drive : Drive number
/// @arg slot : Slot number
pub fn store(self: *Self, drive: u32, slot: u32) !void {
    if (drive >= self.changer.n_drives) {
        return Changer.Error.InvalidDrive;
    }
    if (slot >= self.changer.n_slots) {
        return Changer.Error.InvalidSlot;
    }
    if (self.drives.items[drive].content == null) {
        return Error.SourceEmpty;
    }
    if (self.slots.items[slot].content != null) {
        return Error.DestinationFull;
    }

    try self.changer.store(drive, slot);

    self.drives.items[drive].drive.?.deinit();
    self.slots.items[slot].content = self.drives.items[drive].content;
    self.drives.items[drive].drive = null;
    self.drives.items[drive].content = null;
}
