// Decompressor (Phase 11): RV32C instruction -> equivalent RV32I encoding.
// Sits in IF between the ROM's fetch window and IF/ID, so decode and
// everything after it only ever see 32-bit instructions.
//
// Illegal and reserved encodings expand to 32'h00000000, which the main
// control unit decodes as an illegal instruction (trap cause 2), so an
// illegal compressed instruction needs no extra pipeline field. Illegal:
//   0x0000 and C.ADDI4SPN with nzuimm = 0, C.LWSP with rd = 0, C.JR with
//   rs1 = 0, C.ADDI16SP and C.LUI with a zero immediate, the F/D loads and
//   stores, quadrant 00 funct3 100, the RV64 C.SUBW/C.ADDW slots, and the
//   RV32 shifts with shamt[5] = 1 (custom-extension code points).
// HINT encodings (for example C.ADDI rd, 0 or C.LI x0, imm) are legal and
// expand like their base instruction; their writes to x0 are ignored.
// instr16[1:0] must not be 11; for 11 the output is the illegal pattern.
module decompressor (
    input      [15:0] instr16,
    output reg [31:0] instr32,
    output reg        illegal
);

    wire [1:0] quad   = instr16[1:0];
    wire [2:0] funct3 = instr16[15:13];
    wire [4:0] rd     = instr16[11:7];             // also rs1 in quadrants 1 and 2
    wire [4:0] rs2    = instr16[6:2];
    wire [4:0] rdp    = {2'b01, instr16[4:2]};     // rd', rs2' : x8-x15
    wire [4:0] rs1p   = {2'b01, instr16[9:7]};     // rs1', rd' in C.SRLI ... C.AND

    // immediates, named after the instructions that use them
    wire [9:0]  addi4spn_imm = {instr16[10:7], instr16[12:11], instr16[5], instr16[6], 2'b00};
    wire [6:0]  lw_imm       = {instr16[5], instr16[12:10], instr16[6], 2'b00};
    wire [11:0] imm6         = {{7{instr16[12]}}, instr16[6:2]};          // C.ADDI, C.LI, C.ANDI
    wire [11:0] j_imm        = {instr16[12], instr16[8], instr16[10:9], instr16[6], instr16[7],
                                instr16[2], instr16[11], instr16[5:3], 1'b0};
    wire [20:0] j_off        = {{9{j_imm[11]}}, j_imm};
    wire [11:0] addi16sp_imm = {{3{instr16[12]}}, instr16[4:3], instr16[5], instr16[2], instr16[6], 4'b0000};
    wire [19:0] lui_imm      = {{15{instr16[12]}}, instr16[6:2]};
    wire [5:0]  shamt        = {instr16[12], instr16[6:2]};
    wire [8:0]  b_imm        = {instr16[12], instr16[6:5], instr16[2], instr16[11:10], instr16[4:3], 1'b0};
    wire [12:0] b_off        = {{4{b_imm[8]}}, b_imm};
    wire [7:0]  lwsp_imm     = {instr16[3:2], instr16[12], instr16[6:4], 2'b00};
    wire [7:0]  swsp_imm     = {instr16[8:7], instr16[12:9], 2'b00};

    localparam [6:0] OP_IMM = 7'b0010011, OP = 7'b0110011, LOAD = 7'b0000011, STORE = 7'b0100011,
                     BRANCH = 7'b1100011, JAL = 7'b1101111, JALR = 7'b1100111, LUI = 7'b0110111;

    always @(*) begin
        instr32 = 32'b0;
        illegal = 1'b0;
        case (quad)
            // ---------------- quadrant 0 ----------------
            2'b00: case (funct3)
                3'b000: begin                                     // C.ADDI4SPN
                    instr32 = {2'b00, addi4spn_imm, 5'd2, 3'b000, rdp, OP_IMM};
                    illegal = (addi4spn_imm == 10'b0);
                end
                3'b010:                                           // C.LW
                    instr32 = {5'b0, lw_imm, rs1p, 3'b010, rdp, LOAD};
                3'b110:                                           // C.SW
                    instr32 = {5'b0, lw_imm[6:5], rdp, rs1p, 3'b010, lw_imm[4:0], STORE};
                default:                                          // F/D, reserved
                    illegal = 1'b1;
            endcase

            // ---------------- quadrant 1 ----------------
            2'b01: case (funct3)
                3'b000:                                           // C.ADDI, C.NOP
                    instr32 = {imm6, rd, 3'b000, rd, OP_IMM};
                3'b001:                                           // C.JAL (RV32)
                    instr32 = {j_off[20], j_off[10:1], j_off[11], j_off[19:12], 5'd1, JAL};
                3'b010:                                           // C.LI
                    instr32 = {imm6, 5'd0, 3'b000, rd, OP_IMM};
                3'b011:
                    if (rd == 5'd2) begin                         // C.ADDI16SP
                        instr32 = {addi16sp_imm, 5'd2, 3'b000, 5'd2, OP_IMM};
                        illegal = (addi16sp_imm == 12'b0);
                    end else begin                                // C.LUI
                        instr32 = {lui_imm, rd, LUI};
                        illegal = (shamt == 6'b0);                // nzimm[17:12] = 0
                    end
                3'b100: case (instr16[11:10])
                    2'b00: begin                                  // C.SRLI
                        instr32 = {7'b0000000, shamt[4:0], rs1p, 3'b101, rs1p, OP_IMM};
                        illegal = shamt[5];
                    end
                    2'b01: begin                                  // C.SRAI
                        instr32 = {7'b0100000, shamt[4:0], rs1p, 3'b101, rs1p, OP_IMM};
                        illegal = shamt[5];
                    end
                    2'b10:                                        // C.ANDI
                        instr32 = {imm6, rs1p, 3'b111, rs1p, OP_IMM};
                    default:
                        if (instr16[12])                          // C.SUBW, C.ADDW (RV64), reserved
                            illegal = 1'b1;
                        else case (instr16[6:5])
                            2'b00: instr32 = {7'b0100000, rdp, rs1p, 3'b000, rs1p, OP};   // C.SUB
                            2'b01: instr32 = {7'b0000000, rdp, rs1p, 3'b100, rs1p, OP};   // C.XOR
                            2'b10: instr32 = {7'b0000000, rdp, rs1p, 3'b110, rs1p, OP};   // C.OR
                            2'b11: instr32 = {7'b0000000, rdp, rs1p, 3'b111, rs1p, OP};   // C.AND
                        endcase
                endcase
                3'b101:                                           // C.J
                    instr32 = {j_off[20], j_off[10:1], j_off[11], j_off[19:12], 5'd0, JAL};
                3'b110:                                           // C.BEQZ
                    instr32 = {b_off[12], b_off[10:5], 5'd0, rs1p, 3'b000, b_off[4:1], b_off[11], BRANCH};
                default:                                          // C.BNEZ
                    instr32 = {b_off[12], b_off[10:5], 5'd0, rs1p, 3'b001, b_off[4:1], b_off[11], BRANCH};
            endcase

            // ---------------- quadrant 2 ----------------
            2'b10: case (funct3)
                3'b000: begin                                     // C.SLLI
                    instr32 = {7'b0000000, shamt[4:0], rd, 3'b001, rd, OP_IMM};
                    illegal = shamt[5];
                end
                3'b010: begin                                     // C.LWSP
                    instr32 = {4'b0, lwsp_imm, 5'd2, 3'b010, rd, LOAD};
                    illegal = (rd == 5'd0);
                end
                3'b100:
                    if (!instr16[12]) begin
                        if (rs2 == 5'd0) begin                    // C.JR
                            instr32 = {12'b0, rd, 3'b000, 5'd0, JALR};
                            illegal = (rd == 5'd0);
                        end else                                  // C.MV
                            instr32 = {7'b0, rs2, 5'd0, 3'b000, rd, OP};
                    end else begin
                        if (rs2 == 5'd0) begin
                            if (rd == 5'd0)                       // C.EBREAK
                                instr32 = 32'h00100073;
                            else                                  // C.JALR
                                instr32 = {12'b0, rd, 3'b000, 5'd1, JALR};
                        end else                                  // C.ADD
                            instr32 = {7'b0, rs2, rd, 3'b000, rd, OP};
                    end
                3'b110:                                           // C.SWSP
                    instr32 = {4'b0, swsp_imm[7:5], rs2, 5'd2, 3'b010, swsp_imm[4:0], STORE};
                default:                                          // F/D
                    illegal = 1'b1;
            endcase

            default:                                              // not a compressed instruction
                illegal = 1'b1;
        endcase

        if (illegal)
            instr32 = 32'b0;
    end

endmodule
