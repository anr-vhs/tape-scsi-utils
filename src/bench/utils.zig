const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Error = error{
    InvalidDimensions,
    IndexOutOfBonds,
};

pub fn NDArray(comptime N: comptime_int, comptime T: type) type {
    return struct {
        data: []T,
        dimensions: [N]usize,
        buffer_size: usize,

        pub fn init(gpa: Allocator, dimensions: [N]usize) !@This() {
            var buffer_size: usize = 1;
            for (dimensions) |d| {
                buffer_size *= d;
            }
            if (buffer_size == 0) {
                return Error.InvalidDimensions;
            }
            return .{
                .dimensions = dimensions,
                .buffer_size = buffer_size,
                .data = try gpa.alloc(T, buffer_size),
            };
        }

        pub fn deinit(self: *@This(), gpa: Allocator) void {
            gpa.free(self.data);
        }

        pub fn get(self: *@This(), pos: [N]usize) *T {
            var index: usize = 0;
            var current_subarray_size: usize = 1;
            for (0..N) |i| {
                index += pos[i] * current_subarray_size;
                current_subarray_size *= self.dimensions[i];
            }
            return &self.data[index];
        }
    };
}
