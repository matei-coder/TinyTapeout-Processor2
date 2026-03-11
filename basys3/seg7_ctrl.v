`default_nettype none

// ============================================================
// Controller afisaj 7-segmente cu multiplexare (Basys 3)
// Afiseaza un numar de 16 biti in hex pe 4 cifre
// val[15:8] = AN[3:2] (stanga)
// val[7:0]  = AN[1:0] (dreapta)
// ============================================================

module seg7_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] val,
    output reg  [6:0]  seg,
    output reg  [3:0]  an,
    output wire        dp
);

    assign dp = 1'b1; // punct zecimal oprit

    // Contor pentru multiplexare ~1kHz refresh (100MHz / 2^17 ~= 762Hz)
    reg [16:0] mux_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mux_cnt <= 17'd0;
        else        mux_cnt <= mux_cnt + 17'd1;
    end

    wire [1:0] digit_sel = mux_cnt[16:15]; // selecteaza cifra activa

    // Cifra activa
    reg [3:0] digit;
    always @(*) begin
        case (digit_sel)
            2'd0: digit = val[3:0];     // AN0 - cifra dreapta (uo_out low)
            2'd1: digit = val[7:4];     // AN1 - cifra dreapta (uo_out high)
            2'd2: digit = val[11:8];    // AN2 - cifra stanga (ui_in low)
            2'd3: digit = val[15:12];   // AN3 - cifra stanga (ui_in high)
            default: digit = 4'h0;
        endcase
    end

    // Activare anod (active low)
    always @(*) begin
        case (digit_sel)
            2'd0: an = 4'b1110;
            2'd1: an = 4'b1101;
            2'd2: an = 4'b1011;
            2'd3: an = 4'b0111;
            default: an = 4'b1111;
        endcase
    end

    // Decodificare hex -> segmente (active low)
    // Segmente: seg[6:0] = {G, F, E, D, C, B, A}
    always @(*) begin
        case (digit)
            4'h0: seg = 7'b1000000; // 0
            4'h1: seg = 7'b1111001; // 1
            4'h2: seg = 7'b0100100; // 2
            4'h3: seg = 7'b0110000; // 3
            4'h4: seg = 7'b0011001; // 4
            4'h5: seg = 7'b0010010; // 5
            4'h6: seg = 7'b0000010; // 6
            4'h7: seg = 7'b1111000; // 7
            4'h8: seg = 7'b0000000; // 8
            4'h9: seg = 7'b0010000; // 9
            4'hA: seg = 7'b0001000; // A
            4'hB: seg = 7'b0000011; // b
            4'hC: seg = 7'b1000110; // C
            4'hD: seg = 7'b0100001; // d
            4'hE: seg = 7'b0000110; // E
            4'hF: seg = 7'b0001110; // F
            default: seg = 7'b1111111; // oprit
        endcase
    end

endmodule
