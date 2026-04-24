module imm_gen (
    input  [31:0] instruction,
    input  [6:0]  opcode,
    output reg [31:0] imm
);

    always @(*) begin
        case (opcode)

            // ── I-type ──
            // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
            // LW, LH, LB, LHU, LBU
            // JALR
            7'b0010011,
            7'b0000011,
            7'b1100111: begin
                imm = {{20{instruction[31]}}, instruction[31:20]};
            end

            // ── S-type ──
            // SW, SH, SB
            7'b0100011: begin
                imm = {{20{instruction[31]}},
                        instruction[31:25],
                        instruction[11:7]};
            end

            // ── B-type ──
            // BEQ, BNE, BLT, BGE, BLTU, BGEU
            7'b1100011: begin
                imm = {{19{instruction[31]}},
                        instruction[31],
                        instruction[7],
                        instruction[30:25],
                        instruction[11:8],
                        1'b0};
            end

            // ── U-type ──
            // LUI, AUIPC
            7'b0110111,
            7'b0010111: begin
                imm = {instruction[31:12], 12'b0};
            end

            // ── J-type ──
            // JAL
            7'b1101111: begin
                imm = {{11{instruction[31]}},
                        instruction[31],
                        instruction[19:12],
                        instruction[20],
                        instruction[30:21],
                        1'b0};
            end

            // ── SYSTEM / CSR ──
            // ECALL, EBREAK, CSRRW, CSRRS etc
            // immediate is zero-extended uimm[4:0] from rs1 field
            7'b1110011: begin
                imm = {27'b0, instruction[19:15]};
            end

            // ── default ──
            default: begin
                imm = 32'b0;
            end

        endcase
    end

endmodule