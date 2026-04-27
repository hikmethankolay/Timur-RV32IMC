// ─────────────────────────────────────────────────────────────────────────────
// if_stage
// ─────────────────────────────────────────────────────────────────────────────
// Instruction-Fetch stage. Owns:
//   - pc                : 32-bit program counter
//   - rom_ahb           : AHB-Lite ROM slave (1-cycle HRDATA latency)
//   - pc_plus4_adder    : sequential next-PC
//   - pc_instr_reg      : data-phase shadow PC (matches HRDATA latency)
//   - pc_next mux       : selects pc_plus4 vs branch_target on redirect
//   - branch_flush_d    : 1-cycle extension of branch_flush so the stale
//                         post-redirect HRDATA is also flushed from IF/ID
//
// branch_taken/branch_target come from the EX/MEM-stage branch resolution.
// if_id_flush is exported so the datapath can drive IF/ID's flush rail
// (covers both the redirect cycle AND the cycle after, for AHB ROM latency).
// ─────────────────────────────────────────────────────────────────────────────
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
    // PC redirect: branch_taken drives a 1-cycle redirect to the branch
    // target captured in EX/MEM. Otherwise PC advances by 4.
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

    // pc_instr lags pc_current by one cycle to match the AHB ROM's HRDATA
    // latency. Treated as a true pipeline register: cleared on branch_taken
    // (paired with IF/ID flush on a branch redirect) and frozen when pc_en
    // is low (paired with PC freeze on a stall).
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
    // Because the AHB ROM has 1-cycle read latency, the cycle AFTER a
    // redirect still has stale HRDATA (the wrong-path fetch). Without
    // a second flush cycle, that stale instruction would be latched
    // into IF/ID. branch_flush_d extends the IF/ID flush window by one
    // cycle so that stale instruction is dropped (Bug #3).
    reg branch_flush_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) branch_flush_d <= 1'b0;
        else        branch_flush_d <= branch_taken;
    end
    assign if_id_flush = branch_taken | branch_flush_d;

endmodule
