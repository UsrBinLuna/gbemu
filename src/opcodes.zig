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

pub fn ldhlp_a(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_hl();
    gb.writeByte(address, gb.cpu.a);
    gb.cpu.set_hl(address +% 1);
    gb.cpu.pc += 1;
}

pub fn ldhlm_a(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_hl();
    gb.writeByte(address, gb.cpu.a);
    gb.cpu.set_hl(address -% 1);
    gb.cpu.pc += 1;
}

pub fn lda_ffu8(gb: *gb_mod.GameBoy) void {
    const offset: u8 = gb.readByte(gb.cpu.pc + 1);
    const address: u16 = 0xFF00 + @as(u16, offset);
    const value: u8 = gb.readByte(address);
    gb.cpu.a = value;
    gb.cpu.pc += 2;
}

pub fn lda_u16(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.readu16(gb.cpu.pc + 1);
    const value: u8 = gb.readByte(address);
    gb.cpu.a = value;
    gb.cpu.pc += 3;
}

pub fn lda_bc(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_bc();
    const value: u8 = gb.readByte(address);
    gb.cpu.a = value;
    gb.cpu.pc += 1;
}

pub fn lda_de(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.cpu.get_de();
    const value: u8 = gb.readByte(address);
    gb.cpu.a = value;
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

pub fn ldu16_sp(gb: *gb_mod.GameBoy) void {
    const address: u16 = gb.readu16(gb.cpu.pc + 1);
    const high: u8 = @intCast(gb.cpu.sp >> 8);
    const low: u8 = @intCast(gb.cpu.sp & 0xFF);
    gb.writeByte(address, low);
    gb.writeByte(address + 1, high);
    gb.cpu.pc += 3;
}

// more (hl) things
pub fn inc_hl(gb: *gb_mod.GameBoy) void {
    const addr: u16 = gb.cpu.get_hl();
    const old: u8 = gb.readByte(addr);
    const value: u8 = old +% 1;
    gb.writeByte(addr, value);

    // flags
    gb.cpu.unset_flag(FLAG_SUB);
    if (value == 0) {
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

pub fn dec_hl(gb: *gb_mod.GameBoy) void {
    const addr: u16 = gb.cpu.get_hl();
    const old: u8 = gb.readByte(addr);
    const value: u8 = old -% 1;
    gb.writeByte(addr, value);

    // flags
    gb.cpu.set_flag(FLAG_SUB);
    if (value == 0) {
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

pub fn addhl_sp(gb: *gb_mod.GameBoy) void {
    const hl: u16 = gb.cpu.get_hl();

    if (@as(u32, hl) + @as(u32, gb.cpu.sp) > 0xFFFF) {
        gb.cpu.set_flag(FLAG_CARRY);
    } else {
        gb.cpu.unset_flag(FLAG_CARRY);
    }

    if ((hl & 0x0FFF) + (gb.cpu.sp & 0x0FFF) > 0x0FFF) {
        gb.cpu.set_flag(FLAG_HC);
    } else {
        gb.cpu.unset_flag(FLAG_HC);
    }

    // flags
    gb.cpu.unset_flag(FLAG_SUB);

    gb.cpu.set_hl(hl +% gb.cpu.sp);
    gb.cpu.pc += 1;
}

pub fn jp_hl(gb: *gb_mod.GameBoy) void {
    gb.cpu.pc = gb.cpu.get_hl();
}

pub fn ldhl_spi8(gb: *gb_mod.GameBoy) void {
    const raw_offset = gb.readByte(gb.cpu.pc + 1);
    const offset: u16 = @bitCast(@as(i16, @as(i8, @bitCast(raw_offset))));
    const result: u16 = gb.cpu.sp +% offset;

    if ((gb.cpu.sp & 0x0F) + (raw_offset & 0x0F) > 0x0F) {
        gb.cpu.set_flag(FLAG_HC);
    } else {
        gb.cpu.unset_flag(FLAG_HC);
    }

    if ((gb.cpu.sp & 0xFF) + raw_offset > 0xFF) {
        gb.cpu.set_flag(FLAG_CARRY);
    } else {
        gb.cpu.unset_flag(FLAG_CARRY);
    }
    gb.cpu.unset_flag(FLAG_ZERO);
    gb.cpu.unset_flag(FLAG_SUB);

    gb.cpu.set_hl(result);
    gb.cpu.pc += 2;
}

// more loads that arent enough to deserve their own generator
pub fn ldaddr_bc(gb: *gb_mod.GameBoy) void {
    const addr: u16 = gb.cpu.get_bc();
    gb.writeByte(addr, gb.cpu.a);
    gb.cpu.pc += 1;
}

pub fn ldaddr_de(gb: *gb_mod.GameBoy) void {
    const addr: u16 = gb.cpu.get_de();
    gb.writeByte(addr, gb.cpu.a);
    gb.cpu.pc += 1;
}

// sp stuff
pub fn dec_sp(gb: *gb_mod.GameBoy) void {
    gb.cpu.sp -%= 1;
}

pub fn inc_sp(gb: *gb_mod.GameBoy) void {
    gb.cpu.sp +%= 1;
}

// rotations
pub fn rlca(gb: *gb_mod.GameBoy) void {
    const old: u8 = gb.cpu.a >> 7;
    gb.cpu.a <<= 1;
    gb.cpu.a |= old;

    if (old == 0) {
        gb.cpu.unset_flag(FLAG_CARRY);
    } else {
        gb.cpu.set_flag(FLAG_CARRY);
    }

    if (gb.cpu.a == 0) {
        gb.cpu.set_flag(FLAG_ZERO);
    } else {
        gb.cpu.unset_flag(FLAG_ZERO);
    }
    gb.cpu.unset_flag(FLAG_SUB);
    gb.cpu.unset_flag(FLAG_HC);
    gb.cpu.pc += 1;
}

pub fn rla(gb: *gb_mod.GameBoy) void {
    const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
    const old: u8 = gb.cpu.a >> 7;
    gb.cpu.a <<= 1;
    gb.cpu.a |= flag_bit;
    if (old == 1) {
        gb.cpu.set_flag(FLAG_CARRY);
    } else {
        gb.cpu.unset_flag(FLAG_CARRY);
    }
    if (gb.cpu.a == 0) {
        gb.cpu.set_flag(FLAG_ZERO);
    } else {
        gb.cpu.unset_flag(FLAG_ZERO);
    }
    gb.cpu.unset_flag(FLAG_SUB);
    gb.cpu.unset_flag(FLAG_HC);
    gb.cpu.pc += 1;
}

pub fn rrca(gb: *gb_mod.GameBoy) void {
    const old: u8 = gb.cpu.a & 0b1;
    gb.cpu.a >>= 1;
    gb.cpu.a |= (old << 7);

    if (old == 0) {
        gb.cpu.unset_flag(FLAG_CARRY);
    } else {
        gb.cpu.set_flag(FLAG_CARRY);
    }

    if (gb.cpu.a == 0) {
        gb.cpu.set_flag(FLAG_ZERO);
    } else {
        gb.cpu.unset_flag(FLAG_ZERO);
    }
    gb.cpu.unset_flag(FLAG_SUB);
    gb.cpu.unset_flag(FLAG_HC);
    gb.cpu.pc += 1;
}

pub fn rra(gb: *gb_mod.GameBoy) void {
    const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
    const old: u8 = gb.cpu.a & 0b1;
    gb.cpu.a >>= 1;
    gb.cpu.a |= (flag_bit << 7);
    if (old == 1) {
        gb.cpu.set_flag(FLAG_CARRY);
    } else {
        gb.cpu.unset_flag(FLAG_CARRY);
    }
    if (gb.cpu.a == 0) {
        gb.cpu.set_flag(FLAG_ZERO);
    } else {
        gb.cpu.unset_flag(FLAG_ZERO);
    }
    gb.cpu.unset_flag(FLAG_SUB);
    gb.cpu.unset_flag(FLAG_HC);
    gb.cpu.pc += 1;
}

// what in the WORLD
pub fn daa(gb: *gb_mod.GameBoy) void {
    const sub_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_SUB) != 0);
    const half_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_HC) != 0);
    const carry_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
    var modify: u8 = 0;

    if (sub_bit == 0) { // addition
        if ((gb.cpu.a & 0x0F) > 0x9 or half_bit != 0) {
            modify += 0x06;
        }
        if (gb.cpu.a > 0x99 or carry_bit != 0) {
            modify += 0x60;
            gb.cpu.set_flag(FLAG_CARRY);
        }
        gb.cpu.a +%= modify;
    } else { // subtraction
        if (half_bit != 0) {
            modify += 0x06;
        }
        if (carry_bit != 0) {
            modify += 0x60;
        }
        gb.cpu.a -%= modify;
    }

    if (gb.cpu.a == 0) gb.cpu.set_flag(FLAG_ZERO) else gb.cpu.unset_flag(FLAG_ZERO);
    gb.cpu.unset_flag(FLAG_HC);
}

// jumps
pub fn jr(gb: *gb_mod.GameBoy) void {
    const offset: i16 = @intCast(@as(i8, @bitCast(gb.readByte(gb.cpu.pc + 1))));
    const next_pc: i32 = @as(i32, gb.cpu.pc) + 2 + offset; // i32 conversion important so theres no overflow
    gb.cpu.pc = @truncate(@as(u32, @bitCast(next_pc))); // truncate back to u16
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
