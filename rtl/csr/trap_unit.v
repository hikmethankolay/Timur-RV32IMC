// Trap unit (Phase 10): decides whether the instruction in EX traps.
// Every trap is taken in EX, so the instructions older than the trapping one
// complete and the trapping one never reaches MEM (a misaligned access never
// reaches the bus). Causes, highest priority first:
//   8000000B  machine external interrupt  irq_pending, EX may be interrupted  mtval 0
//   2         illegal instruction         decode Illegal or csr_illegal       mtval 0
//   3         breakpoint                  EBREAK                              mtval PC
//   11        environment call (M-mode)   ECALL                               mtval 0
//   4         load address misaligned     LW addr[1:0] != 0, LH/LHU addr[0]   mtval address
//   6         store address misaligned    SW addr[1:0] != 0, SH addr[0]       mtval address
// Apart from the interrupt the synchronous causes exclude each other: an
// illegal instruction has every other control cleared by decode. With the C
// extension every control-transfer target is 2-byte aligned (branch and jump
// offsets are even, JALR clears bit 0), so instruction-address-misaligned
// (cause 0) cannot occur.
module trap_unit (
    // instruction in EX
    input             valid,
    input      [31:0] pc,
    input             illegal,          // main_control_unit Illegal
    input             is_ecall,
    input             is_ebreak,
    input             csr_access,
    input             csr_illegal,
    input             mem_read,
    input             mem_write,
    input      [2:0]  funct3,           // access size
    input      [1:0]  mem_addr_lo,      // address bits [1:0], from a fast 2-bit adder
    input      [31:0] mem_addr,         // full load/store address (ALU result), for mtval

    // interrupts
    input             irq_pending,      // csr_file: MIE AND MEIE AND MEIP
    input             irq_allowed,      // no MUL or DIV in EX

    output            trap_req,
    output reg [31:0] trap_cause,
    output reg [31:0] trap_val
);

    wire misaligned = (funct3[1:0] == 2'b10 && mem_addr_lo != 2'b00) ||
                      (funct3[1:0] == 2'b01 && mem_addr_lo[0]);

    wire interrupt      = irq_pending && irq_allowed;
    wire bad_instr      = illegal || (csr_access && csr_illegal);
    wire load_misalign  = mem_read  && misaligned;
    wire store_misalign = mem_write && misaligned;

    assign trap_req = valid && (interrupt || bad_instr || is_ebreak || is_ecall ||
                                load_misalign || store_misalign);

    always @(*) begin
        trap_cause = 32'd0;
        trap_val   = 32'd0;
        if (interrupt)
            trap_cause = 32'h8000000B;
        else if (bad_instr)
            trap_cause = 32'd2;
        else if (is_ebreak) begin
            trap_cause = 32'd3;
            trap_val   = pc;
        end else if (is_ecall)
            trap_cause = 32'd11;
        else if (load_misalign) begin
            trap_cause = 32'd4;
            trap_val   = mem_addr;
        end else if (store_misalign) begin
            trap_cause = 32'd6;
            trap_val   = mem_addr;
        end
    end

endmodule
