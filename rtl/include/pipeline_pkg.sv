// ─────────────────────────────────────────────────────────────────────────────
// pipeline_pkg
// ─────────────────────────────────────────────────────────────────────────────
// Shared SystemVerilog types for stage-to-stage bundles.
//
// id_decoded_t collects everything the ID stage produces in one packed
// struct: parsed fields, the immediate, register-file read data, and all
// control signals from main_control_unit + alu_decoder. Datapath unpacks
// the relevant fields at the ID/EX register's per-signal port list, so the
// pipeline-register modules themselves are unchanged.
// ─────────────────────────────────────────────────────────────────────────────
package pipeline_pkg;

    typedef struct packed {
        // Parsed fields
        logic [6:0]  opcode;
        logic [4:0]  rd;
        logic [2:0]  funct3;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [6:0]  funct7;

        // Immediate + register-file read data
        logic [31:0] imm;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;

        // ALU control
        logic [4:0]  ALUControl;
        logic        ALUSrc;

        // Main control
        logic        Branch;
        logic        MemRead;
        logic        MemWrite;
        logic        MemToReg;
        logic        RegWrite;

        // CSR / privileged
        logic [11:0] csr_addr;
        logic        CSRWrite;
        logic [1:0]  CSROp;
        logic        IsECALL;
        logic        IsEBREAK;
        logic        IsMRET;
    } id_decoded_t;

endpackage
