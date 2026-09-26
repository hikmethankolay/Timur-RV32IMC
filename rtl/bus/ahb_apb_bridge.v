// AHB-to-APB bridge (Phase 9): AHB-Lite slave, APB master, APB decode.
//   IDLE   : HREADYOUT = 1. Accept an address phase (HSEL, HTRANS[1], HREADY):
//            register address and direction -> SETUP
//   SETUP  : HREADYOUT = 0, PSEL = 1, PENABLE = 0. PWDATA = HWDATA (valid now,
//            held by the master) -> ACCESS
//   ACCESS : HREADYOUT = PREADY, PSEL = 1, PENABLE = 1, HRDATA = PRDATA.
//            On PREADY: a new accepted address phase -> SETUP, else -> IDLE
// An APB access therefore costs one wait state. APB decode on PADDR[15:8]:
// 0x00 UART, 0x01 GPIO, 0x02 DMAC registers, anything else no PSEL
// (PRDATA = 0, PREADY = 1). APB3 has no byte strobes: peripheral registers
// are word-write only.
module ahb_apb_bridge (
    input             HCLK,
    input             HRESETn,

    // AHB-Lite slave
    input             HSEL,
    input      [31:0] HADDR,
    input      [1:0]  HTRANS,
    input             HWRITE,
    input      [2:0]  HSIZE,
    input      [31:0] HWDATA,
    input             HREADY,
    output     [31:0] HRDATA,
    output            HREADYOUT,
    output            HRESP,

    // APB master
    output reg [31:0] PADDR,
    output reg        PWRITE,
    output     [31:0] PWDATA,
    output            PENABLE,
    output            PSEL_UART,
    output            PSEL_GPIO,
    output            PSEL_DMAC,
    input      [31:0] PRDATA_UART,
    input      [31:0] PRDATA_GPIO,
    input      [31:0] PRDATA_DMAC,
    input             PREADY_UART,
    input             PREADY_GPIO,
    input             PREADY_DMAC
);

    localparam [1:0] S_IDLE   = 2'd0,
                     S_SETUP  = 2'd1,
                     S_ACCESS = 2'd2;

    reg [1:0] state;

    wire accept = HSEL && HTRANS[1] && HREADY;

    wire sel_uart = (PADDR[15:8] == 8'h00);
    wire sel_gpio = (PADDR[15:8] == 8'h01);
    wire sel_dmac = (PADDR[15:8] == 8'h02);

    wire [31:0] prdata = sel_uart ? PRDATA_UART :
                         sel_gpio ? PRDATA_GPIO :
                         sel_dmac ? PRDATA_DMAC :
                                    32'h00000000;

    wire pready = sel_uart ? PREADY_UART :
                  sel_gpio ? PREADY_GPIO :
                  sel_dmac ? PREADY_DMAC :
                             1'b1;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state  <= S_IDLE;
            PADDR  <= 32'b0;
            PWRITE <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (accept) begin
                        PADDR  <= HADDR;
                        PWRITE <= HWRITE;
                        state  <= S_SETUP;
                    end
                end

                S_SETUP:
                    state <= S_ACCESS;

                default: begin   // S_ACCESS
                    if (pready) begin
                        if (accept) begin
                            PADDR  <= HADDR;
                            PWRITE <= HWRITE;
                            state  <= S_SETUP;
                        end else
                            state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    wire apb_active = (state == S_SETUP) || (state == S_ACCESS);

    assign PSEL_UART = apb_active && sel_uart;
    assign PSEL_GPIO = apb_active && sel_gpio;
    assign PSEL_DMAC = apb_active && sel_dmac;
    assign PENABLE   = (state == S_ACCESS);
    assign PWDATA    = HWDATA;

    assign HRDATA    = prdata;
    assign HREADYOUT = (state == S_IDLE)  ? 1'b1 :
                       (state == S_SETUP) ? 1'b0 :
                                            pready;
    assign HRESP     = 1'b0;

endmodule
