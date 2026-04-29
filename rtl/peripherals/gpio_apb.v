module gpio_apb (
    input             PCLK,    // Clock
    input             PRESETn, // Active-low reset
    input             PSEL,    // Peripheral select
    input             PENABLE, // Enable (Access phase)
    input             PWRITE,  // Write = 1, Read = 0
    input      [7:0]  PADDR,   // Address bus
    input      [31:0] PWDATA,  // Write data bus
    output reg [31:0] PRDATA,  // Read data bus
    output            PREADY,  // Ready signal
    output            PSLVERR, // Slave error
    output     [31:0] gpio_out, // Data to pins
    output     [31:0] gpio_dir, // Direction (1=Output, 0=Input)
    input      [31:0] gpio_in   // Data from pins
);

    localparam ADDR_GPIO_OUT = 8'h00;
    localparam ADDR_GPIO_IN  = 8'h04;
    localparam ADDR_GPIO_DIR = 8'h08;

    reg [31:0] gpio_out_reg;
    reg [31:0] gpio_dir_reg;

    reg [31:0] sync_ff1;
    reg [31:0] sync_ff2;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            sync_ff1 <= 32'h0;
            sync_ff2 <= 32'h0;
        end else begin
            sync_ff1 <= gpio_in;
            sync_ff2 <= sync_ff1;
        end
    end

    wire write_en = PSEL && PENABLE && PWRITE;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_out_reg <= 32'h0;
            gpio_dir_reg <= 32'h0;
        end else if (write_en) begin
            case (PADDR)
                ADDR_GPIO_OUT: gpio_out_reg <= PWDATA;
                ADDR_GPIO_DIR: gpio_dir_reg <= PWDATA;
                default: ;
            endcase
        end
    end

    wire read_en = PSEL && PENABLE && !PWRITE;

    always @(*) begin
        if (read_en) begin
            case (PADDR)
                ADDR_GPIO_OUT: PRDATA = gpio_out_reg;
                ADDR_GPIO_IN: PRDATA = sync_ff2;
                ADDR_GPIO_DIR: PRDATA = gpio_dir_reg;
                default: PRDATA = 32'h0;
            endcase
        end else begin
            PRDATA = 32'h0;
        end
    end

    assign PREADY   = 1'b1;
    assign PSLVERR  = 1'b0;
    assign gpio_out = gpio_out_reg;
    assign gpio_dir = gpio_dir_reg;

endmodule