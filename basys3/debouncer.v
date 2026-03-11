`default_nettype none

// ============================================================
// Debouncer pentru butoane (100MHz clock)
// Foloseste un contor de 20 biti ~10ms stabilizare
// ============================================================

module debouncer (
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,
    output reg  btn_out
);

    reg [19:0] cnt;
    reg        btn_sync0, btn_sync1;

    // Sincronizare semnal asincron in domeniul clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync0 <= 1'b0;
            btn_sync1 <= 1'b0;
        end else begin
            btn_sync0 <= btn_in;
            btn_sync1 <= btn_sync0;
        end
    end

    // Contor: daca semnalul e stabil 2^20 / 100MHz = ~10ms, accepta valoarea
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 20'd0;
            btn_out <= 1'b0;
        end else begin
            if (btn_sync1 == btn_out) begin
                cnt <= 20'd0;           // semnal stabil, reseteaza contorul
            end else begin
                cnt <= cnt + 20'd1;
                if (cnt == 20'hFFFFF) begin
                    btn_out <= btn_sync1; // schimba iesirea dupa 10ms stabilitate
                    cnt     <= 20'd0;
                end
            end
        end
    end

endmodule
