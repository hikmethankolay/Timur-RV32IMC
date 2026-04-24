module ram_ahb (
    input         HCLK,      // AHB clock — used: clocks address register and write logic
    input         HRESETn,   // Active-low async reset — used: resets address register
    input         HSEL,      // Slave select — used: gates address registration
    input  [31:0] HADDR,     // AHB address — used: registered for data phase
    input  [1:0]  HTRANS,    // Transfer type — used: HTRANS[1] detects active transfer
    input         HWRITE,    // Write/read — used: registered, controls read or write
    input  [2:0]  HSIZE,     // Transfer size — used: registered, determines byte enables
    input  [31:0] HWDATA,    // Write data — used: written to RAM on write transactions
    output [31:0] HRDATA,    // Read data — used: word from RAM, sign/zero extended
    output        HREADY,    // Transfer complete — used: hardwired 1, single cycle RAM
    output        HRESP      // Response status — used: hardwired 0 (OKAY)
);

    (* ram_init_file = "ram.mif" *) reg [31:0] mem [0:16383];

    wire active = HSEL && HTRANS[1];

    reg [31:0] addr_reg;
    reg hwrite_reg;
    reg [2:0] hsize_reg;
    reg hsel_reg;

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

    reg [3:0] byte_enable;


    always @(*) begin
        case (hsize_reg)
            3'b000: begin
                case (addr_reg[1:0])
                    2'b00: byte_enable = 4'b0001;
                    2'b01: byte_enable = 4'b0010;
                    2'b10: byte_enable = 4'b0100;
                    2'b11: byte_enable = 4'b1000;
                    default: byte_enable = 4'b0000;
                endcase
            end

            3'b001: begin
                case (addr_reg[1])
                    1'b0: byte_enable = 4'b0011;
                    1'b1: byte_enable = 4'b1100;
                    default: byte_enable = 4'b0000;
                endcase
            end

            3'b010: byte_enable = 4'b1111; 
            default: byte_enable = 4'b1111;
        endcase
    end

    always @(posedge HCLK) begin
        if (hsel_reg && hwrite_reg) begin
            if (byte_enable[0]) mem[addr_reg[15:2]][7:0]   <= HWDATA[7:0];
            if (byte_enable[1]) mem[addr_reg[15:2]][15:8]  <= HWDATA[15:8];
            if (byte_enable[2]) mem[addr_reg[15:2]][23:16] <= HWDATA[23:16];
            if (byte_enable[3]) mem[addr_reg[15:2]][31:24] <= HWDATA[31:24];
        end
    end

    wire [31:0] word     = mem[addr_reg[15:2]];

    wire [7:0]  byte_sel = (addr_reg[1:0] == 2'b00) ? word[7:0]   :
                           (addr_reg[1:0] == 2'b01) ? word[15:8]  :
                           (addr_reg[1:0] == 2'b10) ? word[23:16] :
                                                      word[31:24];

    wire [15:0] half_sel = addr_reg[1] ? word[31:16] : word[15:0];

    reg [31:0] hrdata_reg;

    always @(*) begin
        case (hsize_reg)
            3'b000: hrdata_reg = {{24{byte_sel[7]}}, byte_sel};        // LB  sign extend
            3'b001: hrdata_reg = {{16{half_sel[15]}}, half_sel};       // LH  sign extend
            3'b010: hrdata_reg = word;                                  // LW  full word
            3'b100: hrdata_reg = {24'b0, byte_sel};                    // LBU zero extend
            3'b101: hrdata_reg = {16'b0, half_sel};                    // LHU zero extend
            default: hrdata_reg = word;
        endcase
    end

    assign HRDATA = hrdata_reg;

    assign HREADY = 1'b1;
    assign HRESP  = 1'b0;
endmodule