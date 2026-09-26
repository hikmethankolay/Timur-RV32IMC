// GPIO APB slave (Phase 8).
//   0x00 GPIO_OUT  R/W  drives gpio_out[9:0] -> LEDR[9:0]
//   0x04 GPIO_IN   R    gpio_in[9:0] <- SW[9:0], through a two-flop synchroniser
//   0x08 GPIO_DIR  R/W  reserved for header pins (LEDs and switches are fixed-direction)
// Writes take effect at the end of ACCESS; reads are combinational from the
// register selected by PADDR. Registers are decoded on PADDR[7:2]: APB3 has no
// byte strobes, so every write is a whole-register write.
module gpio_apb (
    input             PCLK,
    input             PRESETn,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PADDR,
    input      [31:0] PWDATA,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,
    output     [9:0]  gpio_out,
    input      [9:0]  gpio_in
);

    localparam [5:0] REG_OUT = 6'h00,   // 0x00
                     REG_IN  = 6'h01,   // 0x04
                     REG_DIR = 6'h02;   // 0x08

    reg [9:0] out_reg;
    reg [9:0] dir_reg;
    reg [9:0] in_meta;
    reg [9:0] in_sync;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            in_meta <= 10'b0;
            in_sync <= 10'b0;
        end else begin
            in_meta <= gpio_in;
            in_sync <= in_meta;
        end
    end

    wire write_en = PSEL && PENABLE && PWRITE;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            out_reg <= 10'b0;
            dir_reg <= 10'b0;
        end else if (write_en) begin
            case (PADDR[7:2])
                REG_OUT: out_reg <= PWDATA[9:0];
                REG_DIR: dir_reg <= PWDATA[9:0];
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (PADDR[7:2])
            REG_OUT: PRDATA = {22'b0, out_reg};
            REG_IN:  PRDATA = {22'b0, in_sync};
            REG_DIR: PRDATA = {22'b0, dir_reg};
            default: PRDATA = 32'b0;
        endcase
    end

    assign PREADY   = 1'b1;
    assign PSLVERR  = 1'b0;
    assign gpio_out = out_reg;

endmodule
