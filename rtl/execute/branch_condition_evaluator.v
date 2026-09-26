// Branch condition evaluator (Phase 2).
// Inputs are the two results of one compare of rs1 with rs2: equal, and less
// (signed for BLT/BGE, unsigned for BLTU/BGEU; the comparator chooses by
// funct3[1]). BranchType is the branch funct3.
module branch_condition_evaluator (
    input        equal,        // rs1 == rs2
    input        less,         // rs1 < rs2, signed or unsigned as the branch needs
    input  [2:0] BranchType,
    output reg   BranchTaken
);

    always @(*) begin
        case (BranchType)
            3'b000:  BranchTaken = equal;       // BEQ
            3'b001:  BranchTaken = !equal;      // BNE
            3'b100:  BranchTaken = less;        // BLT
            3'b101:  BranchTaken = !less;       // BGE
            3'b110:  BranchTaken = less;        // BLTU
            3'b111:  BranchTaken = !less;       // BGEU
            default: BranchTaken = 1'b0;        // 010, 011: illegal
        endcase
    end

endmodule
