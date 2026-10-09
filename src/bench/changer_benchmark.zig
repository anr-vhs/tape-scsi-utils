const std = @import("std");
const tapelib = @import("library");
const Library = tapelib.Library;
const Changer = tapelib.Changer;

const RStopwatch = @import("rstopwatch.zig");
const BenchStats = @import("main.zig").BenchStats;
const NDArray = @import("utils.zig").NDArray;

const array_to_csv = @import("utils.zig").array_to_csv;

const ITERATIONS = 4;

pub const ChangerBenchmark = struct {
    iterations: u32,
    n_drives: u32,
    n_slots: u32,
    loads: NDArray(2, BenchStats),
    stores: NDArray(2, BenchStats),
    moves: NDArray(2, BenchStats),

    pub fn save(self: *@This(), dir: std.Io.Dir, io: std.Io) !void {
        var buffer: [256]u8 = undefined;
        var meta = try dir.createFile(io, "meta.toml", .{});
        defer meta.close(io);
        var loads = try dir.createFile(io, "loads.csv", .{});
        defer loads.close(io);
        var stores = try dir.createFile(io, "stores.csv", .{});
        defer stores.close(io);
        var moves = try dir.createFile(io, "moves.csv", .{});
        defer moves.close(io);

        var meta_writer = meta.writerStreaming(io, &buffer);
        const w = &meta_writer.interface;
        try w.print("iterations = {}\n" ++
            "n_drives = {}\n" ++
            "n_slots = {}", .{ self.iterations, self.n_drives, self.n_slots });
        try w.flush();

        try array_to_csv(self.loads, loads, io);
        try array_to_csv(self.stores, stores, io);
        try array_to_csv(self.moves, moves, io);
    }
};

fn do_stats(laps: [ITERATIONS]RStopwatch.Lap) BenchStats {
    var avg: f32 = 0.0;
    var total_dev: f32 = 0.0;
    for (0..ITERATIONS) |i| {
        avg += @floatFromInt(laps[i].iotime());
    }
    avg /= ITERATIONS;
    for (0..ITERATIONS) |i| {
        const tmp = avg - @as(f32, @floatFromInt(laps[i].iotime()));
        total_dev += tmp * tmp;
    }
    const variance = total_dev / ITERATIONS;
    return .{
        .avg = avg,
        .stddev = @sqrt(variance),
    };
}

pub fn benchmark_changer(library: *Library, gpa: std.mem.Allocator, io: std.Io) !ChangerBenchmark {
    var loads = try NDArray(2, BenchStats).init(gpa, .{ library.changer.n_slots, library.changer.n_drives });
    errdefer loads.deinit(gpa);
    var stores = try NDArray(2, BenchStats).init(gpa, .{ library.changer.n_drives, library.changer.n_slots });
    errdefer stores.deinit(gpa);
    var moves = try NDArray(2, BenchStats).init(gpa, .{ library.changer.n_slots, library.changer.n_slots });
    errdefer moves.deinit(gpa);

    var stopwatch = try RStopwatch.init(std.Io.Clock.real, io, gpa);
    defer stopwatch.deinit();

    // Benchmark load and stores
    for (0..library.changer.n_slots) |s| {
        try library.changer.move_arm(Changer.ElementKind.Slot, s);
        if (library.slots.items[s].content == null) {
            const ElementKind = Changer.ElementKind;
            try library.move(ElementKind.Slot, s - 1, ElementKind.Slot, s);
        }
        for (0..library.changer.n_drives) |d| {
            var load_iters: [ITERATIONS]RStopwatch.Lap = undefined;
            var store_iters: [ITERATIONS]RStopwatch.Lap = undefined;
            for (0..ITERATIONS) |i| {
                try stopwatch.take_snapshot();
                try library.load(s, d);
                try stopwatch.take_snapshot();
                load_iters[i] = try stopwatch.last_lap();

                try stopwatch.take_snapshot();
                try library.store(d, s);
                try stopwatch.take_snapshot();
                store_iters[i] = try stopwatch.last_lap();
            }
            loads.get(.{ s, d }).* = do_stats(load_iters);
            stores.get(.{ d, s }).* = do_stats(store_iters);
        }
    }

    // Benchmark arm moves
    for (0..library.changer.n_slots) |s1| {
        try library.changer.move_arm(Changer.ElementKind.Slot, s1);
        for (0..library.changer.n_slots) |s2| {
            var move_iters: [ITERATIONS]RStopwatch.Lap = undefined;
            for (0..ITERATIONS) |i| {
                try stopwatch.take_snapshot();
                try library.changer.move_arm(Changer.ElementKind.Slot, s2);
                try stopwatch.take_snapshot();
                try library.changer.move_arm(Changer.ElementKind.Slot, s1);
                move_iters[i] = try stopwatch.last_lap();
            }
            moves.get(.{ s1, s2 }).* = do_stats(move_iters);
        }
    }

    return .{
        .iterations = ITERATIONS,
        .n_drives = library.changer.n_drives,
        .n_slots = library.changer.n_slots,
        .loads = loads,
        .stores = stores,
        .moves = moves,
    };
}
