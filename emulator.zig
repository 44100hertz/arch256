const std = @import("std");
const expect = std.testing.expect;
const print = std.debug.print;

const memsize = 1 << 16;
const word = u16;

// Instruction layout:
// __LL _DSS IIII IIII
//   L = number of args 0-3
//   D = Whether to write result to an address (1) or not (0)
//   S = Whether to read input(s) from an address (1) or immediate (0)
//   I = Which of 256 instructions to perform in between.

const Instruction = packed struct {
    operation: Operation,
    read_addr1: bool,
    read_addr0: bool,
    write_addr: bool,
    _pad0: bool,
    argc: u2,
    _pad1: u2,
};

test "Instruction is 16-bit" {
    try expect(@sizeOf(Instruction) == 2);
}

const Operation = enum(u8) {
    none,
    copy,
    add,
    jump_if_zero,
    poke,
    halt,
};

const Cpu = struct {
    pc: word,
    reg_in: [2]word,
    reg_out: word,
    memory: *[memsize]word,
    allocator: std.mem.Allocator,
    halted: bool,

    pub fn init() !Cpu {
        var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var alloc = aa.allocator();
        return std.mem.zeroInit(Cpu, .{
            .allocator = alloc,
            .memory = try alloc.create([memsize]word),
            .halted = false,
        });
    }

    pub fn free(self: Cpu) void {
        self.allocator.destroy(self.memory);
    }

    pub fn fetch_next(self: *Cpu) word {
        const out = self.memory[self.pc];
        self.pc +%= 1;
        return out;
    }

    pub fn step(self: *Cpu) void {
        const debug = false;
        // Fetch
        const ix: Instruction = @bitCast(self.fetch_next());
        if (debug) print("instruction {b:0>8} {x:0>2}; ", .{@as(word, @bitCast(ix)) >> 8, @intFromEnum(ix.operation)});
        var write_addr: word = undefined;
        if (ix.write_addr) write_addr = self.fetch_next();
        for (0..ix.argc) |i| {
            self.reg_in[i] = self.fetch_next();
            if (debug) print("param {x:0>4}; ", .{self.reg_in[i]});
        }
        if (debug) print("\n", .{});

        // Read memory
        for (0..2) |i| {
            const memflag = if (i == 0) ix.read_addr0 else ix.read_addr1;
            if (memflag) {
                const addr = self.reg_in[i];
                self.reg_in[i] = self.memory[addr];
                if (debug) print("read {x:0>4} from {x:0>4}\n", .{self.reg_in[i], addr});
            }
        }

        // Perform operation
        switch (ix.operation) {
            Operation.none => {},
            Operation.copy => self.reg_out = self.reg_in[0],
            Operation.add => self.reg_out = self.reg_in[0] + self.reg_in[1],
            Operation.jump_if_zero => { if (self.reg_in[1] == 0) self.pc = self.reg_in[0]; },
            Operation.poke => print("{u}", .{self.reg_in[1]}),
            Operation.halt => self.halted = true,
        }

        // Writeback
        if (ix.write_addr) {
            self.memory[write_addr] = self.reg_out;
            if (debug) print("wrote {x:0>4} to {x:0>4}\n", .{self.reg_out, write_addr});
        }
    }

    pub fn run(self: *Cpu) void {
        for (1..100) |_| {
            self.step();
            if (self.halted) break;
        }
    }
};

// From C "assembler"...
const hello_binary = [_]word{
    0x0048, 0x0065, 0x006c, 0x006c, 0x006f, 0x002c, 0x0020, 0x0077, 0x006f,
    0x0072, 0x006c, 0x0064, 0x0021, 0x000a, 0x0000, 0x1401, 0x007f, 0x0000,
    0x1200, 0x007f, 0x0601, 0x0080, 0x2502, 0x007f, 0x0001, 0x007f, 0x2104,
    0x0000, 0x0080, 0x1003, 0x0021, 0x2003, 0x0011, 0x0000, 0x0005
};

const hello_start = 15;

pub fn main() !void {
    var cpu = try Cpu.init();
    defer cpu.free();
    for (hello_binary, 0..) |w, i| cpu.memory[i] = w;
    cpu.pc = hello_start;
    cpu.run();
}
