module d_ff #(parameter WIDTH = 1) (
	input	[WIDTH-1:0] d,
	input clk,en,rst_n,
	output reg [WIDTH-1:0] q
);

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			q <= {WIDTH{1'b0}};
		else if (en)
			q <= d;
		else
			q <= q;
	end

endmodule