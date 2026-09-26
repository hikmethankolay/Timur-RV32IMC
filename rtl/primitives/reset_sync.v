// Reset synchroniser (Phase 1).
// Asserts asynchronously with async_rst_n and releases on the second rising
// edge of clk after async_rst_n returns high, so every flip-flop in the
// design leaves reset on the same edge.
module reset_sync (
    input  clk,
    input  async_rst_n,   // reset button AND pll_locked
    output sync_rst_n     // system reset distributed to every module
);

    reg stage1;
    reg stage2;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            stage1 <= 1'b0;
            stage2 <= 1'b0;
        end else begin
            stage1 <= 1'b1;
            stage2 <= stage1;
        end
    end

    assign sync_rst_n = stage2;

endmodule
