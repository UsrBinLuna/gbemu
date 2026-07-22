const std = @import("std");
const opcode = @import("opcodes.zig");
const cb = @import("cb_opcodes.zig");

const FLAG_ZERO: u8 = 0b10000000;
const FLAG_SUB: u8 = 0b01000000;
const FLAG_HC: u8 = 0b00100000;
const FLAG_CARRY: u8 = 0b00010000;

const BitOps = enum {
    and_,
    xor_,
    or_,
};

const Conditions = enum { z, c, nz, nc };
const Jumps = enum { jump, relative, call, ret };
const Arithmetic = enum { add, sub, adc, sbc, cp };

pub const CPU = struct {
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,

    // flag register bits
    // 7: zero
    // 6: substraction
    // 5: half carry
    // 4: carry
    f: u8 = 0,

    sp: u16 = 0,
    pc: u16 = 0,
    ime: bool = false,
    ime_queued: u8 = 0,

    stopped: bool = false,

    pub fn get_af(self: CPU) u16 {
        return (@as(u16, self.a) << 8) | @as(u16, self.f);
    }

    pub fn get_bc(self: CPU) u16 {
        return (@as(u16, self.b) << 8) | @as(u16, self.c);
    }

    pub fn get_de(self: CPU) u16 {
        return (@as(u16, self.d) << 8) | @as(u16, self.e);
    }

    pub fn get_hl(self: CPU) u16 {
        return (@as(u16, self.h) << 8) | @as(u16, self.l);
    }

    pub fn set_af(self: *CPU, value: u16) void {
        self.a = @intCast(value >> 8);
        self.f = @intCast(value & 0xF0);
    }

    pub fn set_bc(self: *CPU, value: u16) void {
        self.b = @intCast(value >> 8);
        self.c = @intCast(value & 0xFF);
    }

    pub fn set_de(self: *CPU, value: u16) void {
        self.d = @intCast(value >> 8);
        self.e = @intCast(value & 0xFF);
    }

    pub fn set_hl(self: *CPU, value: u16) void {
        self.h = @intCast(value >> 8);
        self.l = @intCast(value & 0xFF);
    }

    pub fn set_flag(self: *CPU, flag: u8) void {
        self.f = (self.f | flag) & 0xF0;
    }

    pub fn unset_flag(self: *CPU, flag: u8) void {
        self.f = (self.f & ~flag) & 0xF0;
    }

    pub fn get_flag(self: *CPU, flag: u8) u8 {
        return self.f & flag;
    }
};

pub const GameBoy = struct {
    memory: [65536]u8 = std.mem.zeroes([65536]u8),
    cpu: CPU = CPU{},
    rom: []u8,

    // helper functions
    pub fn readByte(self: *GameBoy, address: u16) u8 {
        switch (address) {
            0x0000...0x7FFF => return self.rom[@as(usize, address)],
            else => return self.memory[address],
            // todo: add vram and stuff
        }
    }

    pub fn writeByte(self: *GameBoy, address: u16, value: u8) void {
        // rom banking areas (todo: mbc)
        //std.debug.print("WRITE {x} = {x}\n", .{ address, value });
        if (address < 0x8000) {
            // todo: bank switching
            return;
        }
        self.memory[address] = value;
        if (address == 0xFF02 and value == 0x81) {
            std.debug.print("{c}", .{self.memory[0xFF01]});
            self.memory[0xFF02] = 0;
        }
    }

    pub fn readu16(self: *GameBoy, address: u16) u16 {
        const low = self.readByte(address);
        const high = self.readByte(address + 1);
        return (@as(u16, high) << 8) | low;
    }

    // stack stuff
    pub fn push_u16(self: *GameBoy, value: u16) void {
        const high: u8 = @intCast(value >> 8);
        const low: u8 = @intCast(value & 0xFF);
        self.cpu.sp -= 1;
        self.writeByte(self.cpu.sp, high);
        self.cpu.sp -= 1;
        self.writeByte(self.cpu.sp, low);
    }

    pub fn pop_u16(self: *GameBoy) u16 {
        const low: u8 = self.readByte(self.cpu.sp);
        self.cpu.sp += 1;
        const high: u8 = self.readByte(self.cpu.sp);
        self.cpu.sp += 1;
        const value: u16 = (@as(u16, high) << 8) | low;
        return value;
    }

    const OpcodeFn = *const fn (gb: *GameBoy) void;
    pub const dispatch_table: [256]OpcodeFn = init_dispatch_table();

    // generators
    // LD reg reg
    fn ldGen(comptime dst: []const u8, comptime src: []const u8) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                @field(gb.cpu, dst) = @field(gb.cpu, src);
                gb.cpu.pc += 1;
            }
        }.f;
    }
    // LD reg hl
    fn ldRHLGen(comptime dst: []const u8) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                @field(gb.cpu, dst) = gb.readByte(gb.cpu.get_hl());
                gb.cpu.pc += 1;
            }
        }.f;
    }

    // LD hl reg
    fn ldHLRGen(comptime src: []const u8) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                gb.writeByte(gb.cpu.get_hl(), @field(gb.cpu, src));
                gb.cpu.pc += 1;
            }
        }.f;
    }

    // DEC reg (single)
    fn decGen(comptime dst: []const u8) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const old: u8 = @field(gb.cpu, dst);
                @field(gb.cpu, dst) -%= 1;

                // flags
                gb.cpu.set_flag(FLAG_SUB);
                if (@field(gb.cpu, dst) == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                if ((old & 0x0F) == 0) {
                    gb.cpu.set_flag(FLAG_HC);
                } else {
                    gb.cpu.unset_flag(FLAG_HC);
                }
                gb.cpu.pc += 1;
            }
        }.f;
    }

    // DEC reg (pair)
    fn decGenPair(comptime get: anytype, comptime set: anytype) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value = get(gb.cpu);
                set(&gb.cpu, value -% 1);
                gb.cpu.pc += 1;
            }
        }.f;
    }

    // INC reg (single)
    fn incGen(comptime dst: []const u8) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const old: u8 = @field(gb.cpu, dst);
                @field(gb.cpu, dst) +%= 1;

                // flags
                gb.cpu.unset_flag(FLAG_SUB);
                if (@field(gb.cpu, dst) == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                if ((old & 0x0F) == 0x0F) {
                    gb.cpu.set_flag(FLAG_HC);
                } else {
                    gb.cpu.unset_flag(FLAG_HC);
                }
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn incGenPair(comptime get: anytype, comptime set: anytype) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value = get(gb.cpu);
                set(&gb.cpu, value +% 1);
                gb.cpu.pc += 1;
            }
        }.f;
    }

    // push/pop
    fn pushGen(comptime get: anytype) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value = get(gb.cpu);
                push_u16(gb, value);
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn popGen(comptime set: anytype) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value = pop_u16(gb);
                set(&gb.cpu, value);
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn bitwiseGen(comptime src: []const u8, comptime operation: BitOps) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                switch (operation) {
                    .and_ => {
                        gb.cpu.a &= @field(gb.cpu, src);
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.set_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .xor_ => {
                        gb.cpu.a ^= @field(gb.cpu, src);
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .or_ => {
                        gb.cpu.a |= @field(gb.cpu, src);
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                }
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn bitwiseu8Gen(comptime operation: BitOps) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value: u8 = gb.readByte(gb.cpu.pc + 1);
                switch (operation) {
                    .and_ => {
                        gb.cpu.a &= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.set_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .xor_ => {
                        gb.cpu.a ^= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .or_ => {
                        gb.cpu.a |= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                }
                gb.cpu.pc += 2;
            }
        }.f;
    }

    fn bitwisehlGen(comptime operation: BitOps) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value: u8 = gb.readByte(gb.cpu.get_hl());
                switch (operation) {
                    .and_ => {
                        gb.cpu.a &= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.set_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .xor_ => {
                        gb.cpu.a ^= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                    .or_ => {
                        gb.cpu.a |= value;
                        if (gb.cpu.a == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }
                        gb.cpu.unset_flag(FLAG_HC);
                        gb.cpu.unset_flag(FLAG_SUB);
                        gb.cpu.unset_flag(FLAG_CARRY);
                    },
                }
                gb.cpu.pc += 2;
            }
        }.f;
    }

    fn arithmeticGen(comptime dst: []const u8, comptime src: []const u8, comptime operation: Arithmetic) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                switch (operation) {
                    .add => {
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + @as(u16, @field(gb.cpu, src));
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + (@field(gb.cpu, src) & 0x0F);
                        @field(gb.cpu, dst) +%= @field(gb.cpu, src);

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sub => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (@field(gb.cpu, src) & 0x0F);
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = @field(gb.cpu, src);
                        @field(gb.cpu, dst) -%= @field(gb.cpu, src);

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .adc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + @as(u16, @field(gb.cpu, src)) + @as(u16, carry);
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + (@field(gb.cpu, src) & 0x0F) + carry;
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) +% @field(gb.cpu, src) +% carry;

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sbc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (@field(gb.cpu, src) & 0x0F);
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = @field(gb.cpu, src);
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) -% @field(gb.cpu, src) -% carry;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src + carry) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low + carry) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .cp => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (@field(gb.cpu, src) & 0x0F);
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = @field(gb.cpu, src);
                        const new_value: u8 = @field(gb.cpu, dst) -% @field(gb.cpu, src);

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (new_value == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                }
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn arithmeticu8Gen(comptime dst: []const u8, comptime operation: Arithmetic) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value: u8 = gb.readByte(gb.cpu.pc + 1);
                switch (operation) {
                    .add => {
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + value;
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + ((value) & 0x0F);
                        @field(gb.cpu, dst) +%= value;

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sub => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value) & 0x0F;
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        @field(gb.cpu, dst) -%= value;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .adc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + @as(u16, value) + @as(u16, carry);
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + ((value) & 0x0F) + carry;
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) +% value +% carry;

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sbc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value) & 0x0F;
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) -% value -% carry;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src + carry) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low + carry) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .cp => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value & 0x0F);
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        const new_value: u8 = @field(gb.cpu, dst) -% value;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (new_value == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                }
                gb.cpu.pc += 2;
            }
        }.f;
    }

    fn arithmetichlGen(comptime dst: []const u8, comptime operation: Arithmetic) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const value: u8 = gb.readByte(gb.cpu.get_hl());
                switch (operation) {
                    .add => {
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + value;
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + ((value) & 0x0F);
                        @field(gb.cpu, dst) +%= value;

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sub => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value) & 0x0F;
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        @field(gb.cpu, dst) -%= value;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .adc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const true_sum: u16 = @as(u16, @field(gb.cpu, dst)) + @as(u16, value) + @as(u16, carry);
                        const true_sum_low: u8 = (@field(gb.cpu, dst) & 0x0F) + ((value) & 0x0F) + carry;
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) +% value +% carry;

                        // flags
                        gb.cpu.unset_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (true_sum > 255) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (true_sum_low > 0x0F) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .sbc => {
                        const carry: u8 = (gb.cpu.get_flag(FLAG_CARRY) >> 4) & 1;
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value) & 0x0F;
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        @field(gb.cpu, dst) = @field(gb.cpu, dst) -% value -% carry;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (@field(gb.cpu, dst) == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src + carry) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low + carry) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                    .cp => {
                        const dst_low: u8 = (@field(gb.cpu, dst) & 0x0F);
                        const src_low: u8 = (value & 0x0F);
                        const old_dst = @field(gb.cpu, dst);
                        const old_src = value;
                        const new_value: u8 = @field(gb.cpu, dst) -% value;

                        // flags
                        gb.cpu.set_flag(FLAG_SUB);
                        if (new_value == 0) {
                            gb.cpu.set_flag(FLAG_ZERO);
                        } else {
                            gb.cpu.unset_flag(FLAG_ZERO);
                        }

                        if (old_dst < old_src) {
                            gb.cpu.set_flag(FLAG_CARRY);
                        } else {
                            gb.cpu.unset_flag(FLAG_CARRY);
                        }

                        if (dst_low < src_low) {
                            gb.cpu.set_flag(FLAG_HC);
                        } else {
                            gb.cpu.unset_flag(FLAG_HC);
                        }
                    },
                }
                gb.cpu.pc += 2;
            }
        }.f;
    }

    fn addhlpairGen(comptime get: anytype) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {
                const hl: u16 = gb.cpu.get_hl();
                const val: u16 = get(gb.cpu);

                if (@as(u32, hl) + @as(u32, val) > 0xFFFF) {
                    gb.cpu.set_flag(FLAG_CARRY);
                } else {
                    gb.cpu.unset_flag(FLAG_CARRY);
                }

                if ((hl & 0x0FFF) + (val & 0x0FFF) > 0x0FFF) {
                    gb.cpu.set_flag(FLAG_HC);
                } else {
                    gb.cpu.unset_flag(FLAG_HC);
                }

                // flags
                gb.cpu.unset_flag(FLAG_SUB);

                gb.cpu.set_hl(hl +% val);
                gb.cpu.pc += 1;
            }
        }.f;
    }

    fn conditionalJumpGen(comptime jump: Jumps, comptime condition: Conditions) OpcodeFn {
        return struct {
            fn f(gb: *GameBoy) void {

                // check condition
                var should_jump: bool = false;
                switch (condition) {
                    .z => should_jump = gb.cpu.get_flag(FLAG_ZERO) != 0,
                    .nz => should_jump = gb.cpu.get_flag(FLAG_ZERO) == 0,
                    .c => should_jump = gb.cpu.get_flag(FLAG_CARRY) != 0,
                    .nc => should_jump = gb.cpu.get_flag(FLAG_CARRY) == 0,
                }

                if (!should_jump) {
                    switch (jump) {
                        .jump => {
                            gb.cpu.pc += 3;
                        },
                        .relative => {
                            gb.cpu.pc += 2;
                        },
                        .ret => {
                            gb.cpu.pc += 1;
                        },
                        .call => {
                            gb.cpu.pc += 3;
                        },
                    }
                } else {
                    switch (jump) {
                        .jump => {
                            const address: u16 = gb.readu16(gb.cpu.pc + 1);
                            gb.cpu.pc = address;
                        },
                        .relative => {
                            const offset: i16 = @intCast(@as(i8, @bitCast(gb.readByte(gb.cpu.pc + 1))));
                            const next_pc: i32 = @as(i32, gb.cpu.pc) + 2 + offset; // i32 conversion important so theres no overflow
                            gb.cpu.pc = @truncate(@as(u32, @bitCast(next_pc))); // truncate back to u16
                        },
                        .ret => {
                            const address: u16 = gb.pop_u16();
                            gb.cpu.pc = address;
                        },
                        .call => {
                            const jp: u16 = gb.readu16(gb.cpu.pc + 1);
                            gb.push_u16(gb.cpu.pc + 3);
                            gb.cpu.pc = jp;
                        },
                    }
                }
            }
        }.f;
    }

    // opcode handling
    fn init_dispatch_table() [256]OpcodeFn {
        var table: [256]OpcodeFn = undefined;
        inline for (0..256) |i| {
            table[i] = invalidOpcode;
        }

        table[0x00] = opcode.nop;
        // LD {register}, u8
        table[0x31] = opcode.ldsp;
        table[0x3E] = opcode.lda;
        table[0x06] = opcode.ldb;
        table[0x0E] = opcode.ldc;
        table[0x16] = opcode.ldd;
        table[0x1E] = opcode.lde;
        table[0x26] = opcode.ldh;
        table[0x2E] = opcode.ldl;
        // LD {register pair}, u16
        table[0x01] = opcode.ldbc;
        table[0x11] = opcode.ldde;
        table[0x21] = opcode.ldhl;
        // LD {register pair, A}
        table[0x02] = opcode.ldaddr_bc;
        table[0x12] = opcode.ldaddr_de;
        // LD {address}, {register}
        table[0xE0] = opcode.loadmem_ffval;
        table[0xEA] = opcode.loadmem_a;
        table[0xF0] = opcode.lda_ffu8;
        // LD {register}, {register}
        // dst A
        table[0x78] = ldGen("a", "b");
        table[0x79] = ldGen("a", "c");
        table[0x7A] = ldGen("a", "d");
        table[0x7B] = ldGen("a", "e");
        table[0x7C] = ldGen("a", "h");
        table[0x7D] = ldGen("a", "l");
        table[0x7F] = ldGen("a", "a");
        // dst B
        table[0x40] = ldGen("b", "b");
        table[0x41] = ldGen("b", "c");
        table[0x42] = ldGen("b", "d");
        table[0x43] = ldGen("b", "e");
        table[0x44] = ldGen("b", "h");
        table[0x45] = ldGen("b", "l");
        table[0x47] = ldGen("b", "a");
        // dst C
        table[0x48] = ldGen("c", "b");
        table[0x49] = ldGen("c", "c");
        table[0x4A] = ldGen("c", "d");
        table[0x4B] = ldGen("c", "e");
        table[0x4C] = ldGen("c", "h");
        table[0x4D] = ldGen("c", "l");
        table[0x4F] = ldGen("c", "a");
        // dst D
        table[0x50] = ldGen("d", "b");
        table[0x51] = ldGen("d", "c");
        table[0x52] = ldGen("d", "d");
        table[0x53] = ldGen("d", "e");
        table[0x54] = ldGen("d", "h");
        table[0x55] = ldGen("d", "l");
        table[0x57] = ldGen("d", "a");
        // dst E
        table[0x58] = ldGen("e", "b");
        table[0x59] = ldGen("e", "c");
        table[0x5A] = ldGen("e", "d");
        table[0x5B] = ldGen("e", "e");
        table[0x5C] = ldGen("e", "h");
        table[0x5D] = ldGen("e", "l");
        table[0x5F] = ldGen("e", "a");
        // dst H
        table[0x60] = ldGen("h", "b");
        table[0x61] = ldGen("h", "c");
        table[0x62] = ldGen("h", "d");
        table[0x63] = ldGen("h", "e");
        table[0x64] = ldGen("h", "h");
        table[0x65] = ldGen("h", "l");
        table[0x67] = ldGen("h", "a");
        // dst L
        table[0x68] = ldGen("l", "b");
        table[0x69] = ldGen("l", "c");
        table[0x6A] = ldGen("l", "d");
        table[0x6B] = ldGen("l", "e");
        table[0x6C] = ldGen("l", "h");
        table[0x6D] = ldGen("l", "l");
        table[0x6F] = ldGen("l", "a");
        // LD {register}, address HL
        table[0x46] = ldRHLGen("b");
        table[0x4E] = ldRHLGen("c");
        table[0x56] = ldRHLGen("d");
        table[0x5E] = ldRHLGen("e");
        table[0x66] = ldRHLGen("h");
        table[0x6E] = ldRHLGen("l");
        table[0x7E] = ldRHLGen("a");
        table[0xF9] = opcode.ldsp_hl;
        // LD address HL, {register}
        table[0x70] = ldHLRGen("b");
        table[0x71] = ldHLRGen("c");
        table[0x72] = ldHLRGen("d");
        table[0x73] = ldHLRGen("e");
        table[0x74] = ldHLRGen("h");
        table[0x75] = ldHLRGen("l");
        table[0x77] = ldHLRGen("a");
        // LD A, register pair
        table[0x0A] = opcode.lda_bc;
        table[0x1A] = opcode.lda_de;
        // LD A, address HL+-
        table[0x2A] = opcode.lda_hlp;
        table[0x3A] = opcode.lda_hlm;
        // LD address HL+-, A
        table[0x22] = opcode.ldhlp_a;
        table[0x32] = opcode.ldhlm_a;
        // LD A, address u16
        table[0xFA] = opcode.lda_u16;
        // LD address u16, reg
        table[0x08] = opcode.ldu16_sp;
        // other loads
        table[0xF8] = opcode.ldhl_spi8;
        // PUSH
        table[0xC5] = pushGen(CPU.get_bc);
        table[0xD5] = pushGen(CPU.get_de);
        table[0xE5] = pushGen(CPU.get_hl);
        table[0xF5] = pushGen(CPU.get_af);
        // POP
        table[0xC1] = popGen(CPU.set_bc);
        table[0xD1] = popGen(CPU.set_de);
        table[0xE1] = popGen(CPU.set_hl);
        table[0xF1] = popGen(CPU.set_af);
        // ARITHMETIC
        // ADD
        table[0x80] = arithmeticGen("a", "b", .add);
        table[0x81] = arithmeticGen("a", "c", .add);
        table[0x82] = arithmeticGen("a", "d", .add);
        table[0x83] = arithmeticGen("a", "e", .add);
        table[0x84] = arithmeticGen("a", "h", .add);
        table[0x85] = arithmeticGen("a", "l", .add);
        table[0x86] = arithmetichlGen("a", .add);
        table[0x87] = arithmeticGen("a", "a", .add);
        table[0xC6] = arithmeticu8Gen("a", .add);
        // ADD HL pairs
        table[0x09] = addhlpairGen(CPU.get_bc);
        table[0x19] = addhlpairGen(CPU.get_de);
        table[0x29] = addhlpairGen(CPU.get_hl);
        table[0x39] = opcode.addhl_sp;
        // ADC
        table[0x88] = arithmeticGen("a", "b", .adc);
        table[0x89] = arithmeticGen("a", "c", .adc);
        table[0x8A] = arithmeticGen("a", "d", .adc);
        table[0x8B] = arithmeticGen("a", "e", .adc);
        table[0x8C] = arithmeticGen("a", "h", .adc);
        table[0x8D] = arithmeticGen("a", "l", .adc);
        table[0x8E] = arithmetichlGen("a", .adc);
        table[0x8F] = arithmeticGen("a", "a", .adc);
        table[0xCE] = arithmeticu8Gen("a", .adc);
        // SUB
        table[0x90] = arithmeticGen("a", "b", .sub);
        table[0x91] = arithmeticGen("a", "c", .sub);
        table[0x92] = arithmeticGen("a", "d", .sub);
        table[0x93] = arithmeticGen("a", "e", .sub);
        table[0x94] = arithmeticGen("a", "h", .sub);
        table[0x95] = arithmeticGen("a", "l", .sub);
        table[0x96] = arithmetichlGen("a", .sub);
        table[0x97] = arithmeticGen("a", "a", .sub);
        table[0xD6] = arithmeticu8Gen("a", .sub);
        // SBC
        table[0x98] = arithmeticGen("a", "b", .sbc);
        table[0x99] = arithmeticGen("a", "c", .sbc);
        table[0x9A] = arithmeticGen("a", "d", .sbc);
        table[0x9B] = arithmeticGen("a", "e", .sbc);
        table[0x9C] = arithmeticGen("a", "h", .sbc);
        table[0x9D] = arithmeticGen("a", "l", .sbc);
        table[0x9E] = arithmetichlGen("a", .sbc);
        table[0x9F] = arithmeticGen("a", "a", .sbc);
        table[0xDE] = arithmeticu8Gen("a", .sbc);
        // CP
        table[0xB8] = arithmeticGen("a", "b", .cp);
        table[0xB9] = arithmeticGen("a", "c", .cp);
        table[0xBA] = arithmeticGen("a", "d", .cp);
        table[0xBB] = arithmeticGen("a", "e", .cp);
        table[0xBC] = arithmeticGen("a", "h", .cp);
        table[0xBD] = arithmeticGen("a", "l", .cp);
        table[0xBF] = arithmeticGen("a", "a", .cp);
        table[0xFE] = arithmeticu8Gen("a", .cp);
        // INC single
        table[0x04] = incGen("b");
        table[0x0C] = incGen("c");
        table[0x14] = incGen("d");
        table[0x1C] = incGen("e");
        table[0x24] = incGen("h");
        table[0x2C] = incGen("l");
        table[0x34] = opcode.inc_hl;
        table[0x3C] = incGen("a");
        // INC pairs
        table[0x03] = incGenPair(CPU.get_bc, CPU.set_bc);
        table[0x13] = incGenPair(CPU.get_de, CPU.set_de);
        table[0x23] = incGenPair(CPU.get_hl, CPU.set_hl);
        table[0x33] = opcode.inc_sp;
        // DEC single
        table[0x05] = decGen("b");
        table[0x0D] = decGen("c");
        table[0x15] = decGen("d");
        table[0x1D] = decGen("e");
        table[0x25] = decGen("h");
        table[0x2D] = decGen("l");
        table[0x35] = opcode.dec_hl;
        table[0x3D] = decGen("a");
        // DEC pairs
        table[0x0B] = decGenPair(CPU.get_bc, CPU.set_bc);
        table[0x1B] = decGenPair(CPU.get_de, CPU.set_de);
        table[0x2B] = decGenPair(CPU.get_hl, CPU.set_hl);
        table[0x3B] = opcode.dec_sp;
        // bitwise
        table[0xA0] = bitwiseGen("b", .and_);
        table[0xA1] = bitwiseGen("c", .and_);
        table[0xA2] = bitwiseGen("d", .and_);
        table[0xA3] = bitwiseGen("e", .and_);
        table[0xA4] = bitwiseGen("h", .and_);
        table[0xA5] = bitwiseGen("l", .and_);
        table[0xA6] = bitwisehlGen(.and_);
        table[0xA7] = bitwiseGen("a", .and_);
        table[0xA8] = bitwiseGen("b", .xor_);
        table[0xA9] = bitwiseGen("c", .xor_);
        table[0xAA] = bitwiseGen("d", .xor_);
        table[0xAB] = bitwiseGen("e", .xor_);
        table[0xAC] = bitwiseGen("h", .xor_);
        table[0xAD] = bitwiseGen("l", .xor_);
        table[0xAE] = bitwisehlGen(.xor_);
        table[0xAF] = bitwiseGen("a", .xor_);
        table[0xB0] = bitwiseGen("b", .or_);
        table[0xB1] = bitwiseGen("c", .or_);
        table[0xB2] = bitwiseGen("d", .or_);
        table[0xB3] = bitwiseGen("e", .or_);
        table[0xB4] = bitwiseGen("h", .or_);
        table[0xB5] = bitwiseGen("l", .or_);
        table[0xB6] = bitwisehlGen(.or_);
        table[0xB7] = bitwiseGen("a", .or_);
        table[0x2F] = opcode.cpl;
        table[0x3F] = opcode.ccf;
        // BITWISE u8
        table[0xE6] = bitwiseu8Gen(.and_);
        table[0xF6] = bitwiseu8Gen(.or_);
        table[0xEE] = bitwiseu8Gen(.xor_);
        // JP
        table[0x18] = opcode.jr;
        table[0xC3] = opcode.jp;
        table[0xE9] = opcode.jp_hl;
        // conditional jumps
        table[0xCA] = conditionalJumpGen(.jump, .z);
        table[0xC2] = conditionalJumpGen(.jump, .nz);
        table[0xDA] = conditionalJumpGen(.jump, .c);
        table[0xD2] = conditionalJumpGen(.jump, .nc);
        table[0x28] = conditionalJumpGen(.relative, .z);
        table[0x20] = conditionalJumpGen(.relative, .nz);
        table[0x38] = conditionalJumpGen(.relative, .c);
        table[0x30] = conditionalJumpGen(.relative, .nc);
        table[0xCC] = conditionalJumpGen(.call, .z);
        table[0xC4] = conditionalJumpGen(.call, .nz);
        table[0xDC] = conditionalJumpGen(.call, .c);
        table[0xD4] = conditionalJumpGen(.call, .nc);
        table[0xC8] = conditionalJumpGen(.ret, .z);
        table[0xC0] = conditionalJumpGen(.ret, .nz);
        table[0xD8] = conditionalJumpGen(.ret, .c);
        table[0xD0] = conditionalJumpGen(.ret, .nc);
        // interrupts
        table[0xF3] = opcode.di;
        table[0xFB] = opcode.ei;
        // CALLs
        table[0xC9] = opcode.ret;
        table[0xCD] = opcode.call;
        // rotations
        table[0x07] = opcode.rlca;
        table[0x0F] = opcode.rrca;
        table[0x17] = opcode.rla;
        table[0x1F] = opcode.rra;
        // weird arithmetics
        table[0x27] = opcode.daa;
        // gameboy stuff
        table[0x10] = opcode.stop;
        table[0x76] = opcode.halt;

        return table;
    }

    fn invalidOpcode(gb: *GameBoy) void {
        const opcode_value = gb.readByte(gb.cpu.pc);
        std.debug.print("Fetched opcode: 0x{X:0>2}\n", .{opcode_value});
        std.debug.panic("Unimplemented opcode at: 0x{X:04}\n", .{gb.cpu.pc});
    }

    pub fn step(gb: *GameBoy, opcode_value: u8) void {
        if (opcode_value == 0xCB) {
            cb.cbOpcodes(gb);
        } else {
            dispatch_table[opcode_value](gb);
        }

        if (gb.cpu.ime_queued > 0) {
            gb.cpu.ime_queued -= 1;
            if (gb.cpu.ime_queued == 0) {
                gb.cpu.ime = true;
            }
        }
    }
};

pub fn main(rom: []u8) !void {
    var gb = GameBoy{
        .rom = rom,
    };

    // insert cartdrige
    gb.memory[0x0100] = 0x00;
    gb.cpu.pc = 0x0100;
    gb.cpu.sp = 0xFFFe;

    std.debug.print("Game Boy initialized!\n", .{});

    while (!gb.cpu.stopped) {
        //std.debug.print("PC at: 0x{X:0>4}\n", .{gb.cpu.pc});

        const opcode_value = gb.readByte(gb.cpu.pc);
        //std.debug.print("Fetched opcode: 0x{X:0>2}\n", .{opcode_value});
        gb.step(opcode_value);
    }
}
