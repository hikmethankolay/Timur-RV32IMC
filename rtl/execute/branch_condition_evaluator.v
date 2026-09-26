// Branch condition evaluator (Phase 2).
// Inputs come from an ALU subtraction a - b; BranchType is the branch funct3.
module branch_condition_evaluator (
    input        zero,
    input        alu_result_msb,
    input        overflow,
    input        cout,
    input  [2:0] BranchType,
    output reg   BranchTaken
);

    always @(*) begin
        case (BranchType)
            3'b000:  BranchTaken = zero;                           // BEQ
            3'b001:  BranchTaken = ~zero;                          // BNE
            3'b100:  BranchTaken = alu_result_msb ^ overflow;      // BLT
            3'b101:  BranchTaken = ~(alu_result_msb ^ overflow);   // BGE
            3'b110:  BranchTaken = ~cout;                          // BLTU
            3'b111:  BranchTaken = cout;                           // BGEU
            default: BranchTaken = 1'b0;                           // 010, 011: illegal
        endcase
    end

endmodule
