// Main control unit (Phase 4).
// Decodes opcode (plus funct3, funct7 and funct12 = {funct7, rs2} for SYSTEM)
// into the datapath controls. Unrecognised encodings raise Illegal and force
// every side-effect control to 0; Phase 10 turns Illegal into a trap.
module main_control_unit (
    input      [6:0] opcode,
    input      [2:0] funct3,
    input      [6:0] funct7,
    input      [4:0] rs2_addr,
    output reg       RegWrite,
    output reg [1:0] ALUSrcA,     // 00 rs1, 01 PC, 10 zero
    output reg       ALUSrcB,     // 0 rs2, 1 immediate
    output reg [1:0] ALUOp,       // 00 ADD, 01 SUB, 10 decode funct fields
    output reg       MemRead,
    output reg       MemWrite,
    output reg       MemToReg,
    output reg       Branch,      // conditional branch
    output reg       Jump,        // JAL
    output reg       Jalr,        // JALR
    output reg       CSRAccess,
    output reg [1:0] CSROp,       // 00 WRITE, 01 SET, 10 CLEAR
    output reg       CSRImm,      // funct3[2]: operand is the rs1 field (uimm)
    output reg       IsECALL,
    output reg       IsEBREAK,
    output reg       IsMRET,
    output reg       Illegal
);

    localparam [6:0] OP_RTYPE   = 7'b0110011,
                     OP_IARITH  = 7'b0010011,
                     OP_LOAD    = 7'b0000011,
                     OP_STORE   = 7'b0100011,
                     OP_BRANCH  = 7'b1100011,
                     OP_JAL     = 7'b1101111,
                     OP_JALR    = 7'b1100111,
                     OP_LUI     = 7'b0110111,
                     OP_AUIPC   = 7'b0010111,
                     OP_MISCMEM = 7'b0001111,
                     OP_SYSTEM  = 7'b1110011;

    wire [11:0] funct12 = {funct7, rs2_addr};

    always @(*) begin
        RegWrite  = 1'b0;
        ALUSrcA   = 2'b00;
        ALUSrcB   = 1'b0;
        ALUOp     = 2'b00;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        MemToReg  = 1'b0;
        Branch    = 1'b0;
        Jump      = 1'b0;
        Jalr      = 1'b0;
        CSRAccess = 1'b0;
        CSROp     = 2'b00;
        CSRImm    = 1'b0;
        IsECALL   = 1'b0;
        IsEBREAK  = 1'b0;
        IsMRET    = 1'b0;
        Illegal   = 1'b0;

        case (opcode)
            OP_RTYPE: begin
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
                // funct7 must be 0000000, 0000001 (M) or 0100000 (SUB/SRA only)
                if (!(funct7 == 7'b0000000 || funct7 == 7'b0000001 ||
                      (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101))))
                    Illegal = 1'b1;
            end

            OP_IARITH: begin
                RegWrite = 1'b1;
                ALUSrcB  = 1'b1;
                ALUOp    = 2'b10;
                // SLLI needs funct7 = 0000000; SRLI/SRAI 0000000 or 0100000
                // (in RV32 a set shamt[5] is reserved).
                if (funct3 == 3'b001 && funct7 != 7'b0000000)
                    Illegal = 1'b1;
                if (funct3 == 3'b101 && funct7 != 7'b0000000 && funct7 != 7'b0100000)
                    Illegal = 1'b1;
            end

            OP_LOAD: begin
                RegWrite = 1'b1;
                ALUSrcB  = 1'b1;
                MemRead  = 1'b1;
                MemToReg = 1'b1;
                if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111)
                    Illegal = 1'b1;
            end

            OP_STORE: begin
                ALUSrcB  = 1'b1;
                MemWrite = 1'b1;
                if (funct3 >= 3'b011)
                    Illegal = 1'b1;
            end

            OP_BRANCH: begin
                ALUOp  = 2'b01;
                Branch = 1'b1;
                if (funct3 == 3'b010 || funct3 == 3'b011)
                    Illegal = 1'b1;
            end

            OP_JAL: begin
                // ALU computes PC + imm, the jump target
                RegWrite = 1'b1;
                ALUSrcA  = 2'b01;
                ALUSrcB  = 1'b1;
                Jump     = 1'b1;
            end

            OP_JALR: begin
                // ALU computes rs1 + imm; the target clears bit 0
                RegWrite = 1'b1;
                ALUSrcB  = 1'b1;
                Jalr     = 1'b1;
                if (funct3 != 3'b000)
                    Illegal = 1'b1;
            end

            OP_LUI: begin
                RegWrite = 1'b1;
                ALUSrcA  = 2'b10;   // zero + imm
                ALUSrcB  = 1'b1;
            end

            OP_AUIPC: begin
                RegWrite = 1'b1;
                ALUSrcA  = 2'b01;   // PC + imm
                ALUSrcB  = 1'b1;
            end

            OP_MISCMEM: begin
                // FENCE (000) and FENCE.I (001) are NOPs: single hart, no
                // caches, read-only instruction memory.
                if (funct3 != 3'b000 && funct3 != 3'b001)
                    Illegal = 1'b1;
            end

            OP_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        case (funct12)
                            12'h000: IsECALL  = 1'b1;
                            12'h001: IsEBREAK = 1'b1;
                            12'h302: IsMRET   = 1'b1;
                            12'h105: Illegal  = 1'b0;   // WFI: NOP
                            default: Illegal  = 1'b1;
                        endcase
                    end
                    3'b100: Illegal = 1'b1;
                    default: begin
                        // CSRRW/CSRRS/CSRRC (001-011), CSRRWI/CSRRSI/CSRRCI (101-111)
                        CSRAccess = 1'b1;
                        RegWrite  = 1'b1;
                        CSROp     = funct3[1:0] - 2'b01;
                        CSRImm    = funct3[2];
                    end
                endcase
            end

            default: Illegal = 1'b1;   // includes the all-zero word
        endcase

        if (Illegal) begin
            RegWrite  = 1'b0;
            ALUSrcA   = 2'b00;
            ALUSrcB   = 1'b0;
            ALUOp     = 2'b00;
            MemRead   = 1'b0;
            MemWrite  = 1'b0;
            MemToReg  = 1'b0;
            Branch    = 1'b0;
            Jump      = 1'b0;
            Jalr      = 1'b0;
            CSRAccess = 1'b0;
            CSROp     = 2'b00;
            CSRImm    = 1'b0;
            IsECALL   = 1'b0;
            IsEBREAK  = 1'b0;
            IsMRET    = 1'b0;
        end
    end

endmodule
