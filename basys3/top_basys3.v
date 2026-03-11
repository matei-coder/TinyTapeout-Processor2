`default_nettype none

// ============================================================
// Top-level Basys 3 pentru procesorul RISC 8-bit
// ============================================================
//
// CONTROALE:
//   BTNU         = Reset (tine apasat pentru reset)
//   SW[8]        = load_mode  (1 = incarcare program, 0 = executie)
//   BTNC         = load_valid (puls: incarcare byte in modul load)
//   SW[7:0]      = ui_in      (byte de date / program)
//   SW[15]       = viteza     (0 = ~3Hz vizibil | 1 = 100MHz rapid)
//
// IESIRI:
//   LED[7:0]     = uo_out     (rezultatul instructiunii OUT)
//   LED[8]       = flag Zero
//   LED[9]       = flag Carry
//   LED[10]      = flag Negative
//   LED[11]      = load_mode activ (indicator)
//   LED[15:12]   = 0
//
// 7-SEGMENTE:
//   AN[1:0]      = uo_out in hex  (ex: 0x2A)
//   AN[3:2]      = ui_in  in hex  (ce ai pe switch-uri)
// ============================================================

module top_basys3 (
    input  wire        CLK100MHZ,
    input  wire [15:0] SW,
    input  wire        BTNC,    // load_valid
    input  wire        BTNU,    // reset
    output wire [15:0] LED,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);

    // ----------------------------------------------------------
    // Reset: BTNU apasat = reset (buton active-high -> rst_n active-low)
    // ----------------------------------------------------------
    wire rst_n = ~BTNU;

    // ----------------------------------------------------------
    // Debounce BTNC (evita bouncing-ul butonului)
    // ----------------------------------------------------------
    wire btnc_clean;
    debouncer db_btnc (
        .clk    (CLK100MHZ),
        .rst_n  (rst_n),
        .btn_in (BTNC),
        .btn_out(btnc_clean)
    );

    // ----------------------------------------------------------
    // Clock divider
    // SW[15] = 0 -> ~3Hz  (poti vedea cum evolueaza LED-urile)
    // SW[15] = 1 -> 100MHz (viteza completa)
    // ----------------------------------------------------------
    reg [24:0] clk_cnt;
    always @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) clk_cnt <= 25'd0;
        else        clk_cnt <= clk_cnt + 25'd1;
    end

    // clk_cnt[24] ~= 100MHz / 2^25 ~= 2.98 Hz
    wire cpu_clk = SW[15] ? CLK100MHZ : clk_cnt[24];

    // ----------------------------------------------------------
    // Interfata catre tt_um_mchiriac
    // ----------------------------------------------------------
    wire [7:0] ui_in  = SW[7:0];
    // uio_in[0] = load_mode (SW[8])
    // uio_in[1] = load_valid (BTNC debounced)
    wire [7:0] uio_in = {6'b000000, btnc_clean, SW[8]};

    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // ----------------------------------------------------------
    // Instantiere procesor
    // ----------------------------------------------------------
    tt_um_mchiriac cpu (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (1'b1),
        .clk    (cpu_clk),
        .rst_n  (rst_n)
    );

    // ----------------------------------------------------------
    // LED-uri
    // ----------------------------------------------------------
    assign LED[7:0]   = uo_out;        // rezultat OUT
    assign LED[8]     = uio_out[2];    // flag Zero   (uio[2])
    assign LED[9]     = uio_out[3];    // flag Carry  (uio[3])
    assign LED[10]    = uio_out[4];    // flag Negative (uio[4])
    assign LED[11]    = SW[8];         // load_mode activ
    assign LED[15:12] = 4'b0000;

    // ----------------------------------------------------------
    // Display 7-segmente: AN[3:2] = ui_in hex, AN[1:0] = uo_out hex
    // ----------------------------------------------------------
    seg7_ctrl display (
        .clk  (CLK100MHZ),
        .rst_n(rst_n),
        .val  ({SW[7:0], uo_out}),   // [15:8]=input, [7:0]=output
        .seg  (seg),
        .an   (an),
        .dp   (dp)
    );

endmodule
