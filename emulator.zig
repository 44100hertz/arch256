const std = @import("std");
const expect = std.testing.expect;
const print = std.debug.print;

const debug = false;
const max_run_len = 100;

const memsize = 1 << 8;
const Word = u8;
const SWord = i8;

// Instruction layout:
// IIiii SAA
// I = Instruction kind
// i = Instruction
// S = self-modify / zero flag
// A = dereference args

const Instruction = packed struct {
    deref1: bool,
    deref0: bool,
    self_modify: bool,
    operation: Operation,

    pub fn argc(self: Instruction) u2 {
        const num_args: u2 = switch (self.operation.kind()) {
            .one_arg => 1,
            .two_arg, .unary => 2,
            .binary => 3,
        };
        return num_args - @intFromBool(self.self_modify);
    }

    pub fn print_info(self: Instruction) void {
        print("op:{s} d0:{d} d1:{d} sm:{d}", .{
            @tagName(self.operation),
            @intFromBool(self.deref0),
            @intFromBool(self.deref1),
            @intFromBool(self.self_modify)});
    }

    pub fn has_writeback(self: Instruction) bool {
        return self.operation.kind() == Operation.Kind.binary or
            self.operation.kind() == Operation.Kind.unary;
    }

    pub fn has_two_inputs(self: Instruction) bool {
        return self.operation.kind() == Operation.Kind.two_args or
            (self.operation.kind() == Operation.Kind.binary and !self.self_modify);
    }
};

test "Instruction is 8-bit" {
    try expect(@sizeOf(Instruction) == 1);
}

const Operation = enum(u5) {
    // -- Bank 0: X = Y
    peek = 0b00_000,
    copy,
    deref,
    getflag,
    pop,
    not,
    negate,
    invert,

    // -- Bank 1: OP X Y
    poke = 0b01_000,
    jumpifz,
    jumpifnz,
    setflag,
    // -- Bank 1.2: OP X
    push,
    call,
    ret,
    // unused,

    // -- Bank 2: X = Y OP Z
    add = 0b10_000,
    sub,
    // unused,
    // unused,
    b_and = 0b10_100,
    b_or,
    b_xor,
    // unused,

    // -- Bank 3: X = Y OP Z (2)
    u_shiftl = 0b11_000,
    u_shiftr,
    s_shiftr,
    // unused,
    u_gt = 0b11_100,
    u_lt,
    s_gt,
    s_lt,

    const Kind = enum {
        unary,
        binary,
        one_arg,
        two_arg,
    };

    pub fn kind(self: Operation) Operation.Kind {
        const upper_bank = @intFromEnum(self) & (1 << 2) != 0;
        const kind_bits: u2 = @truncate(@intFromEnum(self) >> 3);
        return switch (kind_bits) {
            0 => Kind.unary,
            1 => if (upper_bank) Kind.one_arg else Kind.two_arg,
            2,3 => Kind.binary,
        };
    }
};

const Cpu = struct {
    pc: Word,
    memory: [memsize]Word,
    halted: bool,

    pub fn init() Cpu {
        return std.mem.zeroInit(Cpu, .{});
    }

    pub fn fetch_next(self: *Cpu) Word {
        const out = self.memory[self.pc];
        self.pc +%= 1;
        return out;
    }

    fn signed(w: Word) SWord {
        return @bitCast(w);
    }

    fn unsigned(w: SWord) Word {
        return @bitCast(w);
    }

    pub fn step(self: *Cpu) void {
        // TODO: implement self modifying bit
        var args: [3]Word = undefined;
        var retval: Word = 0;

        // Fetch
        const ix: Instruction = @bitCast(self.fetch_next());
        if (debug) {
            ix.print_info();
            print("; ", .{});
        }

        for (0..ix.argc()) |i| {
            args[i] = self.fetch_next();
            if (debug) print("param {x:0>2}; ", .{args[i]});
        }
        if (debug) print("\n", .{});

        // Read memory
        for (0..2) |i| {
            const memflag = if (i == 0) ix.deref0 else ix.deref1;
            if (memflag) {
                var idx = switch(ix.operation.kind()) {
                    .unary, .two_arg => i,
                    .binary => i+1,
                    .one_arg => 0,
                };
                if (ix.operation == Operation.deref) idx = 1;
                const addr = args[idx];
                args[idx] = self.memory[addr];
                if (debug) print("read {x:0>2} from {x:0>2}\n", .{args[idx], addr});
            }
        }

        if (ix.self_modify) {
            if (ix.operation.kind() == Operation.)
        }

        // Perform operation
        switch (ix.operation) {
            // Bank 0, unary
            //.peek => {}, // TODO: I/O
            .copy, .deref => retval = args[1],
            //.getflag => {}, // TODO: flags
            //.pop => {}, // TODO: stack
            .not => retval = if (args[1] == 0) 1 else 0,
            .negate => retval = unsigned(-signed(args[1])),
            .invert => retval = ~args[1],

            // Bank 1, two-arg
            .poke => print("{c}", .{args[1]}),
            .jumpifz => { if (args[1] == 0) self.pc = args[0]; },
            .jumpifnz => { if (args[1] != 0) self.pc = args[0]; },
            .setflag => self.halted = true, // TODO flags

            // Bank 1.2, one-arg
            //.push => {}, // TODO stack
            //.call => {}, // TODO stack
            //.ret => {}, // TODO stack

            // Bank 2/3, binary
            .add => retval = args[1] +% args[2], // TODO carry
            .sub => retval = args[1] -% args[2], // TODO carry
            .b_and => retval = args[1] & args[2],
            .b_or => retval = args[1] | args[2],
            .b_xor => retval = args[1] ^ args[2],

            .u_shiftl => retval = args[1] << @truncate(args[2]), // TODO carry
            .u_shiftr => retval = args[1] >> @truncate(args[2]), // TODO carry
            .s_shiftr => retval = unsigned(signed(args[1]) >> @truncate(args[2])), // TODO carry

            .u_gt => retval = if (args[1] > args[2]) 1 else 0,
            .u_lt => retval = if (args[1] < args[2]) 1 else 0,
            .s_gt => retval = if (signed(args[1]) > signed(args[2])) 1 else 0,
            .s_lt => retval = if (signed(args[1]) < signed(args[2])) 1 else 0,
            else => {},
        }

        // Writeback
        if (ix.has_writeback()) {
            self.memory[args[0]] = retval;
            if (debug) print("wrote {x:0>2} to {x:0>2}\n", .{retval, args[0]});
        }
    }

    pub fn run(self: *Cpu) void {
        for (0..max_run_len) |_| {
            self.step();
            if (self.halted) break;
        }
    }
};

pub fn main() !void {
    var cpu = Cpu.init();
    var assembler = Assembler.new(&cpu.memory);
    assembler.write_hello();
    cpu.run();
}

const Assembler = struct {
    addr: Word,
    binary: *[memsize]Word,

    pub fn new(binary: *[memsize]Word) Assembler {
        return Assembler {
            .addr = 0,
            .binary = binary,
        };
    }

    fn push_word(self: *Assembler, word: Word) void {
        self.binary[self.addr] = word;
        self.addr += 1;
    }

    fn push_instruction(self: *Assembler, op: Operation, flags: u3) void {
        const inst = Instruction {
            .operation = op,
            .deref0 = flags & 4 != 0,
            .deref1 = flags & 2 != 0,
            .self_modify = flags & 1 != 0,
        };
        self.push_word(@bitCast(inst));
    }

    pub fn write_hello(self: *Assembler) void {
        // let i = hello.start
        self.push_instruction(Operation.copy, 0b000);
        self.push_word(0x7f);
        const hello_start = self.addr;
        self.push_word(0);
        const loop_start = self.addr;
        // loop:
        // let char = *i ;;
        self.push_instruction(Operation.deref, 0b110);
        self.push_word(0x80);
        self.push_word(0x7f);
        // jmpz char done
        self.push_instruction(Operation.jumpifz, 0b010);
        const addr_done = self.addr;
        self.push_word(0);
        self.push_word(0x80);
        // i = i + 1
        self.push_instruction(Operation.add, 0b100);
        self.push_word(0x7f);
        self.push_word(0x7f);
        self.push_word(0x1);
        // poke TERM_WRITE char
        self.push_instruction(Operation.poke, 0b010);
        self.push_word(0);
        self.push_word(0x80);
        // jmpz loop 0
        self.push_instruction(Operation.jumpifz, 0b000);
        self.push_word(loop_start);
        self.push_word(0);
        // halt
        self.binary[addr_done] = self.addr;
        self.push_instruction(Operation.setflag, 0b000);
        self.push_word(1);
        const hello = "Hello, World!\n";
        self.binary[hello_start] = self.addr;
        for (hello) |c| self.push_word(c);
        self.push_word(0);
    }
};
