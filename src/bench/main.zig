const std = @import("std");
const Library = @import("library");
const Changer = Library.Changer;
const Drive = Library.Drive;

const RStopwatch = @import("rstopwatch.zig");
const changer_benchmark = @import("changer_benchmark.zig");

pub const BenchStats = struct {
    avg: f32,
    stddev: f32,
};

fn help(cmd: []const u8, stdout: *std.Io.Writer) !void {
    try stdout.print("Usage :\n" ++
        "{s} <changer> <drives>...\n", .{cmd});
}

pub fn main(init: std.process.Init) !u8 {
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_file_writer.interface;

    const argv = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(argv);

    if (argv.len < 3) {
        try help(argv[0], stdout);
        return 1;
    }

    var drive_files = try std.ArrayList([]const u8).initCapacity(init.gpa, argv.len - 2);
    for (2..argv.len) |i| {
        try drive_files.append(init.gpa, argv[i]);
    }
    defer drive_files.deinit(init.gpa);

    var library = try Library.init(argv[1], drive_files.items, init.io, init.gpa);
    defer library.deinit();

    std.log.debug("Starting benchmarks", .{});

    var stats = try changer_benchmark.benchmark_changer(&library, init.gpa, init.io);
    defer stats.loads.deinit(init.gpa);
    defer stats.stores.deinit(init.gpa);
    defer stats.moves.deinit(init.gpa);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(init.io, "bench", std.Io.File.Permissions.default_dir) catch {
        std.log.warn("Benchmark directory already exists, overwriting...", .{});
    };
    try stats.save(try cwd.openDir(init.io, "bench", .{}), init.io);

    return 0;
}
