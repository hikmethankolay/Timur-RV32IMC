// Instruction fetch: PC mux, 1-cycle AHB ROM, PC tag delayed to match HRDATA, extended IF/ID flush after branch.
module if_stage (
    input         clk_i,
    input         rst_n_i,
    input         fetch_run_i,    // 0 = hold PC (global stall)
    input         br_taken_i,     // Pulse from MEM: redirect PC
    input  [31:0] jmp_pc_i,       // Target from MEM (resolved JALR / B / JAL)
    output [31:0] instr_f_o,      // Opcode word (1-cycle ROM latency)
    output [31:0] pc_fetch_o,     // Address presented to ROM this cycle
    output [31:0] pc_tag_delay_o, // PC that pairs with instr_f_o (lags fetch addr)
    output        rom_ready_o,
    output        flush_if_id_o   // Also high cycle after br_taken to drop stale ROM data
);
    wire [31:0] pc_next_w, pc_plus4_w;
    wire        hresp_w;
    wire        sel_rom_w = (pc_fetch_o[31:16] == 16'h0000); // Code in low 64 KiB
    wire [1:0]  htrans_w = fetch_run_i ? 2'b10 : 2'b00;

    mux2 #(.WIDTH(32)) u_pc_mux (
        .in0(pc_plus4_w),
        .in1(jmp_pc_i),
        .sel(br_taken_i),
        .out(pc_next_w)
    );

    pc u_pc (
        .clk    (clk_i),
        .rst_n  (rst_n_i),
        .en     (fetch_run_i),
        .pc_next(pc_next_w),
        .pc     (pc_fetch_o)
    );

    rom_ahb u_imem (
        .HCLK    (clk_i),
        .HRESETn (rst_n_i),
        .HSEL    (sel_rom_w),
        .HADDR   (pc_fetch_o),
        .HTRANS  (htrans_w),
        .HWRITE  (1'b0),
        .HSIZE   (3'b010),
        .HWDATA  (32'b0),
        .HRDATA  (instr_f_o),
        .HREADY  (rom_ready_o),
        .HRESP   (hresp_w)
    );

    // Register PC when fetch runs so IF/ID can latch PC+instr as a matched pair.
    reg [31:0] pc_tag_q;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)            pc_tag_q <= 32'b0;
        else if (br_taken_i)    pc_tag_q <= 32'b0;
        else if (fetch_run_i)   pc_tag_q <= pc_fetch_o;
    end
    assign pc_tag_delay_o = pc_tag_q;

    adder_32bit u_pc_plus4 (
        .a       (pc_fetch_o),
        .b       (32'h4),
        .sub     (1'b0),
        .result  (pc_plus4_w),
        .cout    (),
        .overflow()
    );

    // Stretch flush one cycle: wrong-path instruction still on HRDATA after redirect.
    reg br_taken_dly_q;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) br_taken_dly_q <= 1'b0;
        else          br_taken_dly_q <= br_taken_i;
    end
    assign flush_if_id_o = br_taken_i | br_taken_dly_q;
endmodule
