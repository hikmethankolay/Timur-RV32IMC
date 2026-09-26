// Load formatter (Phase 3, WB stage).
// Selects the byte or halfword addressed by addr[1:0] from the raw bus word
// and sign- or zero-extends it. Loads from RAM, the ROM data port and APB
// registers all pass through here.
module load_formatter (
    input      [31:0] hrdata,   // raw word from the data bus
    input      [1:0]  addr,     // address bits [1:0]
    input      [2:0]  funct3,   // 000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU
    output reg [31:0] load_data
);

    reg [7:0]  byte_sel;
    reg [15:0] half_sel;

    always @(*) begin
        case (addr)
            2'b00:   byte_sel = hrdata[7:0];
            2'b01:   byte_sel = hrdata[15:8];
            2'b10:   byte_sel = hrdata[23:16];
            default: byte_sel = hrdata[31:24];
        endcase

        half_sel = addr[1] ? hrdata[31:16] : hrdata[15:0];

        case (funct3)
            3'b000:  load_data = {{24{byte_sel[7]}}, byte_sel};    // LB
            3'b001:  load_data = {{16{half_sel[15]}}, half_sel};   // LH
            3'b100:  load_data = {24'b0, byte_sel};                // LBU
            3'b101:  load_data = {16'b0, half_sel};                // LHU
            default: load_data = hrdata;                           // LW
        endcase
    end

endmodule
