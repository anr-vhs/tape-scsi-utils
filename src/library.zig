const std = @import("std");
const Changer = @import("changer.zig");
const Drive = @import("drive.zig");

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

pub fn init(changer_path: []const u8, drive_paths: []const []const u8, io: std.Io, allocator: std.mem.Allocator) !Self {
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
pub fn load(self: *Self, slot: usize, drive: usize) !void {
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
pub fn store(self: *Self, drive: usize, slot: usize) !void {
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

    self.drives.items[drive].drive.?.deinit();
    self.slots.items[slot].content = self.drives.items[drive].content;
    self.drives.items[drive].drive = null;
    self.drives.items[drive].content = null;

    try self.changer.store(drive, slot);
}

/// Move a tape from one element to another
pub fn move(self: *Self, source_kind: Changer.ElementKind, source_id: usize, dest_kind: Changer.ElementKind, dest_id: usize) !void {
    switch (source_kind) {
        .Slot => switch (dest_kind) {
            .Drive => return self.load(source_id, dest_id),
            .Slot => {
                if (source_id >= self.changer.n_slots) return Changer.Error.InvalidSlot;
                if (dest_id >= self.changer.n_slots) return Changer.Error.InvalidSlot;
                if (self.slots.items[source_id].content == null) return Error.SourceEmpty;
                if (self.slots.items[dest_id].content != null) return Error.DestinationFull;

                try self.changer.move(source_kind, source_id, dest_kind, dest_id);
                self.slots.items[dest_id].content = self.slots.items[source_id].content;
                self.slots.items[source_id].content = null;
            },
        },
        .Drive => switch (dest_kind) {
            .Slot => return self.store(source_id, dest_id),
            .Drive => {
                if (source_id >= self.changer.n_drives) return Changer.Error.InvalidDrive;
                if (dest_id >= self.changer.n_drives) return Changer.Error.InvalidDrive;
                if (self.drives.items[source_id].content == null) return Error.SourceEmpty;
                if (self.drives.items[dest_id].content != null) return Error.DestinationFull;

                self.drives.items[source_id].drive.?.deinit();
                self.changer.move(source_kind, source_id, dest_kind, dest_id) catch |err| {
                    self.drives.items[source_id].drive = try Drive.init(self.drives.items[source_id].path, self.io);
                    return err;
                };
                self.drives.items[dest_id].drive = try Drive.init(self.drives.items[dest_id].path, self.io);
                self.drives.items[dest_id].content = self.drives.items[source_id].content;
                self.drives.items[source_id].content = null;
            },
        },
    }
}
