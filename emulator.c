#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

typedef uint16_t word;
typedef uint8_t byte;

/*
Instruction layout:
__LL _DSS IIII IIII
  L = number of args 0-3
  D = Whether to write back result (to extra provided param)
  S = Whether to read input(s) from an address (1) or immediate (0)
  I = Which of 256 instructions to perform in between.
*/
enum {
    ZERO_PAGE_SIZE = 1 << 8, // First 256 bytes are "registers" on stack
    MEMSIZE = (1 << 16) - ZERO_PAGE_SIZE, // Rest is in heap
    IBIT_READADDR1 = 1 << 8,
    IBIT_READADDR0 = 1 << 9,
    IBIT_WRITEADDR = 1 << 10,
    IOFFSET_LEN = 12,
};

typedef union {
    struct {
        byte operation: 8;
        bool read_addr1: 1;
        bool read_addr0: 1;
        byte write_addr: 1;
        byte _pad0: 1;
        byte argc: 2;
        byte _pad1: 2;
    };
    word iword;
} Instruction;

enum {
    OP_NONE,
    OP_COPY,
    OP_DEREF,
    OP_ADD,
    OP_JUMP_IF_ZERO,
    OP_POKE,
    OP_HALT,
};

typedef struct {
    word pc;
    word reg_in[3];
    word reg_out;
    word zeropage[255];
    word *memory;
    bool halted;
} CPU;

CPU init_cpu() {
    return (CPU){
      .memory = calloc(sizeof(word), MEMSIZE),
      .halted = false,
    };
}

void free_cpu(CPU cpu) {
    free(cpu.memory);
}

void step_cpu(CPU *cpu) {
    bool debug = false;
    Instruction ix = { .iword = cpu->memory[cpu->pc++] };
    word write_addr;
    if(debug) printf("instruction %08b %02x; ", ix.iword >> 8, ix.operation);
    if (ix.write_addr) {
        write_addr = cpu->memory[cpu->pc++];
    }
    for (int i=0; i<ix.argc; ++i) {
        cpu->reg_in[i] = cpu->memory[cpu->pc++];
        if (debug) printf("param %04x; ", cpu->reg_in[i]);
    }
    if (debug) puts("");
    for (int i=0; i<2; ++i) {
        bool memflag = (i == 0) ? ix.read_addr0 : ix.read_addr1;
        if (memflag) {
            word addr = cpu->reg_in[i];
            cpu->reg_in[i] = cpu->memory[addr];
            if (debug) printf("read %04x from %04x\n", cpu->reg_in[i], addr);
        }
    }
    switch (ix.operation) {
        case OP_NONE: break;
        case OP_COPY: cpu->reg_out = cpu->reg_in[0]; break;
        case OP_ADD: cpu->reg_out = cpu->reg_in[0] + cpu->reg_in[1]; break;
        case OP_JUMP_IF_ZERO: if (cpu->reg_in[1] == 0) cpu->pc = cpu->reg_in[0]; break;
        case OP_POKE: putchar(cpu->reg_in[1]); break;
        case OP_HALT: cpu->halted = true;
    }
    if (ix.write_addr) {
        cpu->memory[write_addr] = cpu->reg_out;
        if (debug) printf("wrote %04x to %04x\n", cpu->reg_out, write_addr);
    }
}

int main() {
    CPU cpu = init_cpu();

    // Ghetto assembler in C lmaooo
    char hello_world[] = "Hello, world!\n";
    char *c = hello_world;
    int i=0;
    while (*c) {
        cpu.memory[i] = hello_world[i];
        ++i, ++c;
    }
    int code_start = i;
    // let i = hello.start ;; hello.start is 0
    cpu.memory[i++] = (1 << IOFFSET_LEN) | IBIT_WRITEADDR | OP_COPY;
    cpu.memory[i++] = 127;
    cpu.memory[i++] = 0;
    // loop:
    int loop_start = i;
    // let char = *i ;;
    cpu.memory[i++] = (1 << IOFFSET_LEN) | IBIT_READADDR0 | OP_NONE;
    cpu.memory[i++] = 127;
    cpu.memory[i++] = IBIT_WRITEADDR | IBIT_READADDR0 | OP_COPY;
    cpu.memory[i++] = 128;
    // i += 1
    cpu.memory[i++] = (2 << IOFFSET_LEN) | IBIT_WRITEADDR | IBIT_READADDR1 | OP_ADD;
    cpu.memory[i++] = 127;
    cpu.memory[i++] = 1;
    cpu.memory[i++] = 127;
    // poke TERM_WRITE char
    cpu.memory[i++] = (2 << IOFFSET_LEN) | IBIT_READADDR1 | OP_POKE;
    cpu.memory[i++] = 0;
    cpu.memory[i++] = 128;
    // jmpz done char
    cpu.memory[i++] = (1 << IOFFSET_LEN) | OP_JUMP_IF_ZERO;
    int write_back_to_done_label = i++;
    // jmpz loop 0
    cpu.memory[i++] = (2 << IOFFSET_LEN) | OP_JUMP_IF_ZERO;
    cpu.memory[i++] = loop_start;
    cpu.memory[i++] = 0;
    // done:
    cpu.memory[write_back_to_done_label] = i;
    cpu.memory[i++] = OP_HALT;

    cpu.pc = code_start;

    /* for (int i=0; i<50; ++i) { */
    /*     printf("0x%04x, ", ((cpu.memory[i] & 0xff) << 8) | cpu.memory[i] >> 8); */
    /* } */
    /* puts(""); */
    /* puts(""); */

    for (int i=0; i<100 && !cpu.halted; ++i) {
        step_cpu(&cpu);
    }
    free_cpu(cpu);
    return 0;
}
