// Instruction ROM (Phase 3): one 16384 x 32 array (64 KB) with two
// synchronous read ports.
//   Fetch port : dedicated to IF (Harvard fetch, never waits for the bus).
//   AHB port   : read-only AHB-Lite slave for data loads (.rodata, the .data
//                initial values copied by crt0) and DMAC reads.
// Both ports register their address inside the M9K; the outputs are not
// registered. Memory read registers have no reset (M9K cannot reset them).
module rom_ahb (
    input         HCLK,
    input         HRESETn,      // AHB-Lite slave convention; nothing to reset here

    // Fetch port
    input  [31:0] fetch_addr,   // byte address (word index = bits [15:2])
    output [31:0] fetch_instr,  // word at the address presented on the previous edge

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

    (* ramstyle = "M9K", ram_init_file = "rom.mif" *) reg [31:0] mem [0:16383];

    // Simulation image: unused words read as 0x00000000 (an illegal
    // instruction), the same fill as rom.mif; then rom.hex, one word per line.
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1)
            mem[i] = 32'h00000000;
        $readmemh("rom.hex", mem);
    end
    // synthesis translate_on

    // Address phase accepted only with HSEL, HTRANS[1] and HREADY all set.
    // Between accepted transfers the data port re-reads the last accepted
    // index, so HRDATA holds. Both ports read unconditionally in one block:
    // an enable on either read makes Quartus build two single-port ROMs
    // (twice the M9K blocks) instead of one dual-port ROM.
    wire        accept = HSEL && HTRANS[1] && HREADY;
    reg  [13:0] data_index;
    wire [13:0] data_read_index = accept ? HADDR[15:2] : data_index;

    always @(posedge HCLK)
        if (accept)
            data_index <= HADDR[15:2];

    reg [31:0] fetch_q;
    reg [31:0] data_q;

    always @(posedge HCLK) begin
        fetch_q <= mem[fetch_addr[15:2]];
        data_q  <= mem[data_read_index];
    end

    assign fetch_instr = fetch_q;
    assign HRDATA      = data_q;
    assign HREADYOUT   = 1'b1;
    assign HRESP       = 1'b0;

endmodule
