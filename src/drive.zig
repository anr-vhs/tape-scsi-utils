const std = @import("std");

const mtio = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("linux/mtio.h");
});
const mtop = mtio.mtop;

const ioctl = @import("ioctl.zig").ioctl;
const perror = @import("ioctl.zig").perror;

const Self = @This();

const Error = error{
    IoctlError,
    WriteError,
    ReadError,
};

/// File descriptor of the device file
file: std.Io.File,
io: std.Io,
block_size: usize,

/// Create a drive object
pub fn init(device_path: []const u8, io: std.Io) !Self {
    const device_file = try std.Io.Dir.openFileAbsolute(io, device_path, .{ .mode = .read_write });
    errdefer device_file.close(io);
    var info: mtio.mtget = undefined;
    try ioctl(device_file.handle, mtio.MTIOCGET, &info);
    return .{
        .file = device_file,
        .io = io,
        .block_size = @intCast((info.mt_dsreg & mtio.MT_ST_BLKSIZE_MASK) >> mtio.MT_ST_BLKSIZE_SHIFT),
    };
}

pub fn deinit(self: *Self) void {
    self.file.close(self.io);
}

/// Seek to a block
pub fn seek(self: *const Self, block: usize) !void {
    std.log.debug("Seeking to {}", .{block});
    var op: mtop = .{
        .mt_op = mtio.MTSEEK,
        .mt_count = @intCast(block),
    };

    try ioctl(self.file.handle, mtio.MTIOCTOP, &op);
}

/// Tell which block the reader is on
pub fn tell(self: *const Self) !usize {
    std.log.debug("Telling", .{});
    var pos: mtio.mtpos = undefined;

    try ioctl(self.file.handle, mtio.MTIOCPOS, &pos);

    return @intCast(pos.mt_blkno);
}

/// Sets the block size of the tape
///
/// Setting the block size to 0 means variable block size
pub fn set_blksize(self: *Self, blksize: usize) !void {
    var op: mtop = .{
        .mt_op = mtio.MTSETBLK,
        .mt_count = @intCast(blksize),
    };

    try ioctl(self.file.handle, mtio.MTIOCTOP, &op);

    self.block_size = blksize;
}

/// Writes a data structure to the tape
pub fn write(self: *const Self, comptime T: type, data: *const T) !void {
    if (self.block_size == 0) {
        if (std.c.write(self.file.handle, @ptrCast(data), @sizeOf(T)) != @sizeOf(T)) {
            perror("write");
            return Error.WriteError;
        }
        return;
    }

    // Pad if needed
    const buffer_size = (@divFloor(@sizeOf(T), self.block_size) + 1) * self.block_size;
    const buffer = try std.heap.page_allocator.alloc(u8, buffer_size);
    defer std.heap.page_allocator.free(buffer);

    @memset(buffer, 0);
    @memcpy(buffer.ptr, data);

    self.write_bytes(buffer.ptr, buffer.len) catch {
        perror("write");
        return Error.WriteError;
    };
}

/// Write raw bytes of data to the tape
pub fn write_bytes(self: *const Self, data: [*]const u8, size: usize) !void {
    if (std.c.write(self.file.handle, data, size) != size) {
        return Error.WriteError;
    }
}

/// Read a data structure from the tape
pub fn read(self: *const Self, comptime T: type) !T {
    var data: T = undefined;
    if (self.block_size == 0) {
        if (std.c.read(self.file.handle, @ptrCast(&data), @sizeOf(T)) != @sizeOf(T)) {
            perror("read");
            return Error.ReadError;
        }
    } else {
        const buffer_size = (@divFloor(@sizeOf(T), self.block_size) + 1) * self.block_size;
        const buffer = try std.heap.page_allocator.alloc(u8, buffer_size);
        defer std.heap.page_allocator.free(buffer);

        self.read_bytes(buffer.ptr, buffer_size) catch {
            perror("read");
            return Error.ReadError;
        };

        @memcpy(&data, buffer[0 .. @sizeOf(T) - 1]);
    }
    return data;
}

/// Read raw bytes of data from the tape
pub fn read_bytes(self: *const Self, data: [*]u8, size: usize) !void {
    if (std.c.read(self.file.handle, data, size) != size) {
        return Error.ReadError;
    }
}
