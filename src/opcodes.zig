const std = @import("std");
const gb_mod = @import("cpu.zig");

const FLAG_ZERO: u8 = 0b10000000;
const FLAG_SUB: u8 = 0b01000000;
const FLAG_HC: u8 = 0b00100000;
const FLAG_CARRY: u8 = 0b00010000;

pub fn nop(gb: *gb_mod.GameBoy) void {
    gb.cpu.pc += 1;
}

// load val to registers
pub fn ldsp(gb: *gb_mod.GameBoy) void {
    gb.cpu.sp = gb.readu16(gb.cpu.pc + 1);
    gb.cpu.pc += 3;
}

pub fn lda(gb: *gb_mod.GameBoy) void {
    gb.cpu.a = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn ldb(gb: *gb_mod.GameBoy) void {
    gb.cpu.b = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn ldc(gb: *gb_mod.GameBoy) void {
    gb.cpu.c = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn ldd(gb: *gb_mod.GameBoy) void {
    gb.cpu.d = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn lde(gb: *gb_mod.GameBoy) void {
    gb.cpu.e = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn ldh(gb: *gb_mod.GameBoy) void {
    gb.cpu.h = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

pub fn ldl(gb: *gb_mod.GameBoy) void {
    gb.cpu.l = gb.readByte(gb.cpu.pc + 1);
    gb.cpu.pc += 2;
}

// load val to register pair
pub fn ldbc(gb: *gb_mod.GameBoy) void {
    const value: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.cpu.set_bc(value);
    gb.cpu.pc += 3;
}

pub fn ldde(gb: *gb_mod.GameBoy) void {
    const value: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.cpu.set_de(value);
    gb.cpu.pc += 3;
}

pub fn ldhl(gb: *gb_mod.GameBoy) void {
    const value: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.cpu.set_hl(value);
    gb.cpu.pc += 3;
}

// LD and increase/decrease hl
pub fn lda_hlp(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_hl();
    gb.cpu.a = gb.readByte(address);
    gb.cpu.set_hl(address +% 1);
    gb.cpu.pc += 1;
}

pub fn lda_hlm(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_hl();
    gb.cpu.a = gb.readByte(address);
    gb.cpu.set_hl(address -% 1);
    gb.cpu.pc += 1;
}

// load reg to memory
pub fn loadmem_a(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.writeByte(address, gb.cpu.a);
    gb.cpu.pc += 3;
}

// load val to memory
pub fn loadmem_ffval(gb: *gb_mod.GameBoy) void {
    const offset: u8 = gb.readByte(gb.cpu.pc + 1);
    const address: u16 = 0xFF00 + @as(u16, offset);
    gb.writeByte(address, gb.cpu.a);
    gb.cpu.pc += 2;
}

pub fn incmem_hl(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_hl();
    const old_value: u8 = gb.readByte(address);
    const new_value: u8 = old_value +% 1;
    gb.writeByte(address, new_value);

    // flags
    gb.cpu.unset_flag(FLAG_SUB);
    if (new_value == 0) {
        gb.cpu.set_flag(FLAG_ZERO);
    } else {
        gb.cpu.unset_flag(FLAG_ZERO);
    }
    if ((old_value & 0x0F) == 0x0F) {
        gb.cpu.set_flag(FLAG_HC);
    } else {
        gb.cpu.unset_flag(FLAG_HC);
    }
    gb.cpu.pc += 1;
}

// sp stuff
pub fn dec_sp(gb: *gb_mod.GameBoy) void {
    gb.cpu.sp -%= 1;
}

pub fn inc_sp(gb: *gb_mod.GameBoy) void {
    gb.cpu.sp +%= 1;
}

// jumps
pub fn jr(gb: *gb_mod.GameBoy) void {
    const pc: i16 = @intCast(gb.cpu.pc);
    const offset: i16 = @intCast(@as(i8, @bitCast(gb.readByte(gb.cpu.pc + 1))));
    gb.cpu.pc = @intCast(pc + 2 + offset);
}

pub fn jp(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.cpu.pc = address;
}

pub fn di(gb: *gb_mod.GameBoy) void {
    gb.cpu.ime = false;
    gb.cpu.pc += 1;
}

// call/ret
pub fn call(gb: *gb_mod.GameBoy) void {
    const jump: u16 = gb.readu16(gb.cpu.pc + 1);
    gb.push_u16(gb.cpu.pc + 3);
    gb.cpu.pc = jump;
}

pub fn ret(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.pop_u16();
    gb.cpu.pc = address;
}
