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
fd: c_int,

/// Create a drive object
/// @arg device_fd : The file descriptor to the openned device file, this file has to stay open as long as we use the drive
pub fn create(device_fd: c_int) !Self {
    return .{
        .fd = device_fd,
    };
}

/// Seek to a block
/// @arg block : Block number
pub fn seek(self: *const Self, block: u128) !void {
    std.log.debug("Seeking to {}", .{block});
    const op: mtop = .{
        .mt_op = mtio.MTSEEK,
        .mt_count = @intCast(block),
    };

    const r = ioctl(self.fd, mtio.MTIOCTOP, &op);
    if (r != 0) {
        return DriveError.IoctlError;
    }
}

/// Tell which block the reader is on
pub fn tell(self: *const Self) !u128 {
    std.log.debug("Telling", .{});
    const op: mtop = .{
        .mt_op = mtio.MTSEEK,
        .mt_count = 0,
    };

    const r = ioctl(self.fd, mtio.MTIOCTOP, &op);
    if (r != 0) {
        return DriveError.IoctlError;
    }
    return @intCast(op.mt_count);
}
