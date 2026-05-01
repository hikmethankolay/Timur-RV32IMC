module ahb2apb_bridge (
    input         HCLK,
    input         HRESETn,
    input         HSEL,
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input  [31:0] HWDATA,
    output [31:0] HRDATA,
    output        HREADY,
    output        HRESP,
    output        PSEL_uart,
    output        PSEL_gpio,
    output        PSEL_dmac,
    output        PENABLE,
    output        PWRITE,
    output [7:0]  PADDR,
    output [31:0] PWDATA,
    input  [31:0] PRDATA_uart,
    input         PREADY_uart,
    input  [31:0] PRDATA_gpio,
    input         PREADY_gpio,
    input  [31:0] PRDATA_dmac,
    input         PREADY_dmac
);

    localparam IDLE     = 2'd0;
    localparam SETUP    = 2'd1;
    localparam ACCESS   = 2'd2;
    localparam COMPLETE = 2'd3;

    reg [1:0]  state;
    reg        hwrite_lat;    // latched from AHB address phase
    reg [31:0] haddr_lat;     // latched HADDR
    reg [31:0] hwdata_lat;    // latched HWDATA

    wire sel_uart = (haddr_lat[9:8] == 2'b00);
    wire sel_gpio = (haddr_lat[9:8] == 2'b01);
    wire sel_dmac = (haddr_lat[9:8] == 2'b10);

    wire apb_active = (state == SETUP) || (state == ACCESS);

    assign PSEL_uart = apb_active & sel_uart;
    assign PSEL_gpio = apb_active & sel_gpio;
    assign PSEL_dmac = apb_active & sel_dmac;
    assign PENABLE   = (state == ACCESS);
    assign PWRITE    = hwrite_lat;
    assign PADDR     = haddr_lat[7:0];
    assign PWDATA    = hwdata_lat;

    assign HRDATA = sel_uart ? PRDATA_uart :
                sel_gpio ? PRDATA_gpio :
                sel_dmac ? PRDATA_dmac :
                32'b0;

    wire pready_sel = sel_uart ? PREADY_uart :
        sel_gpio ? PREADY_gpio :
        sel_dmac ? PREADY_dmac :
        1'b1;

    assign HREADY = (state == IDLE) || (state == COMPLETE);
    assign HRESP  = 1'b0;


    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state <= IDLE;
            haddr_lat  <= 32'b0;
            hwrite_lat <= 1'b0;
            hwdata_lat <= 32'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (HSEL && HTRANS[1]) begin
                        haddr_lat  <= HADDR;
                        hwrite_lat <= HWRITE;
                        state      <= SETUP;
                    end
                end

                SETUP: begin
                    hwdata_lat <= HWDATA;
                    state      <= ACCESS;
                end

                ACCESS: begin
                    if (pready_sel) begin
                        state <= COMPLETE;
                    end
                end

                COMPLETE: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
