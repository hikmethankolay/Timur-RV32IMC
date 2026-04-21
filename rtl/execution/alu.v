module alu (
    input         clk,
    input         rst_n,
    input  [31:0] a,
    input  [31:0] b,
    input  [4:0]  ALUControl,
    input         div_start,
    output reg [31:0] result,
    output        zero,
    output        cout,
    output        overflow,
    output        div_busy,
    output        div_done
);

	wire do_sub = (ALUControl == 5'b00110) || (ALUControl == 5'b00111);
	
	wire [31:0] adder_result;
	wire adder_cout;
	wire adder_overflow;
	
	adder_32bit adder_inst (
		.a(a),
		.b(b),
		.sub(do_sub),
		.result(adder_result),
		.cout(adder_cout),
		.overflow(adder_overflow)
	);
	
	reg [1:0] shift_type;
	
	always @(*) begin
		case (ALUControl)
        5'b01001: shift_type = 2'b00;
        5'b01010: shift_type = 2'b01;
        5'b01011: shift_type = 2'b10;
        default:  shift_type = 2'b11;
		endcase
	end

	wire [31:0] shift_result;
	
	barrel_shifter shifter_inst (
    .in         (a),
    .shamt      (b[4:0]),
    .shift_type (shift_type),
    .out        (shift_result)
	);

	wire [31:0] mul_result;

    multiplier mul_inst (
        .a      (a),
        .b      (b),
        .mul_op (ALUControl[1:0]),
        .result (mul_result)
    );

    wire [31:0] div_quotient;
    wire [31:0] div_remainder;

    wire div_start_gated = div_start & ~div_busy;

    divider div_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (div_start_gated),
        .a         (a),
        .b         (b),
        .div_op    (ALUControl[1:0]),
        .quotient  (div_quotient),
        .remainder (div_remainder),
        .busy      (div_busy),
        .done      (div_done)
    );


	
	wire [31:0] and_result = a & b;
	wire [31:0] or_result  = a | b;
	wire [31:0] xor_result = a ^ b;
	wire [31:0] slt_result = {31'b0, (adder_result[31] ^ adder_overflow)};
	
	
	always @(*) begin
        case (ALUControl)
            5'b00000: result = and_result;
            5'b00001: result = or_result;
            5'b00010: result = adder_result;
            5'b00110: result = adder_result;
            5'b00111: result = slt_result;
            5'b01000: result = xor_result;
            5'b01001: result = shift_result;
            5'b01010: result = shift_result;
            5'b01011: result = shift_result;
            5'b10000: result = mul_result;
            5'b10001: result = mul_result;
            5'b10010: result = mul_result;
            5'b10011: result = mul_result;
            5'b10100: result = div_quotient;   // DIV  (div_op=00, signed quotient)
            5'b10101: result = div_quotient;   // DIVU (div_op=01, unsigned quotient)
            5'b10110: result = div_remainder;  // REM  (div_op=10, signed remainder)
            5'b10111: result = div_remainder;  // REMU (div_op=11, unsigned remainder)
            default:  result = 32'b0;
        endcase
    end

	assign zero     = (result == 32'h00000000);
	assign cout     = adder_cout;
	assign overflow = adder_overflow;

endmodule