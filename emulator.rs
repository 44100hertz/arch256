type Word = u16;

const MEMSIZE: usize = 1 << 16;

fn main() {
    let mut cpu = Cpu::new();
    let hello_binary: Vec<Word> = vec![
        0x0048, 0x0065, 0x006c, 0x006c, 0x006f, 0x002c, 0x0020, 0x0077, 0x006f,
        0x0072, 0x006c, 0x0064, 0x0021, 0x000a, 0x0000, 0x1401, 0x007f, 0x0000,
        0x1200, 0x007f, 0x0601, 0x0080, 0x2502, 0x007f, 0x0001, 0x007f, 0x2104,
        0x0000, 0x0080, 0x1003, 0x0021, 0x2003, 0x0011, 0x0000, 0x0005
    ];

    for (i, word) in hello_binary.iter().enumerate() {
        cpu.memory[i] = *word;
    }
    cpu.pc = 15;
    cpu.run();
}

#[repr(u8)]
#[derive(Copy, Clone, Debug)]
enum Operation {
    None,
    Copy,
    Add,
    JumpIfZero,
    Poke,
    Halt,
}

impl Operation {
    fn from_byte(byte: u8) -> Self {
        if byte > (Operation::Halt as u8) {
            Operation::None
        } else {
            unsafe {
                std::mem::transmute(byte)
            }
        }
    }
}

struct Instruction {
    operation: Operation,
    argc: u8,
    read_addr: [bool; 2],
    write_addr: bool,
}

impl Instruction {
    fn from_word(word: Word) -> Self {
        Self {
            operation: Operation::from_byte(word as u8),
            argc: (word >> 12 & 0x3) as u8,
            read_addr: [
                word & (1 << 9) != 0,
                word & (1 << 8) != 0,
            ],
            write_addr: word & (1 << 10) != 0,
        }
    }

    fn to_word(&self) -> Word {
        (self.operation as Word) |
        (self.argc as Word) << 12 |
        (self.read_addr[0] as Word) << 8 |
        (self.read_addr[1] as Word) << 9 |
        (self.write_addr as Word) << 10
    }
}

struct Cpu {
    pc: Word,
    reg_in: [Word; 3],
    reg_out: Word,
    memory: Vec<Word>,
    halted: bool,
}

impl Cpu {
    fn new() -> Self {
        Self {
            pc: 0,
            reg_in: [0; 3],
            reg_out: 0,
            memory: (0..MEMSIZE).map(|_| 0).collect(),
            halted: false,
        }
    }

    fn fetch(&mut self) -> Word {
        let out = self.memory[self.pc as usize];
        self.pc += 1;
        out
    }

    fn step(&mut self) {
        // Fetch
        let debug = false;
        let ix = Instruction::from_word(self.fetch());
        if debug { print!("instruction {:?}; ", ix.operation) };
        let write_addr = if ix.write_addr { self.fetch() } else { 0 };
        for i in 0..(ix.argc as usize) {
            self.reg_in[i] = self.fetch();
            if debug { print!("{:04x}; ", self.reg_in[i]) }
        }
        if debug { println!() }

        // Read memory
        for i in 0..2 {
            if ix.read_addr[i] {
                let addr = self.reg_in[i];
                self.reg_in[i] = self.memory[addr as usize];
                if debug { println!("read {:04x} from {:04x}", self.reg_in[i], addr) }
            }
        }

        // Do operation
        match ix.operation {
            Operation::Copy => self.reg_out = self.reg_in[0],
            Operation::Add => self.reg_out = self.reg_in[0].wrapping_add(self.reg_in[1]),
            Operation::JumpIfZero => if self.reg_in[1] == 0 { self.pc = self.reg_in[0] },
            Operation::Poke => print!("{}", (self.reg_in[1] as u8 as char)),
            Operation::Halt => self.halted = true,
            _ => {}
        }

        // Writeback
        if ix.write_addr {
            self.memory[write_addr as usize] = self.reg_out;
            if debug { println!("wrote {:04x} to {:04x}", self.reg_out, write_addr) }
        }
    }

    fn run(&mut self) {
        for _ in 0..100 {
            if self.halted { break }
            self.step();
        }
    }
}
