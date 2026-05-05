module dmac_ahb_master (
    input         HCLK,
    input         HRESETn,

    // DMA parameters from APB control registers (dmac_apb)
    input  [31:0] dmac_src,    // Source AHB address (read from here)
    input  [31:0] dmac_dst,    // Destination AHB address (write to here)
    input  [31:0] dmac_len,    // Number of 32-bit words to transfer
    input         dmac_enable, // Start pulse from dmac_apb CTRL register

    // AHB slave response inputs
    input  [31:0] HRDATA,      // Read data captured in READ_DATA state
    input         HREADY,      // Bus ready — wait here when 0
    input         HGRANT,      // DMAC has bus ownership

    // AHB master outputs
    output [31:0] HADDR,       // Address to bus
    output [1:0]  HTRANS,      // NONSEQ when issuing, IDLE otherwise
    output        HWRITE,      // 1 in WRITE_ADDR/WRITE_DATA, 0 otherwise
    output [2:0]  HSIZE,       // Always 3'b010 (word transfers)
    output [31:0] HWDATA,      // Captured read data driven in WRITE_DATA
    output        HBUSREQ,     // Hold high while transfer in progress
    output        HLOCK,       // Hold bus atomically through one word's 4 cycles

    // Status outputs → dmac_apb STATUS register
    output        dmac_busy,   // High from REQUEST until DONE
    output        dmac_done    // One-cycle pulse when transfer complete
);

    localparam [2:0] S_IDLE       = 3'd0,
                    S_REQUEST    = 3'd1,
                    S_READ_ADDR  = 3'd2,
                    S_READ_DATA  = 3'd3,
                    S_WRITE_ADDR = 3'd4,
                    S_WRITE_DATA = 3'd5,
                    S_DONE       = 3'd6;

    reg [2:0]  state;

    reg [31:0] src_ptr;
    reg [31:0] dst_ptr;
    reg [31:0] words_left;
    reg [31:0] rd_buf;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state      <= S_IDLE;
            src_ptr    <= 32'b0;
            dst_ptr    <= 32'b0;
            words_left <= 32'b0;
            rd_buf     <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (dmac_enable && (dmac_len != 32'b0)) begin
                        src_ptr <= dmac_src;
                        dst_ptr <= dmac_dst;
                        words_left <= dmac_len;
                        state <= S_REQUEST;
                    end
                end

                S_REQUEST: begin
                    if (HGRANT && HREADY) begin
                        state <= S_READ_ADDR;
                    end
                end

                S_READ_ADDR: begin
                    if (HGRANT && HREADY) begin
                        state <= S_READ_DATA;
                    end
                end

                S_READ_DATA: begin
                    if (HREADY) begin
                        rd_buf <= HRDATA;
                        state <= S_WRITE_ADDR;
                    end
                end

                S_WRITE_ADDR: begin
                    if (HGRANT && HREADY) begin
                        state <= S_WRITE_DATA;
                    end
                end

                S_WRITE_DATA: begin
                    if (HREADY) begin
                        src_ptr <= src_ptr + 32'd4;
                        dst_ptr <= dst_ptr + 32'd4;
                        words_left <= words_left - 32'd1;

                        if (words_left == 32'd1) begin
                        state <= S_DONE;
                        end
                        else begin
                            state <= S_READ_ADDR;
                        end

                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    localparam [1:0] HTRANS_IDLE   = 2'b00,
                    HTRANS_NONSEQ = 2'b10;

    assign HBUSREQ = (state != S_IDLE) && (state != S_DONE);

    assign HTRANS  = ((state == S_READ_ADDR) || (state == S_WRITE_ADDR))
                     ? HTRANS_NONSEQ : HTRANS_IDLE;
    
    assign HWRITE  = (state == S_WRITE_ADDR) || (state == S_WRITE_DATA);

    assign HSIZE   = 3'b010;

    assign HADDR   = (state == S_READ_ADDR)  ? src_ptr :
                     (state == S_WRITE_ADDR) ? dst_ptr :
                                               32'b0;

    assign HWDATA  = (state == S_WRITE_DATA) ? rd_buf : 32'b0;


    // HLOCK held through the address-phase states of one word so the arbiter
    // can't preempt between read-addr/read-data/write-addr. Released in
    // S_WRITE_DATA so the CPU can grab the bus at word boundaries.
    assign HLOCK = (state == S_READ_ADDR)  ||
                   (state == S_READ_DATA)  ||
                   (state == S_WRITE_ADDR);

    assign dmac_busy = (state != S_IDLE);
    assign dmac_done = (state == S_DONE);

endmodule
