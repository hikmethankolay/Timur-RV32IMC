// ALU decoder (Phase 4).
// op5 (opcode bit 5) separates R-type (1) from I-type arithmetic (0): for
// I-type, funct7 holds immediate bits, so SUB and the M extension are only
// decoded when op5 = 1 (ADDI -5 stays ADD; ADDI 40 does not become MUL).
module alu_decoder (
    input      [1:0] ALUOp,       // 00 ADD, 01 SUB, 10 decode funct fields
    input      [2:0] funct3,
    input      [6:0] funct7,
    input            op5,
    output reg [4:0] ALUControl
);

    always @(*) begin
        case (ALUOp)
            2'b00: ALUControl = 5'b00010;   // ADD
            2'b01: ALUControl = 5'b00110;   // SUB
            2'b10: begin
                if (op5 && funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000:  ALUControl = 5'b10000;   // MUL
                        3'b001:  ALUControl = 5'b10001;   // MULH
                        3'b010:  ALUControl = 5'b10010;   // MULHSU
                        3'b011:  ALUControl = 5'b10011;   // MULHU
                        3'b100:  ALUControl = 5'b10100;   // DIV
                        3'b101:  ALUControl = 5'b10101;   // DIVU
                        3'b110:  ALUControl = 5'b10110;   // REM
                        default: ALUControl = 5'b10111;   // REMU
                    endcase
                end else begin
                    case (funct3)
                        3'b000:  ALUControl = (op5 && funct7[5]) ? 5'b00110    // SUB
                                                                 : 5'b00010;   // ADD / ADDI
                        3'b001:  ALUControl = 5'b01001;                        // SLL / SLLI
                        3'b010:  ALUControl = 5'b00111;                        // SLT / SLTI
                        3'b011:  ALUControl = 5'b01100;                        // SLTU / SLTIU
                        3'b100:  ALUControl = 5'b01000;                        // XOR / XORI
                        3'b101:  ALUControl = funct7[5] ? 5'b01011             // SRA / SRAI
                                                        : 5'b01010;            // SRL / SRLI
                        3'b110:  ALUControl = 5'b00001;                        // OR / ORI
                        default: ALUControl = 5'b00000;                        // AND / ANDI
                    endcase
                end
            end
            default: ALUControl = 5'b00010;
        endcase
    end

endmodule
