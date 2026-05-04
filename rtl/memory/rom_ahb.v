module rom_ahb (
    input         HCLK,
    input         HRESETn,

    // ── Port A : I-Bus ──────────────────────────────────────────────────────
    input         HSEL_a,
    input  [31:0] HADDR_a,
    input  [1:0]  HTRANS_a,
    input         HWRITE_a,
    input  [2:0]  HSIZE_a,
    input  [31:0] HWDATA_a,
    output [31:0] HRDATA_a,
    output        HREADY_a,
    output        HRESP_a,

    // ── Port B : D-Bus ──────────────────────────────────────────────────────
    input         HSEL_b,
    input  [31:0] HADDR_b,
    input  [1:0]  HTRANS_b,
    input         HWRITE_b,
    input  [2:0]  HSIZE_b,
    input  [31:0] HWDATA_b,
    output [31:0] HRDATA_b,
    output        HREADY_b,
    output        HRESP_b
);

    (* ramstyle = "M9K" *) reg [31:0] mem_a [0:16383];
    (* ramstyle = "M9K" *) reg [31:0] mem_b [0:16383];

    initial begin
        $readmemh("test_rom.hex", mem_a);
        $readmemh("test_rom.hex", mem_b);
    end

    wire active_a = HSEL_a & HTRANS_a[1];
    wire active_b = HSEL_b & HTRANS_b[1];

    // Port A read
    reg [31:0] rdata_a;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            rdata_a <= 32'b0;
        else if (active_a && !HWRITE_a)
            rdata_a <= mem_a[HADDR_a[15:2]];
    end

    // Port B read
    reg [31:0] rdata_b;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            rdata_b <= 32'b0;
        else if (active_b && !HWRITE_b)
            rdata_b <= mem_b[HADDR_b[15:2]];
    end

    assign HRDATA_a = rdata_a;
    assign HREADY_a = 1'b1;
    assign HRESP_a  = 1'b0;

    assign HRDATA_b = rdata_b;
    assign HREADY_b = 1'b1;
    assign HRESP_b  = 1'b0;

endmodule
