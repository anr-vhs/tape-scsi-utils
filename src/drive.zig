const std = @import("std");

const mtio = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("linux/mtio.h");
});
const ioctl = mtio.ioctl;
const mtop = mtio.mtop;

const Self = @This();

const DriveError = error{
    IoctlError,
};

/// File descriptor of the device file
file: std.Io.File,
io: std.Io,

/// Create a drive object
/// @arg device_path : The absolute path to the device file
pub fn init(device_path: []const u8, io: std.Io) !Self {
    const device_file = try std.Io.Dir.openFileAbsolute(io, device_path, .{ .mode = .read_write });
    return .{
        .file = device_file,
        .io = io,
    };
}

pub fn deinit(self: *Self) void {
    self.file.close(self.io);
}

/// Seek to a block
/// @arg block : Block number
pub fn seek(self: *const Self, block: u128) !void {
    std.log.debug("Seeking to {}", .{block});
    const op: mtop = .{
        .mt_op = mtio.MTSEEK,
        .mt_count = @intCast(block),
    };

    const r = ioctl(self.file.handle, mtio.MTIOCTOP, &op);
    if (r != 0) {
        return DriveError.IoctlError;
    }
}

/// Tell which block the reader is on
pub fn tell(self: *const Self) !u128 {
    std.log.debug("Telling", .{});
    var pos: mtio.mtpos = undefined;

    const r = ioctl(self.file.handle, mtio.MTIOCPOS, &pos);
    if (r != 0) {
        return DriveError.IoctlError;
    }
    return @intCast(pos.mt_blkno);
}
