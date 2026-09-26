// AHB bus mux (Phase 9).
// Address and control follow the address-phase owner (HMASTER). HWDATA
// belongs to the data phase and follows HMASTER_DATA; selecting it with
// HMASTER would send the wrong master's write data whenever ownership changes
// on the same edge as a write. HRDATA and HREADY go back to both masters
// straight from the decoder.
module ahb_bus_mux (
    input         HMASTER,        // 0 CPU, 1 DMAC
    input         HMASTER_DATA,

    // master 0: CPU data port
    input  [31:0] HADDR_CPU,
    input  [1:0]  HTRANS_CPU,
    input         HWRITE_CPU,
    input  [2:0]  HSIZE_CPU,
    input  [31:0] HWDATA_CPU,

    // master 1: DMAC
    input  [31:0] HADDR_DMAC,
    input  [1:0]  HTRANS_DMAC,
    input         HWRITE_DMAC,
    input  [2:0]  HSIZE_DMAC,
    input  [31:0] HWDATA_DMAC,

    // to the decoder and all slaves
    output [31:0] HADDR,
    output [1:0]  HTRANS,
    output        HWRITE,
    output [2:0]  HSIZE,
    output [31:0] HWDATA
);

    assign HADDR  = HMASTER      ? HADDR_DMAC  : HADDR_CPU;
    assign HTRANS = HMASTER      ? HTRANS_DMAC : HTRANS_CPU;
    assign HWRITE = HMASTER      ? HWRITE_DMAC : HWRITE_CPU;
    assign HSIZE  = HMASTER      ? HSIZE_DMAC  : HSIZE_CPU;
    assign HWDATA = HMASTER_DATA ? HWDATA_DMAC : HWDATA_CPU;

endmodule
