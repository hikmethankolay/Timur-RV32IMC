// Data RAM (Phase 3): 64 KB as four byte-lane arrays of 16384 x 8, one per
// byte of the word, so the per-lane write enables map directly onto M9K.
//   Address phase: accepted with HSEL & HTRANS[1] & HREADY; a read starts the
//                  synchronous read of all four lanes, a write registers its
//                  index and byte enables.
//   Data phase   : a write stores HWDATA at the registered index on the
//                  enabled lanes; a read drives the raw 32-bit word on HRDATA.
// Byte/halfword selection and sign extension happen in the CPU (Phase 3).
module ram_ahb (
    input         HCLK,
    input         HRESETn,
    input         HSEL,
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input  [31:0] HWDATA,
    input         HREADY,
    output [31:0] HRDATA,
    output        HREADYOUT,
    output        HRESP
);

    (* ramstyle = "M9K" *) reg [7:0] lane0 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] lane1 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] lane2 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] lane3 [0:16383];

    wire        accept = HSEL & HTRANS[1] & HREADY;
    wire [13:0] index  = HADDR[15:2];

    // Byte enables from HSIZE and HADDR[1:0].
    reg [3:0] byte_en;
    always @(*) begin
        case (HSIZE)
            3'b000:  byte_en = 4'b0001 << HADDR[1:0];           // byte
            3'b001:  byte_en = HADDR[1] ? 4'b1100 : 4'b0011;    // halfword
            3'b010:  byte_en = 4'b1111;                         // word
            default: byte_en = 4'b0000;
        endcase
    end

    // ---------------------------------------------------------------------
    // Address phase: register the write for its data phase
    // ---------------------------------------------------------------------
    reg        wr_pending;
    reg [13:0] wr_index;
    reg [3:0]  wr_be;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            wr_pending <= 1'b0;
            wr_index   <= 14'b0;
            wr_be      <= 4'b0;
        end else if (HREADY) begin
            wr_pending <= accept & HWRITE;
            wr_index   <= index;
            wr_be      <= byte_en;
        end
    end

    // ---------------------------------------------------------------------
    // Data phase write: HWDATA is valid now, one cycle after the address.
    // Kept free of reset and extra logic so each lane infers as M9K.
    // ---------------------------------------------------------------------
    always @(posedge HCLK) begin
        if (wr_pending) begin
            if (wr_be[0]) lane0[wr_index] <= HWDATA[7:0];
            if (wr_be[1]) lane1[wr_index] <= HWDATA[15:8];
            if (wr_be[2]) lane2[wr_index] <= HWDATA[23:16];
            if (wr_be[3]) lane3[wr_index] <= HWDATA[31:24];
        end
    end

    // ---------------------------------------------------------------------
    // Synchronous read in the address phase (M9K registers the address; the
    // output is not registered). No reset on the read registers.
    // ---------------------------------------------------------------------
    wire read_accept = accept & ~HWRITE;

    reg [7:0] rd0, rd1, rd2, rd3;
    always @(posedge HCLK) begin
        if (read_accept) begin
            rd0 <= lane0[index];
            rd1 <= lane1[index];
            rd2 <= lane2[index];
            rd3 <= lane3[index];
        end
    end

    // ---------------------------------------------------------------------
    // Read-after-write bypass. A load right behind a store to the same word
    // has its address phase in the store's data phase: the memory returns the
    // old contents on the same edge the new data is written. Captured
    // alongside the read: the lanes and data being written this cycle, merged
    // over the memory output in the data phase (logic after the read output
    // does not affect M9K inference).
    // ---------------------------------------------------------------------
    reg        byp_hit;
    reg [3:0]  byp_be;
    reg [31:0] byp_data;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            byp_hit <= 1'b0;
        else if (read_accept)
            byp_hit <= wr_pending && (wr_index == index);
    end

    always @(posedge HCLK) begin
        if (read_accept) begin
            byp_be   <= wr_be;
            byp_data <= HWDATA;
        end
    end

    assign HRDATA[7:0]   = (byp_hit && byp_be[0]) ? byp_data[7:0]   : rd0;
    assign HRDATA[15:8]  = (byp_hit && byp_be[1]) ? byp_data[15:8]  : rd1;
    assign HRDATA[23:16] = (byp_hit && byp_be[2]) ? byp_data[23:16] : rd2;
    assign HRDATA[31:24] = (byp_hit && byp_be[3]) ? byp_data[31:24] : rd3;

    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

endmodule
