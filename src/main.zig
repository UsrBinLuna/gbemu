const std = @import("std");
const gb = @import("cpu.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    const io = init.io;

    const cwd = std.Io.Dir.cwd();

    const rom = try std.Io.Dir.readFileAlloc(cwd, io, "test.gb", alloc, .unlimited);
    defer alloc.free(rom);

    std.debug.print("ROM Size: {} bytes\n", .{rom.len});

    try gb.main(rom);
}
