// Instruction ROM (Phase 3; split banks for the C extension, Phase 11).
// 64 KB stored as two 16-bit banks of 16384 entries: LO holds the halfwords
// at byte offsets 0 mod 4, HI those at 2 mod 4. Each bank has two
// synchronous read ports.
//   Fetch port : dedicated to IF (Harvard fetch, never waits for the bus).
//                The 32 bits at byte address A are LO[(A + 2) >> 2] and
//                HI[A >> 2], ordered by A[1], so any halfword-aligned window
//                (a 16-bit instruction, or a 32-bit one straddling two words)
//                is read in one cycle. The fetch logic supplies both indexes.
//   AHB port   : read-only AHB-Lite slave for data loads (.rodata, the .data
//                initial values copied by crt0) and DMAC reads; it reads
//                {HI[w], LO[w]}, an ordinary word.
// Every port registers its address inside the M9K; the outputs are not
// registered. Memory read registers have no reset (M9K cannot reset them).
module rom_ahb (
    input         HCLK,
    input         HRESETn,

    // Fetch port
    input  [13:0] fetch_lo_index,  // (A + 2) >> 2
    input  [13:0] fetch_hi_index,  // A >> 2
    input         fetch_odd,       // A[1]
    output [31:0] fetch_window,    // 32 bits at the address presented on the previous edge

    // AHB-Lite slave port
    input         HSEL,
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,       // writes are ignored
    input  [2:0]  HSIZE,
    input  [31:0] HWDATA,
    input         HREADY,
    output [31:0] HRDATA,
    output        HREADYOUT,
    output        HRESP
);

    (* ramstyle = "M9K", ram_init_file = "rom_lo.mif" *) reg [15:0] lo [0:16383];
    (* ramstyle = "M9K", ram_init_file = "rom_hi.mif" *) reg [15:0] hi [0:16383];

    // Simulation image: unused halfwords read as 0000 (an illegal instruction),
    // the same fill as the .mif files; then rom_lo.hex and rom_hi.hex.
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1) begin
            lo[i] = 16'h0000;
            hi[i] = 16'h0000;
        end
        $readmemh("rom_lo.hex", lo);
        $readmemh("rom_hi.hex", hi);
    end
    // synthesis translate_on

    // Address phase accepted only with HSEL, HTRANS[1] and HREADY all set.
    // Between accepted transfers the data port re-reads the last accepted
    // index, so HRDATA holds. Every port reads unconditionally in one block:
    // an enable on a read makes Quartus build single-port copies of a bank
    // (twice the M9K blocks) instead of one dual-port ROM per bank.
    wire        accept = HSEL && HTRANS[1] && HREADY;
    reg  [13:0] data_index;
    wire [13:0] data_read_index = accept ? HADDR[15:2] : data_index;

    always @(posedge HCLK)
        if (accept)
            data_index <= HADDR[15:2];

    reg [15:0] lo_fetch_q, hi_fetch_q;
    reg [15:0] lo_data_q,  hi_data_q;
    reg        odd_q;

    always @(posedge HCLK) begin
        lo_fetch_q <= lo[fetch_lo_index];
        hi_fetch_q <= hi[fetch_hi_index];
        lo_data_q  <= lo[data_read_index];
        hi_data_q  <= hi[data_read_index];
        odd_q      <= fetch_odd;
    end

    assign fetch_window = odd_q ? {lo_fetch_q, hi_fetch_q} : {hi_fetch_q, lo_fetch_q};
    assign HRDATA       = {hi_data_q, lo_data_q};
    assign HREADYOUT    = 1'b1;
    assign HRESP        = 1'b0;

endmodule
