pub const Library = @import("library.zig");
pub const Changer = @import("changer.zig");
pub const Drive = @import("drive.zig");

const std = @import("std");

const data = "Some data that will be written to the tape";

test "Library load/store" {
    var library = try Library.init("/dev/sch0", &.{"/dev/nst0"}, std.testing.io, std.testing.allocator);
    defer library.deinit();

    const start_drive_contents = try library.changer.get_drives_contents(std.testing.allocator);
    defer std.testing.allocator.free(start_drive_contents.items);
    const start_slots_contents = try library.changer.get_slots_contents(std.testing.allocator);
    defer std.testing.allocator.free(start_slots_contents.items);

    try library.load(0, 0);

    const mid_drive_contents = try library.changer.get_drives_contents(std.testing.allocator);
    defer std.testing.allocator.free(mid_drive_contents.items);
    const mid_slots_contents = try library.changer.get_slots_contents(std.testing.allocator);
    defer std.testing.allocator.free(mid_slots_contents.items);

    try std.testing.expectEqualStrings(&start_slots_contents.items[0].?, &mid_drive_contents.items[0].?);

    try std.testing.expectEqualSlices(?[36]u8, start_drive_contents.items[1..], mid_drive_contents.items[1..]);
    try std.testing.expectEqualSlices(?[36]u8, start_slots_contents.items[1..], mid_slots_contents.items[1..]);

    try library.store(0, 0);

    const end_drive_contents = try library.changer.get_drives_contents(std.testing.allocator);
    defer std.testing.allocator.free(end_drive_contents.items);
    const end_slots_contents = try library.changer.get_slots_contents(std.testing.allocator);
    defer std.testing.allocator.free(end_slots_contents.items);

    try std.testing.expectEqualSlices(?[36]u8, start_drive_contents.items, end_drive_contents.items);
    try std.testing.expectEqualSlices(?[36]u8, start_slots_contents.items, end_slots_contents.items);
}

test "Drive write" {
    var library = try Library.init("/dev/sch0", &.{"/dev/nst0"}, std.testing.io, std.testing.allocator);
    defer library.deinit();

    try library.load(0, 0);

    var drive = library.drives.items[0].drive.?;
    try drive.seek(0);
    try drive.set_blksize(32);
    try drive.write(@TypeOf(data.*), data);

    try library.store(0, 0);
}

test "Drive read" {
    var library = try Library.init("/dev/sch0", &.{"/dev/nst0"}, std.testing.io, std.testing.allocator);
    defer library.deinit();

    try library.load(0, 0);

    var drive = library.drives.items[0].drive.?;
    try drive.seek(0);
    const read_data = try drive.read(@TypeOf(data.*));

    try library.store(0, 0);

    try std.testing.expectEqual(data.*, read_data);
}
