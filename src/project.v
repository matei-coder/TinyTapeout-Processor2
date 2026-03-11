/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// ============================================================
// RISC 8-bit CPU
// ------------------------------------------------------------
// ROM   : 64 x 16-bit (64 instructiuni)
// RAM   : 16 x  8-bit (16 bytes date)
// Regs  : R0-R7 (8 x 8-bit)
// PC    : 6-bit (adreseaza 0-63)
// Stages: FETCH -> DECODE -> EXECUTE (3 clock cycles/instructiune)
//
// Format instructiune (16 biti):
//  [15:12] OPCODE (4 biti)
//  [11:9]  Rd  - registru destinatie / Rs pentru CMP,STORE,OUT
//  [8:6]   Rs1 - registru sursa 1 / registru adresa pt LOAD/STORE
//  [5:3]   Rs2 - registru sursa 2 (doar R-type)
//  [7:0]   imm8 - imediat 8-bit (LDI)
//  [5:0]   addr6 - adresa 6-bit (JMP, JZ, JNZ)
//
// Tabel instructiuni:
//  0x0  ADD  Rd, Rs1, Rs2  -> Rd = Rs1 + Rs2
//  0x1  SUB  Rd, Rs1, Rs2  -> Rd = Rs1 - Rs2
//  0x2  AND  Rd, Rs1, Rs2  -> Rd = Rs1 & Rs2
//  0x3  OR   Rd, Rs1, Rs2  -> Rd = Rs1 | Rs2
//  0x4  XOR  Rd, Rs1, Rs2  -> Rd = Rs1 ^ Rs2
//  0x5  SHL  Rd, Rs1       -> Rd = Rs1 << 1
//  0x6  SHR  Rd, Rs1       -> Rd = Rs1 >> 1
//  0x7  LDI  Rd, #imm8     -> Rd = imm8
//  0x8  LOAD Rd, [Rs1]     -> Rd = RAM[Rs1]
//  0x9  STORE Rd, [Rs1]    -> RAM[Rs1] = Rd
//  0xA  JMP  addr          -> PC = addr
//  0xB  JZ   addr          -> daca Z=1, PC = addr
//  0xC  JNZ  addr          -> daca Z=0, PC = addr
//  0xD  CMP  Rd, Rs1       -> seteaza flaguri, Rd - Rs1
//  0xE  OUT  Rd            -> io_out = Rd
//  0xF  IN   Rd            -> Rd = io_in
// ============================================================

module cpu (
    input  wire       clk,
    input  wire       rst_n,
    // Interfata incarcare program
    input  wire [7:0] data_in,       // byte de date (ui_in)
    input  wire       load_mode,     // 1 = incarcare program, 0 = executie
    input  wire       load_valid,    // puls pentru fiecare byte incarcat
    // IO procesor
    input  wire [7:0] io_in,         // intrare pentru instructiunea IN
    output reg  [7:0] io_out,        // iesire pentru instructiunea OUT
    // Flaguri de stare
    output wire       flag_zero,
    output wire       flag_carry,
    output wire       flag_neg
);

    // ----------------------------------------------------------------
    // Memorie
    // ----------------------------------------------------------------
    reg [15:0] rom [0:31];   // 32 x 16-bit - memorie program
    reg [7:0]  ram [0:15];   // 16 x  8-bit - memorie date

    // ----------------------------------------------------------------
    // Register File: R0-R7
    // ----------------------------------------------------------------
    reg [7:0] regs [0:7];

    // ----------------------------------------------------------------
    // Registre CPU
    // ----------------------------------------------------------------
    reg [4:0]  pc;     // Program Counter (5-bit, adreseaza 0-31)
    reg [15:0] ir;     // Instruction Register
    reg [1:0]  state;  // Stare FSM

    // Flaguri
    reg flag_z, flag_c, flag_n;
    assign flag_zero  = flag_z;
    assign flag_carry = flag_c;
    assign flag_neg   = flag_n;

    // Stari pipeline
    localparam FETCH   = 2'd0;
    localparam DECODE  = 2'd1;
    localparam EXECUTE = 2'd2;

    // ----------------------------------------------------------------
    // Opcodes
    // ----------------------------------------------------------------
    localparam OP_ADD   = 4'h0;
    localparam OP_SUB   = 4'h1;
    localparam OP_AND   = 4'h2;
    localparam OP_OR    = 4'h3;
    localparam OP_XOR   = 4'h4;
    localparam OP_SHL   = 4'h5;
    localparam OP_SHR   = 4'h6;
    localparam OP_LDI   = 4'h7;
    localparam OP_LOAD  = 4'h8;
    localparam OP_STORE = 4'h9;
    localparam OP_JMP   = 4'hA;
    localparam OP_JZ    = 4'hB;
    localparam OP_JNZ   = 4'hC;
    localparam OP_CMP   = 4'hD;
    localparam OP_OUT   = 4'hE;
    localparam OP_IN    = 4'hF;

    // ----------------------------------------------------------------
    // Decodificare campuri din IR
    // ----------------------------------------------------------------
    wire [3:0] opcode = ir[15:12];
    wire [2:0] f_rd   = ir[11:9];  // destinatie / Rs pt CMP,STORE,OUT
    wire [2:0] f_rs1  = ir[8:6];   // sursa 1 / adresa pt LOAD/STORE
    wire [2:0] f_rs2  = ir[5:3];   // sursa 2 (R-type)
    wire [7:0] f_imm  = ir[7:0];   // imediat 8-bit (LDI)
    wire [4:0] f_addr = ir[4:0];   // adresa salt 5-bit (JMP, JZ, JNZ) - max 31

    // ----------------------------------------------------------------
    // Intrari ALU
    // ----------------------------------------------------------------
    wire [7:0] op_a = regs[f_rs1];
    wire [7:0] op_b = regs[f_rs2];

    // ----------------------------------------------------------------
    // Rezultate ALU (combinationale)
    // [8] = carry/overflow, [7:0] = rezultat
    // ----------------------------------------------------------------
    wire [8:0] alu_add = {1'b0, op_a} + {1'b0, op_b};
    wire [8:0] alu_sub = {1'b0, op_a} - {1'b0, op_b};
    wire [7:0] alu_and = op_a & op_b;
    wire [7:0] alu_or  = op_a | op_b;
    wire [7:0] alu_xor = op_a ^ op_b;
    wire [8:0] alu_shl = {op_a, 1'b0};                       // [8]=bit iesit, [7:0]=rezultat
    wire [8:0] alu_shr = {op_a[0], 1'b0, op_a[7:1]};        // [8]=bit iesit, [7:0]=rezultat
    wire [8:0] alu_cmp = {1'b0, regs[f_rd]} - {1'b0, op_a}; // CMP: regs[Rd] - regs[Rs1]

    // ----------------------------------------------------------------
    // Logica incarcare program in ROM
    // ----------------------------------------------------------------
    reg [4:0] rom_wr_addr;
    reg [7:0] load_high;
    reg       load_byte_idx;   // 0=asteapta byte high, 1=asteapta byte low
    reg       load_valid_r;
    wire      load_valid_pulse = load_valid && !load_valid_r;

    // Detectie front crescator pe load_valid
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) load_valid_r <= 1'b0;
        else        load_valid_r <= load_valid;
    end

    // Scriere ROM (cate 2 bytes = 1 instructiune de 16 biti)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_wr_addr   <= 5'd0;
            load_byte_idx <= 1'b0;
            load_high     <= 8'd0;
        end else if (!load_mode) begin
            // Reset pointer la iesirea din modul incarcare
            rom_wr_addr   <= 5'd0;
            load_byte_idx <= 1'b0;
        end else if (load_valid_pulse) begin
            if (!load_byte_idx) begin
                // Primul byte: parte high a instructiunii
                load_high     <= data_in;
                load_byte_idx <= 1'b1;
            end else begin
                // Al doilea byte: parte low -> scriere in ROM
                rom[rom_wr_addr] <= {load_high, data_in};
                rom_wr_addr      <= rom_wr_addr + 5'd1;
                load_byte_idx    <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // FSM executie CPU
    // ----------------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc     <= 5'd0;
            state  <= FETCH;
            ir     <= 16'd0;
            io_out <= 8'd0;
            flag_z <= 1'b0;
            flag_c <= 1'b0;
            flag_n <= 1'b0;
            for (i = 0; i < 8; i = i + 1)
                regs[i] <= 8'd0;
        end else if (load_mode) begin
            // CPU oprit in timp ce se incarca programul
            pc    <= 5'd0;
            state <= FETCH;
        end else begin
            case (state)

                // ---- FETCH: citeste instructiunea, incrementeaza PC ----
                FETCH: begin
                    ir    <= rom[pc];
                    pc    <= pc + 5'd1;
                    state <= DECODE;
                end

                // ---- DECODE: stagiu pipeline (citire regs prin fire combinationale) ----
                DECODE: begin
                    state <= EXECUTE;
                end

                // ---- EXECUTE: executa operatia ----
                EXECUTE: begin
                    state <= FETCH;
                    case (opcode)

                        OP_ADD: begin
                            regs[f_rd] <= alu_add[7:0];
                            flag_c <= alu_add[8];
                            flag_z <= (alu_add[7:0] == 8'd0);
                            flag_n <= alu_add[7];
                        end

                        OP_SUB: begin
                            regs[f_rd] <= alu_sub[7:0];
                            flag_c <= alu_sub[8];
                            flag_z <= (alu_sub[7:0] == 8'd0);
                            flag_n <= alu_sub[7];
                        end

                        OP_AND: begin
                            regs[f_rd] <= alu_and;
                            flag_c <= 1'b0;
                            flag_z <= (alu_and == 8'd0);
                            flag_n <= alu_and[7];
                        end

                        OP_OR: begin
                            regs[f_rd] <= alu_or;
                            flag_c <= 1'b0;
                            flag_z <= (alu_or == 8'd0);
                            flag_n <= alu_or[7];
                        end

                        OP_XOR: begin
                            regs[f_rd] <= alu_xor;
                            flag_c <= 1'b0;
                            flag_z <= (alu_xor == 8'd0);
                            flag_n <= alu_xor[7];
                        end

                        OP_SHL: begin
                            regs[f_rd] <= alu_shl[7:0];
                            flag_c <= alu_shl[8];
                            flag_z <= (alu_shl[7:0] == 8'd0);
                            flag_n <= alu_shl[7];
                        end

                        OP_SHR: begin
                            regs[f_rd] <= alu_shr[7:0];
                            flag_c <= alu_shr[8];
                            flag_z <= (alu_shr[7:0] == 8'd0);
                            flag_n <= alu_shr[7];
                        end

                        OP_LDI: begin
                            regs[f_rd] <= f_imm;
                        end

                        OP_LOAD: begin
                            regs[f_rd] <= ram[regs[f_rs1][3:0]];
                        end

                        OP_STORE: begin
                            ram[regs[f_rs1][3:0]] <= regs[f_rd];
                        end

                        OP_JMP: begin
                            pc <= f_addr;
                        end

                        OP_JZ: begin
                            if (flag_z) pc <= f_addr;
                        end

                        OP_JNZ: begin
                            if (!flag_z) pc <= f_addr;
                        end

                        OP_CMP: begin
                            flag_z <= (alu_cmp[7:0] == 8'd0);
                            flag_c <= alu_cmp[8];
                            flag_n <= alu_cmp[7];
                        end

                        OP_OUT: begin
                            io_out <= regs[f_rd];
                        end

                        OP_IN: begin
                            regs[f_rd] <= io_in;
                        end

                        default: begin
                            // NOP - instructiune nedefinita, continua
                        end

                    endcase
                end

                default: state <= FETCH;

            endcase
        end
    end

endmodule

// ============================================================
// Wrapper TinyTapeout pentru procesorul RISC 8-bit
// ============================================================
// Mapare pini:
//
//  ui_in  [7:0]  -> date intrare (byte program in modul incarcare
//                                 sau valoare IO pentru instructiunea IN)
//  uo_out [7:0]  -> date iesire  (rezultatul instructiunii OUT)
//
//  uio_in [0]    -> load_mode   (1 = incarcare program, 0 = executie)
//  uio_in [1]    -> load_valid  (puls pentru fiecare byte incarcat)
//  uio_in [7:2]  -> neutilizati
//
//  uio_out[0]    -> flag_zero   (rezultat 0 dupa ultima operatie ALU)
//  uio_out[1]    -> flag_carry  (carry/borrow dupa ultima operatie)
//  uio_out[2]    -> flag_neg    (rezultat negativ dupa ultima operatie)
//  uio_out[7:3]  -> 0
//
// Protocol incarcare program:
//  1. Seteaza load_mode = 1
//  2. Pentru fiecare instructiune de 16 biti:
//     a. Pune byte HIGH pe ui_in, puls pe load_valid
//     b. Pune byte LOW  pe ui_in, puls pe load_valid
//  3. Seteaza load_mode = 0 -> procesorul porneste de la PC=0
// ============================================================

module tt_um_mchiriac (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire flag_zero, flag_carry, flag_neg;

    // uio[2:0] sunt iesiri (flaguri), restul sunt intrari
    assign uio_oe  = 8'b00000111;
    assign uio_out = {5'b00000, flag_neg, flag_carry, flag_zero};

    cpu cpu_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_in    (ui_in),
        .load_mode  (uio_in[0]),
        .load_valid (uio_in[1]),
        .io_in      (ui_in),
        .io_out     (uo_out),
        .flag_zero  (flag_zero),
        .flag_carry (flag_carry),
        .flag_neg   (flag_neg)
    );

    wire _unused = &{ena, uio_in[7:2]};

endmodule
