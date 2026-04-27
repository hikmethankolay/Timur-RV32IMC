module alu_decoder (
    input  [6:0] opcode,
    input  [1:0] ALUOp,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [4:0] ALUControl
);

    wire is_rtype     = (opcode == 7'b0110011);
    wire is_iarith    = (opcode == 7'b0010011);
    wire is_shift_imm = is_iarith && ((funct3 == 3'b001) || (funct3 == 3'b101));
    wire use_funct7   = is_rtype | is_shift_imm;

    always @(*) begin
        case (ALUOp)

            2'b00: ALUControl = 5'b00010;

            2'b01: ALUControl = 5'b00110;

            2'b10: begin
                if (is_rtype && (funct7 == 7'b0000001)) begin
                    case (funct3)
                        3'b000: ALUControl = 5'b10000; // MUL
                        3'b001: ALUControl = 5'b10001; // MULH
                        3'b010: ALUControl = 5'b10010; // MULHSU
                        3'b011: ALUControl = 5'b10011; // MULHU
                        3'b100: ALUControl = 5'b10100; // DIV
                        3'b101: ALUControl = 5'b10101; // DIVU
                        3'b110: ALUControl = 5'b10110; // REM
                        3'b111: ALUControl = 5'b10111; // REMU
                        default: ALUControl = 5'b00010;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: ALUControl = (use_funct7 && funct7[5]) ? 5'b00110  // SUB
                                                                       : 5'b00010; // ADD / ADDI
                        3'b001: ALUControl = 5'b01001; // SLL  / SLLI
                        3'b010: ALUControl = 5'b00111; // SLT  / SLTI
                        3'b011: ALUControl = 5'b01100; // SLTU / SLTIU
                        3'b100: ALUControl = 5'b01000; // XOR  / XORI
                        3'b101: ALUControl = (use_funct7 && funct7[5]) ? 5'b01011  // SRA / SRAI
                                                                       : 5'b01010; // SRL / SRLI
                        3'b110: ALUControl = 5'b00001; // OR   / ORI
                        3'b111: ALUControl = 5'b00000; // AND  / ANDI
                        default: ALUControl = 5'b00010;
                    endcase
                end
            end

            default: ALUControl = 5'b00010;

        endcase
    end

endmodule
