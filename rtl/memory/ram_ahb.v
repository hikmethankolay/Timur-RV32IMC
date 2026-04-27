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

    (* ramstyle = "M9K" *) reg [7:0] mem0 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] mem1 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] mem2 [0:16383];
    (* ramstyle = "M9K" *) reg [7:0] mem3 [0:16383];

    // AHB active transfer condition (NONSEQ or SEQ)
    wire active = HSEL & HTRANS[1];

    // Address phase registers for write operations
    reg [13:0] write_addr;
    reg [3:0]  write_be;
    reg        write_en;

    // Byte enable generation logic
    function [3:0] get_byte_enable;
        input [1:0] addr;
        input [2:0] size;
        begin
            case (size)
                3'b000:  get_byte_enable = 4'b0001 << addr;               // Byte
                3'b001:  get_byte_enable = 4'b0011 << {addr[1], 1'b0};    // Halfword
                3'b010:  get_byte_enable = 4'b1111;                       // Word
                default: get_byte_enable = 4'b0000;
            endcase
        end
    endfunction

    // --------------------------------------------------------
    // Address Phase (Cycle 1): Latch Write Control Signals
    // --------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            write_addr <= 14'b0;
            write_be   <= 4'b0;
            write_en   <= 1'b0;
        end else begin
            if (active && HWRITE) begin
                write_addr <= HADDR[15:2];
                write_be   <= get_byte_enable(HADDR[1:0], HSIZE);
                write_en   <= 1'b1;
            end else begin
                write_en   <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------
    // Data Phase (Cycle 2): Synchronous RAM Write & Read
    // --------------------------------------------------------

    // Write port: per-byte synchronous write. Kept on its own always block
    // (no async reset, no extra logic) so each bank infers as a single M9K.
    always @(posedge HCLK) begin
        if (write_en) begin
            if (write_be[0]) mem0[write_addr] <= HWDATA[7:0];
            if (write_be[1]) mem1[write_addr] <= HWDATA[15:8];
            if (write_be[2]) mem2[write_addr] <= HWDATA[23:16];
            if (write_be[3]) mem3[write_addr] <= HWDATA[31:24];
        end
    end

    reg [31:0] ram_read_data;
    always @(posedge HCLK) begin
        if (active && !HWRITE) begin
            ram_read_data[7:0]   <= mem0[HADDR[15:2]];
            ram_read_data[15:8]  <= mem1[HADDR[15:2]];
            ram_read_data[23:16] <= mem2[HADDR[15:2]];
            ram_read_data[31:24] <= mem3[HADDR[15:2]];
        end
    end

    // --------------------------------------------------------
    // Read-After-Write Bypass (parallel to RAM, no inference impact)
    // --------------------------------------------------------
    reg        bypass_en_d;
    reg [3:0]  bypass_be_d;
    reg [31:0] bypass_data_d;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            bypass_en_d   <= 1'b0;
            bypass_be_d   <= 4'b0;
            bypass_data_d <= 32'b0;
        end else begin
            bypass_en_d   <= write_en && active && !HWRITE && (write_addr == HADDR[15:2]);
            bypass_be_d   <= write_be;
            bypass_data_d <= HWDATA;
        end
    end

    assign HRDATA[7:0]   = (bypass_en_d && bypass_be_d[0]) ? bypass_data_d[7:0]   : ram_read_data[7:0];
    assign HRDATA[15:8]  = (bypass_en_d && bypass_be_d[1]) ? bypass_data_d[15:8]  : ram_read_data[15:8];
    assign HRDATA[23:16] = (bypass_en_d && bypass_be_d[2]) ? bypass_data_d[23:16] : ram_read_data[23:16];
    assign HRDATA[31:24] = (bypass_en_d && bypass_be_d[3]) ? bypass_data_d[31:24] : ram_read_data[31:24];

    // Output assignments (Zero-wait-state response)
    assign HREADY = 1'b1;
    assign HRESP  = 1'b0;

endmodule
