module dmac_apb (
    input         PCLK,
    input         PRESETn,
    input         PSEL,
    input         PENABLE,
    input         PWRITE,
    input  [7:0]  PADDR,
    input  [31:0] PWDATA,
    output [31:0] PRDATA,
    output        PREADY,
    output        PSLVERR,
    output [31:0] dma_src,
    output [31:0] dma_dst,
    output [31:0] dma_len,
    output        dma_start,
    input         dma_busy,
    input         dma_done
);

    localparam ADDR_SRC    = 8'h00;
    localparam ADDR_DST    = 8'h04;
    localparam ADDR_LEN    = 8'h08;
    localparam ADDR_CTRL   = 8'h0C;
    localparam ADDR_STATUS = 8'h10;

    wire transfer = PSEL & PENABLE;

    reg [31:0] src_reg;
    reg [31:0] dst_reg;
    reg [31:0] len_reg;
    reg        dma_start_reg;

    assign PREADY     = 1'b1;
    assign PSLVERR    = 1'b0;
    assign dma_src    = src_reg;
    assign dma_dst    = dst_reg;
    assign dma_len    = len_reg;
    assign dma_start  = dma_start_reg;

    assign PRDATA = (PADDR == ADDR_SRC)    ? src_reg                        :
                (PADDR == ADDR_DST)    ? dst_reg                        :
                (PADDR == ADDR_LEN)    ? len_reg                        :
                (PADDR == ADDR_STATUS) ? {30'b0, dma_done, dma_busy}    :
                32'b0;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            src_reg       <= 32'b0;
            dst_reg       <= 32'b0;
            len_reg       <= 32'b0;
            dma_start_reg <= 1'b0;
        end else begin
            dma_start_reg <= 1'b0;

            if (transfer & PWRITE) begin
                case (PADDR)
                    ADDR_SRC:  src_reg <= PWDATA;
                    ADDR_DST:  dst_reg <= PWDATA;
                    ADDR_LEN:  len_reg <= PWDATA;
                    ADDR_CTRL: begin
                        if (PWDATA[0] & !dma_busy)
                            dma_start_reg <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
