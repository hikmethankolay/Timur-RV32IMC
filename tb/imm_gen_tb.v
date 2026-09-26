`timescale 1ns/1ps
//
// imm_gen_tb: immediates for all formats, sign extension, bit 0 of B and J
// immediates (Phase 4).
// Vector: instruction(hex) opcode(hex) imm(hex).
//
module imm_gen_tb;

    reg  [31:0] instruction;
    reg  [6:0]  opcode;
    wire [31:0] imm;

    imm_gen dut (
        .instruction (instruction),
        .opcode      (opcode),
        .imm         (imm)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_imm;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        instruction = 32'b0;
        opcode = 7'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/imm_gen_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/imm_gen_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %h", instruction, opcode, exp_imm) == 3) begin
                    #10;
                    total = total + 1;
                    if (imm !== exp_imm) begin
                        failed = failed + 1;
                        $display("FAIL instr=%h opcode=%h | got=%h expected=%h", instruction, opcode, imm, exp_imm);
                    end else
                        $display("PASS instr=%h opcode=%h | imm=%h", instruction, opcode, imm);
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
