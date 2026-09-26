// DMA engine, AHB master 1 (Phase 9): memory-to-memory word copies.
//   IDLE    : dmac_start -> RD_ADDR (count = 0); LEN = 0 -> DONE directly
//   RD_ADDR : NONSEQ read of src + 4*count; accepted (HGRANT and HREADY) -> RD_DATA
//   RD_DATA : HREADY -> capture HRDATA -> WR_ADDR
//   WR_ADDR : NONSEQ write of dst + 4*count; accepted -> WR_DATA
//   WR_DATA : HWDATA = captured word; HREADY -> count + 1;
//             DONE if count + 1 = LEN, else RD_ADDR
//   DONE    : pulse dmac_done -> IDLE
// Word transfers only; reads from ROM or RAM, writes to RAM. If the CPU takes
// the bus between states the engine waits in its current state with its data
// preserved, so no transfer needs to be atomic.
module dmac_ahb_master (
    input             HCLK,
    input             HRESETn,

    // from dmac_apb_regs
    input      [31:0] dmac_src,
    input      [31:0] dmac_dst,
    input      [31:0] dmac_len,
    input             dmac_start,
    // to dmac_apb_regs
    output            dmac_busy,
    output            dmac_done,

    // AHB master
    input             HGRANT,
    input             HREADY,
    input      [31:0] HRDATA,
    output            HBUSREQ,
    output     [31:0] HADDR,
    output     [1:0]  HTRANS,
    output            HWRITE,
    output     [2:0]  HSIZE,
    output     [31:0] HWDATA
);

    localparam [2:0] S_IDLE    = 3'd0,
                     S_RD_ADDR = 3'd1,
                     S_RD_DATA = 3'd2,
                     S_WR_ADDR = 3'd3,
                     S_WR_DATA = 3'd4,
                     S_DONE    = 3'd5;

    localparam [1:0] HTRANS_IDLE   = 2'b00,
                     HTRANS_NONSEQ = 2'b10;

    reg [2:0]  state;
    reg [31:0] src;
    reg [31:0] dst;
    reg [31:0] len;
    reg [31:0] count;
    reg [31:0] data_buf;

    wire [31:0] offset     = {count[29:0], 2'b00};
    wire [31:0] count_next = count + 32'd1;
    wire        accepted   = HGRANT && HREADY;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state    <= S_IDLE;
            src      <= 32'b0;
            dst      <= 32'b0;
            len      <= 32'b0;
            count    <= 32'b0;
            data_buf <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (dmac_start) begin
                        src   <= dmac_src;
                        dst   <= dmac_dst;
                        len   <= dmac_len;
                        count <= 32'b0;
                        state <= (dmac_len == 32'b0) ? S_DONE : S_RD_ADDR;
                    end
                end

                S_RD_ADDR:
                    if (accepted)
                        state <= S_RD_DATA;

                S_RD_DATA:
                    if (HREADY) begin
                        data_buf <= HRDATA;
                        state    <= S_WR_ADDR;
                    end

                S_WR_ADDR:
                    if (accepted)
                        state <= S_WR_DATA;

                S_WR_DATA:
                    if (HREADY) begin
                        count <= count_next;
                        state <= (count_next == len) ? S_DONE : S_RD_ADDR;
                    end

                default:   // S_DONE
                    state <= S_IDLE;
            endcase
        end
    end

    assign HBUSREQ = (state == S_RD_ADDR) || (state == S_RD_DATA) ||
                     (state == S_WR_ADDR) || (state == S_WR_DATA);
    assign HTRANS  = ((state == S_RD_ADDR) || (state == S_WR_ADDR)) ? HTRANS_NONSEQ : HTRANS_IDLE;
    assign HWRITE  = (state == S_WR_ADDR);
    assign HSIZE   = 3'b010;
    assign HADDR   = (state == S_WR_ADDR) ? (dst + offset) : (src + offset);
    assign HWDATA  = data_buf;

    assign dmac_busy = (state != S_IDLE);
    assign dmac_done = (state == S_DONE);

endmodule
