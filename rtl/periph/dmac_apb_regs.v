// DMAC control registers, APB slave (Phase 8).
//   0x00 DMAC_SRC     R/W  source byte address (word-aligned): ROM or RAM
//   0x04 DMAC_DST     R/W  destination byte address (word-aligned): RAM
//   0x08 DMAC_LEN     R/W  number of 32-bit words; 0 = no transfer (done at once)
//   0x0C DMAC_CTRL    R/W  bit 0 start (self-clearing, pulses dmac_start, ignored
//                          while busy), bit 1 irq_enable; any write clears done
//   0x10 DMAC_STATUS  R    bit 0 busy (from the engine), bit 1 done (sticky)
// Registers are decoded on PADDR[7:2].
module dmac_apb_regs (
    input             PCLK,
    input             PRESETn,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PADDR,
    input      [31:0] PWDATA,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,

    // to the engine (dmac_ahb_master)
    output     [31:0] dmac_src,
    output     [31:0] dmac_dst,
    output     [31:0] dmac_len,
    output reg        dmac_start,
    // from the engine
    input             dmac_busy,
    input             dmac_done,

    output            irq            // done AND irq_enable (optional)
);

    localparam [5:0] REG_SRC    = 6'h00,   // 0x00
                     REG_DST    = 6'h01,   // 0x04
                     REG_LEN    = 6'h02,   // 0x08
                     REG_CTRL   = 6'h03,   // 0x0C
                     REG_STATUS = 6'h04;   // 0x10

    reg [31:0] src_reg;
    reg [31:0] dst_reg;
    reg [31:0] len_reg;
    reg        irq_enable;
    reg        done_flag;

    wire write_en   = PSEL && PENABLE && PWRITE;
    wire ctrl_write = write_en && (PADDR[7:2] == REG_CTRL);

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            src_reg    <= 32'b0;
            dst_reg    <= 32'b0;
            len_reg    <= 32'b0;
            irq_enable <= 1'b0;
            done_flag  <= 1'b0;
            dmac_start <= 1'b0;
        end else begin
            dmac_start <= 1'b0;

            if (write_en) begin
                case (PADDR[7:2])
                    REG_SRC: src_reg <= PWDATA;
                    REG_DST: dst_reg <= PWDATA;
                    REG_LEN: len_reg <= PWDATA;
                    default: ;
                endcase
            end

            if (ctrl_write) begin
                irq_enable <= PWDATA[1];
                done_flag  <= 1'b0;
                if (PWDATA[0] && !dmac_busy)
                    dmac_start <= 1'b1;
            end

            // A completion in the same cycle as a CTRL write stays visible.
            if (dmac_done)
                done_flag <= 1'b1;
        end
    end

    always @(*) begin
        case (PADDR[7:2])
            REG_SRC:    PRDATA = src_reg;
            REG_DST:    PRDATA = dst_reg;
            REG_LEN:    PRDATA = len_reg;
            REG_CTRL:   PRDATA = {30'b0, irq_enable, 1'b0};   // start reads 0
            REG_STATUS: PRDATA = {30'b0, done_flag, dmac_busy};
            default:    PRDATA = 32'b0;
        endcase
    end

    assign PREADY   = 1'b1;
    assign PSLVERR  = 1'b0;
    assign dmac_src = src_reg;
    assign dmac_dst = dst_reg;
    assign dmac_len = len_reg;
    assign irq      = done_flag && irq_enable;

endmodule
