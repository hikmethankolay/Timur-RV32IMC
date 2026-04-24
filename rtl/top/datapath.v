module datapath(
    input  clk,
    input  rst_n,
    output [31:0] pc_out
);

    // PC signals
    wire [31:0] pc_current;
    wire [31:0] pc_next;
    wire [31:0] pc_plus4;
    wire [31:0] branch_target;

    // Instruction fetch
    wire [31:0] instruction;

    // Instruction parser outputs
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [6:0] funct7;

    // Immediate generator output
    wire [31:0] imm;

    // Register file outputs
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    // Control signals
    wire        Branch;
    wire        MemRead;
    wire        MemToReg;
    wire [1:0]  ALUOp;
    wire        MemWrite;
    wire        ALUSrc;
    wire        RegWrite;
    wire        CSRWrite;
    wire [1:0]  CSROp;
    wire        IsECALL;
    wire        IsEBREAK;
    wire        IsMRET;

    // ALU decoder output
    wire [4:0]  ALUControl;

    // ALU inputs and outputs
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_result;
    wire        zero;
    wire        cout;
    wire        overflow;
    wire        div_busy;
    wire        div_done;

    // Branch evaluator
    wire        BranchTaken;

    // Memory outputs
    wire [31:0] mem_read_data;

    // Writeback
    wire [31:0] reg_write_data;

    // AHB bus signals
    wire [31:0] HADDR;
    wire [1:0]  HTRANS;
    wire        HWRITE;
    wire [2:0]  HSIZE;
    wire [31:0] HWDATA;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;
    wire        HSEL_ROM;
    wire        HSEL_RAM;

    pc program_counter(
        .clk(clk),
        .rst_n(rst_n),
        .en(1'b1), // TEMPORARY
        .pc_next(pc_next),
        .pc(pc_current)
    );

    rom_ahb program_memory (
        .HCLK    (clk),
        .HRESETn (rst_n),
        .HSEL    (HSEL_ROM),
        .HADDR   (pc_current),
        .HTRANS  (2'b10), // TEMPORARY
        .HWRITE  (1'b0),
        .HSIZE   (3'b010),
        .HWDATA  (32'b0),
        .HRDATA  (instruction),
        .HREADY  (HREADY),
        .HRESP   (HRESP)
    );

    instr_parser instruction_parser(
        .instruction(instruction),
        .opcode(opcode),
        .rd(rd),
        .funct3(funct3),
        .rs1(rs1_addr),
        .rs2(rs2_addr),
        .funct7(funct7)
    );

    imm_gen immediate_generator(
        .instruction(instruction),
        .opcode(opcode),
        .imm(imm) 
    );

    main_control_unit main(
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs2_addr(rs2_addr),
        .Branch(Branch),
        .MemRead(MemRead),
        .MemToReg(MemToReg),
        .ALUOp(ALUOp),
        .MemWrite(MemWrite),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .CSRWrite(CSRWrite),
        .CSROp(CSROp),
        .IsECALL(IsECALL),
        .IsEBREAK(IsEBREAK),
        .IsMRET(IsMRET)
    );

    alu_decoder alu_dec(
        .ALUOp(ALUOp),
        .funct3(funct3),
        .funct7(funct7),
        .ALUControl(ALUControl)
    );

    registers register_memory (
        .clk(clk),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd),
        .rd_data(reg_write_data),
        .reg_write(RegWrite),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    mux2 #(.WIDTH(32)) ALUB_Mux(
        .in0(rs2_data),
        .in1(imm),
        .sel(ALUSrc),
        .out(alu_b)
    );

     mux2 #(.WIDTH(32)) ALUA_Mux(
        .in0(rs1_data),
        .in1(pc_current),
        .sel(opcode == 7'b0010111),
        .out(alu_a)
    );

    alu arithmetic_logic_unit(
        .clk(clk),
        .rst_n(rst_n),
        .a(alu_a),
        .b(alu_b),
        .ALUControl(ALUControl),
        .div_start(1'b0), // TEMPORARY
        .result(alu_result),
        .zero(zero),
        .cout(cout),
        .overflow(overflow),
        .div_busy(div_busy),
        .div_done(div_done)
    );

    branch_condition_evaluator bce(
        .zero(zero),
        .alu_result_msb(alu_result[31]),
        .overflow(overflow),
        .cout(cout),
        .BranchType(funct3),
        .BranchTaken(BranchTaken)
    );

    ram_ahb data_memory(
        .HCLK    (clk),
        .HRESETn (rst_n),
        .HSEL    (HSEL_RAM),
        .HADDR   (alu_result),
        .HTRANS  ((MemRead | MemWrite) ? 2'b10 : 2'b00),
        .HWRITE  (MemWrite),
        .HSIZE   (funct3),
        .HWDATA  (rs2_data),
        .HRDATA  (mem_read_data),
        .HREADY  (HREADY),
        .HRESP   (HRESP)
    );

    assign HSEL_ROM = (pc_current[31:16] == 16'h0000);
    assign HSEL_RAM = (alu_result[31:16] == 16'h2000);

    mux2 #(.WIDTH(32)) memory_to_reg_mux (
        .in0(alu_result),
        .in1(mem_read_data),
        .sel(MemToReg),
        .out(reg_write_data)
    );

    assign pc_out = pc_current;

    adder_32bit pc_plus4_adder (
        .a      (pc_current),
        .b      (32'h00000004),
        .sub    (1'b0),
        .result (pc_plus4),
        .cout   (),
        .overflow ()
    );

    adder_32bit branch_adder (
        .a      (pc_current),
        .b      (imm),
        .sub    (1'b0),
        .result (branch_target),
        .cout   (),
        .overflow ()
    );

    mux2 #(.WIDTH(32)) pc_next_mux (
        .in0 (pc_plus4),
        .in1 (branch_target),
        .sel (Branch & BranchTaken),
        .out (pc_next)
    );

endmodule