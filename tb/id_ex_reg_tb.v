`timescale 1ns/1ps
//
// id_ex_reg_tb: every ID/EX field is carried unchanged (5-bit ALUControl,
// funct3, controls), hold with enable = 0, flush and reset give a bubble with
// every control 0 (Phase 6).
// Vector: rst_n enable flush (bin) in_seed(hex) expect(bin) exp_seed(hex) wait_type
//
module id_ex_reg_tb;

    reg         clk, rst_n, enable, flush;

    reg  [31:0] pc_in, rs1_data_in, rs2_data_in, imm_in;
    reg  [4:0]  rs1_addr_in, rs2_addr_in, rd_addr_in;
    reg  [2:0]  funct3_in;
    reg  [11:0] csr_addr_in;
    reg  [4:0]  ALUControl_in;
    reg  [1:0]  ALUSrcA_in;
    reg         ALUSrcB_in, Branch_in, Jump_in, Jalr_in;
    reg         MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in;
    reg         CSRAccess_in;
    reg  [1:0]  CSROp_in;
    reg         CSRImm_in, IsECALL_in, IsEBREAK_in, IsMRET_in, Illegal_in, valid_in;

    wire [31:0] pc_out, rs1_data_out, rs2_data_out, imm_out;
    wire [4:0]  rs1_addr_out, rs2_addr_out, rd_addr_out;
    wire [2:0]  funct3_out;
    wire [11:0] csr_addr_out;
    wire [4:0]  ALUControl_out;
    wire [1:0]  ALUSrcA_out;
    wire        ALUSrcB_out, Branch_out, Jump_out, Jalr_out;
    wire        MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out;
    wire        CSRAccess_out;
    wire [1:0]  CSROp_out;
    wire        CSRImm_out, IsECALL_out, IsEBREAK_out, IsMRET_out, Illegal_out, valid_out;

    id_ex_reg dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .flush          (flush),
        .pc_in          (pc_in),
        .rs1_data_in    (rs1_data_in),
        .rs2_data_in    (rs2_data_in),
        .imm_in         (imm_in),
        .rs1_addr_in    (rs1_addr_in),
        .rs2_addr_in    (rs2_addr_in),
        .rd_addr_in     (rd_addr_in),
        .funct3_in      (funct3_in),
        .csr_addr_in    (csr_addr_in),
        .ALUControl_in  (ALUControl_in),
        .ALUSrcA_in     (ALUSrcA_in),
        .ALUSrcB_in     (ALUSrcB_in),
        .Branch_in      (Branch_in),
        .Jump_in        (Jump_in),
        .Jalr_in        (Jalr_in),
        .MemRead_in     (MemRead_in),
        .MemWrite_in    (MemWrite_in),
        .MemToReg_in    (MemToReg_in),
        .RegWrite_in    (RegWrite_in),
        .CSRAccess_in   (CSRAccess_in),
        .CSROp_in       (CSROp_in),
        .CSRImm_in      (CSRImm_in),
        .IsECALL_in     (IsECALL_in),
        .IsEBREAK_in    (IsEBREAK_in),
        .IsMRET_in      (IsMRET_in),
        .Illegal_in     (Illegal_in),
        .valid_in       (valid_in),
        .pc_out         (pc_out),
        .rs1_data_out   (rs1_data_out),
        .rs2_data_out   (rs2_data_out),
        .imm_out        (imm_out),
        .rs1_addr_out   (rs1_addr_out),
        .rs2_addr_out   (rs2_addr_out),
        .rd_addr_out    (rd_addr_out),
        .funct3_out     (funct3_out),
        .csr_addr_out   (csr_addr_out),
        .ALUControl_out (ALUControl_out),
        .ALUSrcA_out    (ALUSrcA_out),
        .ALUSrcB_out    (ALUSrcB_out),
        .Branch_out     (Branch_out),
        .Jump_out       (Jump_out),
        .Jalr_out       (Jalr_out),
        .MemRead_out    (MemRead_out),
        .MemWrite_out   (MemWrite_out),
        .MemToReg_out   (MemToReg_out),
        .RegWrite_out   (RegWrite_out),
        .CSRAccess_out  (CSRAccess_out),
        .CSROp_out      (CSROp_out),
        .CSRImm_out     (CSRImm_out),
        .IsECALL_out    (IsECALL_out),
        .IsEBREAK_out   (IsEBREAK_out),
        .IsMRET_out     (IsMRET_out),
        .Illegal_out    (Illegal_out),
        .valid_out      (valid_out)
    );

    always #5 clk = ~clk;

    // Field values derived from a seed, packed in port order (182 bits).
    function [181:0] fields;
        input [31:0] s;
        fields = {s, s ^ 32'h5555AAAA, ~s, {s[15:0], s[31:16]},
                  s[4:0], s[9:5], s[14:10], s[17:15], s[29:18],
                  s[24:20] ^ 5'b10101, s[1:0], s[2],
                  s[3], s[4], s[5],
                  s[6], s[7], s[8], s[9],
                  s[10], s[12:11], s[13],
                  s[14], s[15], s[16], s[17],
                  s[31]};
    endfunction

    wire [181:0] got = {pc_out, rs1_data_out, rs2_data_out, imm_out,
                        rs1_addr_out, rs2_addr_out, rd_addr_out, funct3_out, csr_addr_out,
                        ALUControl_out, ALUSrcA_out, ALUSrcB_out,
                        Branch_out, Jump_out, Jalr_out,
                        MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out,
                        CSRAccess_out, CSROp_out, CSRImm_out,
                        IsECALL_out, IsEBREAK_out, IsMRET_out, Illegal_out,
                        valid_out};

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      in_seed, exp_seed;
    reg             expect_fields, wait_type;
    reg [181:0]     exp;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        enable = 1'b0;
        flush = 1'b0;
        {pc_in, rs1_data_in, rs2_data_in, imm_in,
         rs1_addr_in, rs2_addr_in, rd_addr_in, funct3_in, csr_addr_in,
         ALUControl_in, ALUSrcA_in, ALUSrcB_in,
         Branch_in, Jump_in, Jalr_in,
         MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in,
         CSRAccess_in, CSROp_in, CSRImm_in,
         IsECALL_in, IsEBREAK_in, IsMRET_in, Illegal_in,
         valid_in} = 182'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/id_ex_reg_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/id_ex_reg_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %h %b %h %b", rst_n, enable, flush, in_seed,
                            expect_fields, exp_seed, wait_type) == 7) begin
                    {pc_in, rs1_data_in, rs2_data_in, imm_in,
                     rs1_addr_in, rs2_addr_in, rd_addr_in, funct3_in, csr_addr_in,
                     ALUControl_in, ALUSrcA_in, ALUSrcB_in,
                     Branch_in, Jump_in, Jalr_in,
                     MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in,
                     CSRAccess_in, CSROp_in, CSRImm_in,
                     IsECALL_in, IsEBREAK_in, IsMRET_in, Illegal_in,
                     valid_in} = fields(in_seed);
                    exp = expect_fields ? fields(exp_seed) : 182'b0;
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b en=%b flush=%b seed=%h | got=%h | expected=%h",
                                 rst_n, enable, flush, in_seed, got, exp);
                    end else
                        $display("PASS rst_n=%b en=%b flush=%b seed=%h | pc=%h ALUControl=%b funct3=%b valid=%b",
                                 rst_n, enable, flush, in_seed, pc_out, ALUControl_out, funct3_out, valid_out);
                end
            end
            $fclose(fd);
        end

        if (total == 0)
            $display("FAIL no test vectors were applied");
        if (failed == 0 && total > 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $stop;
    end

endmodule
