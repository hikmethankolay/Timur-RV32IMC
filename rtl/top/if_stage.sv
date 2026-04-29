module if_stage(
    input         clk,
    input         rst_n,
    input         pc_en,
    input         branch_taken,
    input  [31:0] branch_target,
    output [31:0] instruction,
    output [31:0] pc_current,
    output [31:0] pc_instr,
    output        HREADY_ROM,
    output        if_id_flush
);
    wire [31:0] pc_next, pc_plus4;
    wire        HRESP;
    wire        HSEL_ROM = (pc_current[31:16] == 16'h0000);

    // ─── PC redirect mux ─────────────────────────────────────────────
    mux2 #(.WIDTH(32)) pc_next_mux(
        .in0(pc_plus4),
        .in1(branch_target),
        .sel(branch_taken),
        .out(pc_next)
    );

    pc program_counter(
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (pc_en),
        .pc_next(pc_next),
        .pc     (pc_current)
    );

    wire [1:0] htrans_rom = pc_en ? 2'b10 : 2'b00;

    rom_ahb program_memory(
        .HCLK    (clk),
        .HRESETn (rst_n),
        .HSEL    (HSEL_ROM),
        .HADDR   (pc_current),
        .HTRANS  (htrans_rom),
        .HWRITE  (1'b0),
        .HSIZE   (3'b010),
        .HWDATA  (32'b0),
        .HRDATA  (instruction),
        .HREADY  (HREADY_ROM),
        .HRESP   (HRESP)
    );

    reg [31:0] pc_instr_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            pc_instr_reg <= 32'b0;
        else if (branch_taken) pc_instr_reg <= 32'b0;
        else if (pc_en)        pc_instr_reg <= pc_current;
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

    // ─── IF/ID flush extension ───────────────────────────────────────
    reg branch_flush_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) branch_flush_d <= 1'b0;
        else        branch_flush_d <= branch_taken;
    end
    assign if_id_flush = branch_taken | branch_flush_d;

endmodule
