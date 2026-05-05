module dmac_ahb_master (
    input         HCLK,
    input         HRESETn,

    // DMA parameters from APB control registers (dmac_apb)
    input  [31:0] dmac_src,    // Source AHB address (read from here)
    input  [31:0] dmac_dst,    // Destination AHB address (write to here)
    input  [31:0] dmac_len,    // Number of 32-bit words to transfer
    input         dmac_enable, // Start pulse from dmac_apb CTRL register

    // AHB slave response inputs
    input  [31:0] HRDATA,      // Read data — captured in W_ISSUE's data phase
    input         HREADY,      // Bus ready — wait here when 0
    input         HGRANT,      // DMAC has bus ownership

    // AHB master outputs
    output [31:0] HADDR,       // Address to bus
    output [1:0]  HTRANS,      // NONSEQ in any address-phase state, IDLE otherwise
    output        HWRITE,      // 1 in W_ISSUE / FINAL_DATA, 0 otherwise
    output [2:0]  HSIZE,       // Always 3'b010 (word transfers)
    output [31:0] HWDATA,      // rd_buf driven in R_ISSUE / FINAL_DATA
    output        HBUSREQ,     // Hold high while transfer in progress
    output        HLOCK,       // Hold bus atomically across the entire pipeline

    // Status outputs → dmac_apb STATUS register
    output        dmac_busy,   // High from REQUEST until DONE
    output        dmac_done    // One-cycle pulse when transfer complete
);

    // Pipelined FSM: alternating R-addr / W-addr cycles in steady state.
    //
    //   Cycle:   1     2          3          4          ...   2N+1       2N+2
    //   Addr:    R0    W0         R1         W1         ...   W(N-1)     —
    //   Data:    —     R0 (cap)   W0 (drv)   R1 (cap)   ...   R(N-1)     W(N-1)
    //
    // Each word costs ~2 cycles in steady state instead of 4.
    localparam [2:0] S_IDLE          = 3'd0,
                     S_REQUEST       = 3'd1,
                     S_R_ISSUE_FIRST = 3'd2,  // first read addr — no preceding data phase
                     S_W_ISSUE       = 3'd3,  // issue W addr; data phase = previous R (capture HRDATA)
                     S_R_ISSUE       = 3'd4,  // issue R addr; data phase = previous W (drive HWDATA)
                     S_FINAL_DATA    = 3'd5,  // no addr phase; final W's data phase (drive HWDATA)
                     S_DONE          = 3'd6;

    reg [2:0]  state;

    reg [31:0] src_ptr;
    reg [31:0] dst_ptr;
    reg [31:0] reads_remaining;
    reg [31:0] rd_buf;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state           <= S_IDLE;
            src_ptr         <= 32'b0;
            dst_ptr         <= 32'b0;
            reads_remaining <= 32'b0;
            rd_buf          <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (dmac_enable && (dmac_len != 32'b0)) begin
                        src_ptr         <= dmac_src;
                        dst_ptr         <= dmac_dst;
                        reads_remaining <= dmac_len;
                        state           <= S_REQUEST;
                    end
                end

                S_REQUEST: begin
                    if (HGRANT && HREADY)
                        state <= S_R_ISSUE_FIRST;
                end

                S_R_ISSUE_FIRST: begin
                    if (HGRANT && HREADY) begin
                        src_ptr         <= src_ptr + 32'd4;
                        reads_remaining <= reads_remaining - 32'd1;
                        state           <= S_W_ISSUE;
                    end
                end

                S_W_ISSUE: begin
                    // Address phase: issue W. Data phase: capture R's HRDATA.
                    if (HREADY) begin
                        rd_buf  <= HRDATA;
                        dst_ptr <= dst_ptr + 32'd4;
                        if (reads_remaining == 32'd0)
                            state <= S_FINAL_DATA;  // last write — only data phase remains
                        else
                            state <= S_R_ISSUE;
                    end
                end

                S_R_ISSUE: begin
                    // Address phase: issue R. Data phase: drive HWDATA = rd_buf
                    // (the previous W's data phase).
                    if (HGRANT && HREADY) begin
                        src_ptr         <= src_ptr + 32'd4;
                        reads_remaining <= reads_remaining - 32'd1;
                        state           <= S_W_ISSUE;
                    end
                end

                S_FINAL_DATA: begin
                    // No new address phase; just commit the last write's data.
                    if (HREADY)
                        state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

    localparam [1:0] HTRANS_IDLE   = 2'b00,
                    HTRANS_NONSEQ = 2'b10;

    assign HBUSREQ = (state != S_IDLE) && (state != S_DONE);

    assign HTRANS = ((state == S_R_ISSUE_FIRST) ||
                     (state == S_W_ISSUE)       ||
                     (state == S_R_ISSUE))
                    ? HTRANS_NONSEQ : HTRANS_IDLE;

    assign HWRITE = (state == S_W_ISSUE) || (state == S_FINAL_DATA);

    assign HSIZE = 3'b010;

    assign HADDR = (state == S_R_ISSUE_FIRST) ? src_ptr :
                   (state == S_R_ISSUE)       ? src_ptr :
                   (state == S_W_ISSUE)       ? dst_ptr :
                                                32'b0;


    assign HWDATA = (state == S_R_ISSUE)    ? rd_buf :
                    (state == S_FINAL_DATA) ? rd_buf :
                                              32'b0;

    assign HLOCK = (state == S_R_ISSUE_FIRST) ||
                   (state == S_W_ISSUE)       ||
                   (state == S_R_ISSUE)       ||
                   (state == S_FINAL_DATA);

    assign dmac_busy = (state != S_IDLE);
    assign dmac_done = (state == S_DONE);

endmodule
