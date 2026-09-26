// CSR file (Phase 10): machine-mode control and status registers.
// Read is combinational (the old value for rd); writes, trap entry, MRET and
// the counters update on the rising edge. The file never decides *when* to
// write: the pipeline raises csr_we only in the cycle in which the CSR
// instruction leaves EX, so a CSR instruction held in EX by a bus freeze is
// written exactly once.
//
//   300 mstatus   MIE [3], MPIE [7], MPP [12:11] fixed at 11
//   301 misa      RV32IMC: 40001104 (read only, writes ignored)
//   304 mie       MEIE [11]
//   305 mtvec     direct mode: [1:0] read 0
//   340 mscratch
//   341 mepc      [0] reads 0 (instructions are 2-byte aligned with C)
//   342 mcause    [31] interrupt, [30:0] cause
//   343 mtval
//   344 mip       MEIP [11] = OR of the interrupt lines (read only)
//   B00/B80 mcycle, mcycleh      B02/B82 minstret, minstreth
//   C00-C02, C80-C82  cycle, time, instret and upper halves (read only shadows;
//                     time counts CPU clock cycles)
//   F11-F14 mvendorid, marchid, mimpid, mhartid: read as 0
// Anything else is not implemented and reads as illegal; so is a write attempt
// to the read-only space csr_addr[11:10] = 11.
module csr_file (
    input         clk,
    input         rst_n,

    // CSR instruction in EX
    input  [11:0] csr_addr,           // instr[31:20], carried in ID/EX
    input  [1:0]  csr_op,             // 00 WRITE, 01 SET, 10 CLEAR
    input  [31:0] csr_wdata,          // operand: forwarded rs1 or zero-extended uimm
    input         csr_write_attempt,  // the instruction wants to write (for legality)
    input         csr_we,             // commit the write on this edge
    output reg [31:0] csr_rdata,      // current (old) value of csr_addr
    output        csr_illegal,        // unimplemented address, or write attempt to read-only space

    // trap entry and return
    input         trap_take,          // take a trap on this edge
    input  [31:0] trap_cause,         // new mcause
    input  [31:0] trap_epc,           // new mepc: PC of the instruction in EX
    input  [31:0] trap_val,           // new mtval
    input         mret_take,          // MRET leaves EX on this edge

    // counters and interrupts
    input         retire,             // an instruction leaves WB on this edge
    input  [1:0]  irq_lines,          // level-sensitive external interrupt sources

    // redirect targets and interrupt request
    output [31:0] mtvec_out,
    output [31:0] mepc_out,
    output        irq_pending         // MIE AND MEIE AND MEIP
);

    localparam [11:0] CSR_MSTATUS   = 12'h300,
                      CSR_MISA      = 12'h301,
                      CSR_MIE       = 12'h304,
                      CSR_MTVEC     = 12'h305,
                      CSR_MSCRATCH  = 12'h340,
                      CSR_MEPC      = 12'h341,
                      CSR_MCAUSE    = 12'h342,
                      CSR_MTVAL     = 12'h343,
                      CSR_MIP       = 12'h344,
                      CSR_MCYCLE    = 12'hB00,
                      CSR_MINSTRET  = 12'hB02,
                      CSR_MCYCLEH   = 12'hB80,
                      CSR_MINSTRETH = 12'hB82,
                      CSR_CYCLE     = 12'hC00,
                      CSR_TIME      = 12'hC01,
                      CSR_INSTRET   = 12'hC02,
                      CSR_CYCLEH    = 12'hC80,
                      CSR_TIMEH     = 12'hC81,
                      CSR_INSTRETH  = 12'hC82,
                      CSR_MVENDORID = 12'hF11,
                      CSR_MARCHID   = 12'hF12,
                      CSR_MIMPID    = 12'hF13,
                      CSR_MHARTID   = 12'hF14;

    localparam [31:0] MISA_VALUE = 32'h40001104;     // MXL = 1 (32-bit), I, M, C

    // ---------------------------------------------------------------------
    // State: only the bits that can change
    // ---------------------------------------------------------------------
    reg        mie_bit;          // mstatus.MIE
    reg        mpie_bit;         // mstatus.MPIE
    reg        meie_bit;         // mie.MEIE
    reg [31:2] mtvec_q;
    reg [31:0] mscratch_q;
    reg [31:1] mepc_q;
    reg [31:0] mcause_q;
    reg [31:0] mtval_q;
    reg [63:0] mcycle_q;
    reg [63:0] minstret_q;

    wire meip = |irq_lines;

    wire [31:0] mstatus_value = {19'b0, 2'b11, 3'b000, mpie_bit, 3'b000, mie_bit, 3'b000};
    wire [31:0] mie_value     = {20'b0, meie_bit, 11'b0};
    wire [31:0] mip_value     = {20'b0, meip, 11'b0};

    // ---------------------------------------------------------------------
    // Read mux
    // ---------------------------------------------------------------------
    reg implemented;

    always @(*) begin
        implemented = 1'b1;
        case (csr_addr)
            CSR_MSTATUS:   csr_rdata = mstatus_value;
            CSR_MISA:      csr_rdata = MISA_VALUE;
            CSR_MIE:       csr_rdata = mie_value;
            CSR_MTVEC:     csr_rdata = {mtvec_q, 2'b00};
            CSR_MSCRATCH:  csr_rdata = mscratch_q;
            CSR_MEPC:      csr_rdata = {mepc_q, 1'b0};
            CSR_MCAUSE:    csr_rdata = mcause_q;
            CSR_MTVAL:     csr_rdata = mtval_q;
            CSR_MIP:       csr_rdata = mip_value;
            CSR_MCYCLE,
            CSR_CYCLE,
            CSR_TIME:      csr_rdata = mcycle_q[31:0];
            CSR_MCYCLEH,
            CSR_CYCLEH,
            CSR_TIMEH:     csr_rdata = mcycle_q[63:32];
            CSR_MINSTRET,
            CSR_INSTRET:   csr_rdata = minstret_q[31:0];
            CSR_MINSTRETH,
            CSR_INSTRETH:  csr_rdata = minstret_q[63:32];
            CSR_MVENDORID,
            CSR_MARCHID,
            CSR_MIMPID,
            CSR_MHARTID:   csr_rdata = 32'b0;
            default: begin
                csr_rdata   = 32'b0;
                implemented = 1'b0;
            end
        endcase
    end

    // csr_write_attempt, never csr_we: the pipeline builds csr_we from "no
    // trap in this cycle", and the trap depends on csr_illegal.
    assign csr_illegal = !implemented || (csr_write_attempt && csr_addr[11:10] == 2'b11);

    // ---------------------------------------------------------------------
    // Value written by CSRRW / CSRRS / CSRRC
    // ---------------------------------------------------------------------
    reg [31:0] new_value;

    always @(*) begin
        case (csr_op)
            2'b01:   new_value = csr_rdata | csr_wdata;     // SET
            2'b10:   new_value = csr_rdata & ~csr_wdata;    // CLEAR
            default: new_value = csr_wdata;                 // WRITE
        endcase
    end

    wire write_mcycle    = csr_we && (csr_addr == CSR_MCYCLE   || csr_addr == CSR_MCYCLEH);
    wire write_minstret  = csr_we && (csr_addr == CSR_MINSTRET || csr_addr == CSR_MINSTRETH);

    // ---------------------------------------------------------------------
    // Updates. Priority: trap entry, MRET, CSR write. The pipeline never
    // raises two of them in the same cycle, but a fixed order keeps the
    // behaviour defined if it did.
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mie_bit    <= 1'b0;
            mpie_bit   <= 1'b0;
            meie_bit   <= 1'b0;
            mtvec_q    <= 30'b0;
            mscratch_q <= 32'b0;
            mepc_q     <= 31'b0;
            mcause_q   <= 32'b0;
            mtval_q    <= 32'b0;
            mcycle_q   <= 64'b0;
            minstret_q <= 64'b0;
        end else begin
            if (trap_take) begin
                mepc_q   <= trap_epc[31:1];
                mcause_q <= trap_cause;
                mtval_q  <= trap_val;
                mpie_bit <= mie_bit;
                mie_bit  <= 1'b0;
            end else if (mret_take) begin
                mie_bit  <= mpie_bit;
                mpie_bit <= 1'b1;
            end else if (csr_we) begin
                case (csr_addr)
                    CSR_MSTATUS: begin
                        mie_bit  <= new_value[3];
                        mpie_bit <= new_value[7];
                    end
                    CSR_MIE:      meie_bit   <= new_value[11];
                    CSR_MTVEC:    mtvec_q    <= new_value[31:2];
                    CSR_MSCRATCH: mscratch_q <= new_value;
                    CSR_MEPC:     mepc_q     <= new_value[31:1];
                    CSR_MCAUSE:   mcause_q   <= new_value;
                    CSR_MTVAL:    mtval_q    <= new_value;
                    default: ;    // misa, mip, counters (below), read-only space
                endcase
            end

            // A write to a counter replaces the written half and suppresses
            // the increment in that cycle.
            if (write_mcycle) begin
                if (csr_addr == CSR_MCYCLE)
                    mcycle_q[31:0]  <= new_value;
                else
                    mcycle_q[63:32] <= new_value;
            end else
                mcycle_q <= mcycle_q + 64'd1;

            if (write_minstret) begin
                if (csr_addr == CSR_MINSTRET)
                    minstret_q[31:0]  <= new_value;
                else
                    minstret_q[63:32] <= new_value;
            end else if (retire)
                minstret_q <= minstret_q + 64'd1;
        end
    end

    assign mtvec_out   = {mtvec_q, 2'b00};
    assign mepc_out    = {mepc_q, 1'b0};
    assign irq_pending = mie_bit && meie_bit && meip;

endmodule
