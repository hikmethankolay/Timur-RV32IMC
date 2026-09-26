// Arithmetic Logic Unit (Phase 2).
// Combinational except for the divider, which is started and acknowledged by
// the hazard logic (div_start / div_ack, Phase 7).
module alu (
    input             clk,
    input             rst_n,
    input      [31:0] a,
    input      [31:0] b,
    input      [4:0]  ALUControl,
    input             div_start,   // one-cycle start pulse for the divider
    input             div_ack,     // the DIV leaves EX; passed to the divider's ack
    output reg [31:0] result,
    output            zero,        // result == 0, after the final result mux
    output            cout,
    output            overflow,
    output            div_busy,
    output            div_done
);

    // The adder subtracts for SUB, SLT and SLTU (branches reach the ALU as SUB).
    wire do_sub = (ALUControl == 5'b00110) ||   // SUB
                  (ALUControl == 5'b00111) ||   // SLT
                  (ALUControl == 5'b01100);     // SLTU

    wire [31:0] adder_result;
    wire        adder_cout;
    wire        adder_overflow;

    adder_32bit u_adder (
        .a        (a),
        .b        (b),
        .sub      (do_sub),
        .result   (adder_result),
        .cout     (adder_cout),
        .overflow (adder_overflow)
    );

    // Shift type decoded explicitly: 01011 has bits [2:1] = 01, so slicing
    // ALUControl would not work.
    reg [1:0] shift_type;
    always @(*) begin
        case (ALUControl)
            5'b01001: shift_type = 2'b00;   // SLL
            5'b01010: shift_type = 2'b01;   // SRL
            5'b01011: shift_type = 2'b10;   // SRA
            default:  shift_type = 2'b00;
        endcase
    end

    wire [31:0] shift_result;

    barrel_shifter u_shifter (
        .in         (a),
        .shamt      (b[4:0]),
        .shift_type (shift_type),
        .out        (shift_result)
    );

    wire [31:0] mul_result;

    multiplier u_mul (
        .a      (a),
        .b      (b),
        .mul_op (ALUControl[1:0]),
        .result (mul_result)
    );

    wire [31:0] div_quotient;
    wire [31:0] div_remainder;

    divider u_div (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (div_start),
        .ack       (div_ack),
        .a         (a),
        .b         (b),
        .div_op    (ALUControl[1:0]),
        .quotient  (div_quotient),
        .remainder (div_remainder),
        .busy      (div_busy),
        .done      (div_done)
    );

    wire [31:0] slt_result  = {31'b0, adder_result[31] ^ adder_overflow};
    wire [31:0] sltu_result = {31'b0, ~adder_cout};

    always @(*) begin
        case (ALUControl)
            5'b00000: result = a & b;           // AND
            5'b00001: result = a | b;           // OR
            5'b00010: result = adder_result;    // ADD
            5'b00110: result = adder_result;    // SUB
            5'b00111: result = slt_result;      // SLT
            5'b01000: result = a ^ b;           // XOR
            5'b01001: result = shift_result;    // SLL
            5'b01010: result = shift_result;    // SRL
            5'b01011: result = shift_result;    // SRA
            5'b01100: result = sltu_result;     // SLTU
            5'b10000: result = mul_result;      // MUL
            5'b10001: result = mul_result;      // MULH
            5'b10010: result = mul_result;      // MULHSU
            5'b10011: result = mul_result;      // MULHU
            5'b10100: result = div_quotient;    // DIV
            5'b10101: result = div_quotient;    // DIVU
            5'b10110: result = div_remainder;   // REM
            5'b10111: result = div_remainder;   // REMU
            default:  result = 32'b0;
        endcase
    end

    assign zero     = (result == 32'b0);
    assign cout     = adder_cout;
    assign overflow = adder_overflow;

endmodule
