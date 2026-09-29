const std = @import("std");
const Library = @import("library");

const RStopwatch = @import("rstopwatch.zig");
const BenchStats = @import("main.zig").BenchStats;

const ITERATIONS = 4;

pub const ChangerBenchmark = struct {
    iterations: u32,
    n_drives: u32,
    n_slots: u32,
    loads: std.ArrayList(std.ArrayList(BenchStats)),
    stores: std.ArrayList(std.ArrayList(BenchStats)),
    moves: std.ArrayList(std.ArrayList(BenchStats)),
};

const Laps = [ITERATIONS]RStopwatch.Lap;

pub fn benchmark_changer(library: Library, allocator: std.mem.Allocator) !ChangerBenchmark {
    // var loads = try std.ArrayList(std.ArrayList(Laps)).initCapacity(allocator, library.changer.n_slots);
    var stores = try std.ArrayList(std.ArrayList(Laps)).initCapacity(allocator, library.changer.n_drives);
    // var moves = try std.ArrayList(std.ArrayList(Laps)).initCapacity(allocator, library.changer.n_slots);

    for (0..library.changer.n_drives) |d| {
        try stores.append(allocator, try std.ArrayList(Laps).initCapacity(allocator, library.changer.n_slots));
        try stores.items[d].expandToCapacity();
    }
}
