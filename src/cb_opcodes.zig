const std = @import("std");
const gb_mod = @import("cpu.zig");

const FLAG_ZERO: u8 = 0b10000000;
const FLAG_SUB: u8 = 0b01000000;
const FLAG_HC: u8 = 0b00100000;
const FLAG_CARRY: u8 = 0b00010000;

fn getRegister(gb: *gb_mod.GameBoy, reg: u3) *u8 {
    return switch (reg) {
        0b000 => &gb.cpu.b,
        0b001 => &gb.cpu.c,
        0b010 => &gb.cpu.d,
        0b011 => &gb.cpu.e,
        0b100 => &gb.cpu.h,
        0b101 => &gb.cpu.l,
        0b111 => &gb.cpu.a,
        0b110 => unreachable,
    };
}

pub fn cbOpcodes(gb: *gb_mod.GameBoy) void {
    //std.debug.print("Fetched CB opcode: 0x{X:0>2}\n", .{gb.readByte(gb.cpu.pc + 1)});
    // get prefix for BIT, RES, SET
    const op: u8 = gb.readByte(gb.cpu.pc + 1);

    const pre: u8 = op >> 6; // 0b11000000
    const operator: u3 = @truncate((op >> 3) & 0b111); // 0b00111000
    const idx: u3 = @truncate(op & 0b111); // 0b00000111
    if (idx == 0b110) {
        const addr = gb.cpu.get_hl();
        var value: u8 = gb.readByte(addr);

        if (pre == 0b01) {
            const mask: u8 = @as(u8, 1) << operator;
            const res: u8 = (value & mask);
            if (res == 0) { // BIT
                gb.cpu.set_flag(FLAG_ZERO);
            } else {
                gb.cpu.unset_flag(FLAG_ZERO);
            }
            gb.cpu.unset_flag(FLAG_SUB);
            gb.cpu.set_flag(FLAG_HC);
        } else if (pre == 0b10) {
            const mask: u8 = @as(u8, 1) << operator;
            value &= ~mask;
            gb.writeByte(addr, value);
        } else if (pre == 0b11) {
            const mask: u8 = @as(u8, 1) << operator;
            value |= mask;
            gb.writeByte(addr, value);
        } else {
            switch (operator) {
                0b000 => { // RLC
                    const old: u8 = value >> 7;
                    value <<= 1;
                    value |= old;
                    gb.writeByte(addr, value);

                    if (old == 0) {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.set_flag(FLAG_CARRY);
                    }

                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b001 => { // RRC
                    const old: u8 = value & 0b1;
                    value >>= 1;
                    value |= (old << 7);
                    gb.writeByte(addr, value);

                    if (old == 0) {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.set_flag(FLAG_CARRY);
                    }

                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b010 => { // RL
                    const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
                    const old: u8 = value >> 7;
                    value <<= 1;
                    value |= flag_bit;
                    gb.writeByte(addr, value);
                    if (old == 1) {
                        gb.cpu.set_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    }
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b011 => { // RR
                    const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
                    const old: u8 = value & 0b1;
                    value >>= 1;
                    value |= (flag_bit << 7);
                    gb.writeByte(addr, value);
                    if (old == 1) {
                        gb.cpu.set_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    }
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b100 => { // SLA
                    const old: u8 = value >> 7;
                    value <<= 1;
                    gb.writeByte(addr, value);
                    if (old == 1) {
                        gb.cpu.set_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    }
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b101 => { // SRA
                    const old: u8 = value & 0b1;
                    const old_bit7: u8 = value & 0b10000000;
                    value >>= 1;
                    value |= old_bit7;
                    gb.writeByte(addr, value);
                    if (old == 1) {
                        gb.cpu.set_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    }
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_SUB);
                    gb.cpu.unset_flag(FLAG_HC);
                },
                0b110 => { // SWAP
                    const high: u8 = ((value & 0b11110000) >> 4);
                    const low: u8 = ((value & 0b00001111) << 4);
                    value = low | high;
                    gb.writeByte(addr, value);
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    gb.cpu.unset_flag(FLAG_CARRY);
                    gb.cpu.unset_flag(FLAG_HC);
                    gb.cpu.unset_flag(FLAG_SUB);
                },
                0b111 => { // SRL
                    const old: u8 = value & 0b1;
                    value >>= 1;
                    gb.writeByte(addr, value);
                    if (value == 0) {
                        gb.cpu.set_flag(FLAG_ZERO);
                    } else {
                        gb.cpu.unset_flag(FLAG_ZERO);
                    }
                    if (old == 0) {
                        gb.cpu.unset_flag(FLAG_CARRY);
                    } else {
                        gb.cpu.set_flag(FLAG_CARRY);
                    }
                    gb.cpu.unset_flag(FLAG_HC);
                    gb.cpu.unset_flag(FLAG_SUB);
                },
            }
        }
        gb.cpu.pc += 2;
        return;
    }
    const reg = getRegister(gb, idx);

    if (pre == 0b01) {
        const mask: u8 = @as(u8, 1) << operator;
        const res: u8 = (reg.* & mask);
        if (res == 0) { // BIT
            gb.cpu.set_flag(FLAG_ZERO);
        } else {
            gb.cpu.unset_flag(FLAG_ZERO);
        }
        gb.cpu.unset_flag(FLAG_SUB);
        gb.cpu.set_flag(FLAG_HC);
    } else if (pre == 0b10) {
        const mask: u8 = @as(u8, 1) << operator;
        reg.* &= ~mask;
    } else if (pre == 0b11) {
        const mask: u8 = @as(u8, 1) << operator;
        reg.* |= mask;
    } else {
        switch (operator) {
            0b000 => { // RLC
                const old: u8 = reg.* >> 7;
                reg.* <<= 1;
                reg.* |= old;

                if (old == 0) {
                    gb.cpu.unset_flag(FLAG_CARRY);
                } else {
                    gb.cpu.set_flag(FLAG_CARRY);
                }

                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b001 => { // RRC
                const old: u8 = reg.* & 0b1;
                reg.* >>= 1;
                reg.* |= (old << 7);

                if (old == 0) {
                    gb.cpu.unset_flag(FLAG_CARRY);
                } else {
                    gb.cpu.set_flag(FLAG_CARRY);
                }

                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b010 => { // RL
                const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
                const old: u8 = reg.* >> 7;
                reg.* <<= 1;
                reg.* |= flag_bit;
                if (old == 1) {
                    gb.cpu.set_flag(FLAG_CARRY);
                } else {
                    gb.cpu.unset_flag(FLAG_CARRY);
                }
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b011 => { // RR
                const flag_bit: u8 = @intFromBool(gb.cpu.get_flag(FLAG_CARRY) != 0);
                const old: u8 = reg.* & 0b1;
                reg.* >>= 1;
                reg.* |= (flag_bit << 7);
                if (old == 1) {
                    gb.cpu.set_flag(FLAG_CARRY);
                } else {
                    gb.cpu.unset_flag(FLAG_CARRY);
                }
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b100 => { // SLA
                const old: u8 = reg.* >> 7;
                reg.* <<= 1;
                if (old == 1) {
                    gb.cpu.set_flag(FLAG_CARRY);
                } else {
                    gb.cpu.unset_flag(FLAG_CARRY);
                }
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b101 => { // SRA
                const old: u8 = reg.* & 0b1;
                const old_bit7: u8 = reg.* & 0b10000000;
                reg.* >>= 1;
                reg.* |= old_bit7;
                if (old == 1) {
                    gb.cpu.set_flag(FLAG_CARRY);
                } else {
                    gb.cpu.unset_flag(FLAG_CARRY);
                }
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_SUB);
                gb.cpu.unset_flag(FLAG_HC);
            },
            0b110 => { // SWAP
                const high: u8 = ((reg.* & 0b11110000) >> 4);
                const low: u8 = ((reg.* & 0b00001111) << 4);
                reg.* = low | high;
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                gb.cpu.unset_flag(FLAG_CARRY);
                gb.cpu.unset_flag(FLAG_HC);
                gb.cpu.unset_flag(FLAG_SUB);
            },
            0b111 => { // SRL
                const old: u8 = reg.* & 0b1;
                reg.* >>= 1;
                if (reg.* == 0) {
                    gb.cpu.set_flag(FLAG_ZERO);
                } else {
                    gb.cpu.unset_flag(FLAG_ZERO);
                }
                if (old == 0) {
                    gb.cpu.unset_flag(FLAG_CARRY);
                } else {
                    gb.cpu.set_flag(FLAG_CARRY);
                }
                gb.cpu.unset_flag(FLAG_HC);
                gb.cpu.unset_flag(FLAG_SUB);
            },
        }
    }
    gb.cpu.pc += 2;
}
