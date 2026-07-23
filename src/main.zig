const std = @import("std");
const gb = @import("cpu.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    const io = init.io;
    const minimal = init.minimal;

    const cwd = std.Io.Dir.cwd();

    const args = try minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.debug.print("Usage: {s} <argument>\n", .{args[0]});
        return;
    }

    const rom = try std.Io.Dir.readFileAlloc(cwd, io, args[1], alloc, .unlimited);
    defer alloc.free(rom);

    std.debug.print("ROM Size: {} bytes\n", .{rom.len});

    try gb.main(rom);
}
