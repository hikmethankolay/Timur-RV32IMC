module if_stage(
    input         clk,
    input         rst_n,
    input  [31:0] pc_next,
    output [31:0] instruction,
    output [31:0] pc_current,
    output [31:0] pc_instr,
    output [31:0] pc_plus4
);
    wire HRESP;
    wire HREADY_ROM;
    wire HSEL_ROM = (pc_current[31:16] == 16'h0000);

    pc program_counter(
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (1'b1),
        .pc_next(pc_next),
        .pc     (pc_current)
    );

    rom_ahb program_memory(
        .HCLK    (clk),
        .HRESETn (rst_n),
        .HSEL    (HSEL_ROM),
        .HADDR   (pc_current),
        .HTRANS  (2'b10),
        .HWRITE  (1'b0),
        .HSIZE   (3'b010),
        .HWDATA  (32'b0),
        .HRDATA  (instruction),
        .HREADY  (HREADY_ROM),
        .HRESP   (HRESP)
    );

    // pc_instr lags pc_current by one cycle so it matches the instruction
    // returned by the AHB ROM, whose HRDATA is one cycle behind HADDR.
    reg [31:0] pc_instr_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_instr_reg <= 32'b0;
        else        pc_instr_reg <= pc_current;
    end
    assign pc_instr = pc_instr_reg;

    adder_32bit pc_plus4_adder(
        .a       (pc_current),
        .b       (32'h00000004),
        .sub     (1'b0),
        .result  (pc_plus4),
        .cout    (),
        .overflow()
    );
endmodule
