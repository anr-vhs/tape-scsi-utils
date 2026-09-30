const std = @import("std");

pub const RSnapshot = struct {
    timestamp: std.Io.Timestamp,
    ressource: std.c.rusage,
};

pub const Lap = struct {
    start: RSnapshot,
    end: RSnapshot,

    fn timeval_to_ms(t: std.c.timeval) i64 {
        return @intCast(t.sec * 1000 + @divFloor(t.usec, 1000));
    }

    /// Gets the wall clock time
    pub fn realtime(self: *const Lap) i64 {
        return self.end.timestamp.toMilliseconds() - self.start.timestamp.toMilliseconds();
    }
    /// Gets the time spent in user mode
    pub fn usertime(self: *const Lap) i64 {
        return timeval_to_ms(self.end.ressource.utime) - timeval_to_ms(self.start.ressource.utime);
    }
    /// Gets the time spent in kernel mode
    pub fn systemtime(self: *const Lap) i64 {
        return timeval_to_ms(self.end.ressource.stime) - timeval_to_ms(self.start.ressource.stime);
    }
    /// Gets approximatively the time spent waiting for I/O
    pub fn iotime(self: *const Lap) i64 {
        return self.realtime() - self.usertime() - self.systemtime();
    }
};

pub const e = error{
    InvalidLap,
    GetRUsageError,
};

const Self = @This();

clock: std.Io.Clock,
io: std.Io,
alloctor: std.mem.Allocator,
snapshots: std.ArrayList(RSnapshot),

pub fn init(clock: std.Io.Clock, io: std.Io, allocator: std.mem.Allocator) !Self {
    const resolution = try clock.resolution(io);
    if (resolution.toMilliseconds() != 0) {
        std.log.warn("Clock resolution might be inaccurate, resolution is {}ns", .{resolution.toNanoseconds()});
    }
    return .{
        .clock = clock,
        .io = io,
        .alloctor = allocator,
        .snapshots = try std.ArrayList(RSnapshot).initCapacity(allocator, 2),
    };
}
pub fn deinit(self: *Self) void {
    self.snapshots.deinit(self.alloctor);
}

pub fn take_snapshot(self: *Self) !void {
    const ts = self.clock.now(self.io);
    var ru: std.c.rusage = undefined;
    if (std.c.getrusage(std.c.rusage.SELF, &ru) != 0) {
        return e.GetRUsageError;
    }
    try self.snapshots.append(self.alloctor, .{
        .timestamp = ts,
        .ressource = ru,
    });
}

pub fn get_lap(self: *const Self, n: usize) !Lap {
    if (self.snapshots.items.len <= n + 1) {
        return e.InvalidLap;
    }
    return .{
        .start = self.snapshots.items[n],
        .end = self.snapshots.items[n + 1],
    };
}

pub fn last_lap(self: *const Self) !Lap {
    return self.get_lap(self.snapshots.items.len - 2);
}
