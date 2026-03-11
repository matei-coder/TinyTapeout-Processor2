/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

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
