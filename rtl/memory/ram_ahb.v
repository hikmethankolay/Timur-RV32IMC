module ram_ahb (
    input         HCLK,
    input         HRESETn,
    input         HSEL,
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input  [31:0] HWDATA,
    output [31:0] HRDATA,
    output        HREADY,
    output        HRESP
);

    (* ramstyle = "M10K" *) reg [7:0] mem0 [0:16383];
    (* ramstyle = "M10K" *) reg [7:0] mem1 [0:16383];
    (* ramstyle = "M10K" *) reg [7:0] mem2 [0:16383];
    (* ramstyle = "M10K" *) reg [7:0] mem3 [0:16383];

    wire active = HSEL && HTRANS[1];

    // address phase registers
    reg [31:0] addr_reg;
    reg        hwrite_reg;
    reg [2:0]  hsize_reg;
    reg        hsel_reg;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_reg   <= 32'b0;
            hwrite_reg <= 1'b0;
            hsize_reg  <= 3'b0;
            hsel_reg   <= 1'b0;
        end else begin
            addr_reg   <= HADDR;
            hwrite_reg <= HWRITE;
            hsize_reg  <= HSIZE;
            hsel_reg   <= active;
        end
    end

    // byte enables
    reg [3:0] byte_enable;
    always @(*) begin
        case (hsize_reg)
            3'b000, 3'b100: begin
                case (addr_reg[1:0])
                    2'b00: byte_enable = 4'b0001;
                    2'b01: byte_enable = 4'b0010;
                    2'b10: byte_enable = 4'b0100;
                    2'b11: byte_enable = 4'b1000;
                endcase
            end
            3'b001, 3'b101: byte_enable = addr_reg[1] ? 4'b1100 : 4'b0011;
            3'b010:         byte_enable = 4'b1111;
            default:        byte_enable = 4'b0000;
        endcase
    end

    reg [7:0] read_byte0, read_byte1, read_byte2, read_byte3;

    always @(posedge HCLK) begin
        read_byte0 <= mem0[HADDR[15:2]];
        read_byte1 <= mem1[HADDR[15:2]];
        read_byte2 <= mem2[HADDR[15:2]];
        read_byte3 <= mem3[HADDR[15:2]];

        if (active && HWRITE) begin
            if (byte_enable[0]) mem0[HADDR[15:2]] <= HWDATA[7:0];
            if (byte_enable[1]) mem1[HADDR[15:2]] <= HWDATA[15:8];
            if (byte_enable[2]) mem2[HADDR[15:2]] <= HWDATA[23:16];
            if (byte_enable[3]) mem3[HADDR[15:2]] <= HWDATA[31:24];
        end
    end

    wire [31:0] word_read = {read_byte3, read_byte2, read_byte1, read_byte0};

    wire [7:0]  byte_sel  = (addr_reg[1:0] == 2'b00) ? word_read[7:0]   :
                            (addr_reg[1:0] == 2'b01) ? word_read[15:8]  :
                            (addr_reg[1:0] == 2'b10) ? word_read[23:16] :
                                                       word_read[31:24];

    wire [15:0] half_sel  = addr_reg[1] ? word_read[31:16] : word_read[15:0];

    reg [31:0] formatted;
    always @(*) begin
        case (hsize_reg)
            3'b000:  formatted = {{24{byte_sel[7]}}, byte_sel};
            3'b001:  formatted = {{16{half_sel[15]}}, half_sel};
            3'b010:  formatted = word_read;
            3'b100:  formatted = {24'b0, byte_sel};
            3'b101:  formatted = {16'b0, half_sel};
            default: formatted = 32'b0;
        endcase
    end

    assign HRDATA = formatted;
    assign HREADY = 1'b1;
    assign HRESP  = 1'b0;

endmodule