// Store aligner (Phase 3, MEM stage).
// Replicates the store data onto every byte lane so the slave's byte enables
// pick the right lane whatever the offset. HSIZE carries only the size
// (funct3[1:0]); it is driven by cpu_ahb_master.
module store_aligner (
    input      [2:0]  funct3,   // 000 SB, 001 SH, 010 SW
    input      [31:0] rs2,      // forwarded store data from EX/MEM
    output reg [31:0] hwdata
);

    always @(*) begin
        case (funct3[1:0])
            2'b00:   hwdata = {4{rs2[7:0]}};    // SB: byte into all four lanes
            2'b01:   hwdata = {2{rs2[15:0]}};   // SH: halfword into both halves
            default: hwdata = rs2;              // SW
        endcase
    end

endmodule
