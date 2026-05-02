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

    // Status outputs → dmac_apb STATUS register
    output        dmac_busy,   // High from REQUEST until DONE
    output        dmac_done    // One-cycle pulse when transfer complete
);

endmodule
