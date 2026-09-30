const std = @import("std");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("stdio.h");
});

pub const Error = error{
    IoctlError,
};

pub fn ioctl(fd: c_int, op: c_ulong, arg: *anyopaque) !void {
    if (c.ioctl(fd, op, arg) == -1) {
        c.perror("ioctl");
        return Error.IoctlError;
    }
}
