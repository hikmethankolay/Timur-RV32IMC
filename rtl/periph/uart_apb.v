// UART APB slave (Phase 8), 8N1.
//   0x00 UART_DATA    R/W  write: byte to send (ignored while tx_busy)
//                          read : received byte; clears rx_valid and rx_overrun
//   0x04 UART_STATUS  R    bit 0 tx_busy, bit 1 rx_valid, bit 2 rx_overrun
//   0x08 UART_CTRL    R/W  bit 0 rx_enable, bit 1 rx_irq_enable
// Every register resets to 0: the receiver starts disabled.
// One bit lasts DIVIDER + 1 clock cycles: 434 cycles = 115,207 baud at 50 MHz.
// Registers are decoded on PADDR[7:2].
module uart_apb #(
    parameter DIVIDER = 433   // f_clk / baud - 1
) (
    input             PCLK,
    input             PRESETn,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PADDR,
    input      [31:0] PWDATA,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,
    output reg        uart_tx,
    input             uart_rx,
    output            irq            // rx_valid AND rx_irq_enable (optional)
);

    // ceil(log2(DIVIDER + 1)): 9 bits for 433
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam CW   = clog2(DIVIDER + 1);
    localparam HALF = DIVIDER / 2;

    localparam [5:0] REG_DATA   = 6'h00,   // 0x00
                     REG_STATUS = 6'h01,   // 0x04
                     REG_CTRL   = 6'h02;   // 0x08

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    wire write_en = PSEL && PENABLE && PWRITE;
    wire read_en  = PSEL && PENABLE && !PWRITE;

    wire data_write = write_en && (PADDR[7:2] == REG_DATA);
    wire data_read  = read_en  && (PADDR[7:2] == REG_DATA);
    wire ctrl_write = write_en && (PADDR[7:2] == REG_CTRL);

    reg       rx_enable;
    reg       rx_irq_enable;
    reg [7:0] rx_data;
    reg       rx_valid;
    reg       rx_overrun;

    // -----------------------------------------------------------------
    // Transmitter: IDLE -> START (1 bit) -> DATA (8 bits, LSB first)
    // -> STOP (1 bit) -> IDLE. tx_busy covers the whole frame.
    // -----------------------------------------------------------------
    reg [1:0]    tx_state;
    reg [CW-1:0] tx_count;
    reg [2:0]    tx_bit;
    reg [7:0]    tx_shift;

    wire tx_busy = (tx_state != S_IDLE);
    wire tx_tick = (tx_count == DIVIDER);

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_state <= S_IDLE;
            tx_count <= {CW{1'b0}};
            tx_bit   <= 3'd0;
            tx_shift <= 8'h00;
            uart_tx  <= 1'b1;
        end else begin
            case (tx_state)
                S_IDLE: begin
                    uart_tx <= 1'b1;
                    if (data_write) begin
                        tx_shift <= PWDATA[7:0];
                        tx_count <= {CW{1'b0}};
                        uart_tx  <= 1'b0;             // start bit
                        tx_state <= S_START;
                    end
                end

                S_START: begin
                    if (tx_tick) begin
                        tx_count <= {CW{1'b0}};
                        tx_bit   <= 3'd0;
                        uart_tx  <= tx_shift[0];
                        tx_state <= S_DATA;
                    end else
                        tx_count <= tx_count + 1'b1;
                end

                S_DATA: begin
                    if (tx_tick) begin
                        tx_count <= {CW{1'b0}};
                        if (tx_bit == 3'd7) begin
                            uart_tx  <= 1'b1;         // stop bit
                            tx_state <= S_STOP;
                        end else begin
                            tx_bit   <= tx_bit + 3'd1;
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            uart_tx  <= tx_shift[1];
                        end
                    end else
                        tx_count <= tx_count + 1'b1;
                end

                default: begin   // S_STOP
                    if (tx_tick) begin
                        tx_count <= {CW{1'b0}};
                        tx_state <= S_IDLE;
                    end else
                        tx_count <= tx_count + 1'b1;
                end
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Receiver: a falling edge on the synchronised line starts a half-bit
    // count; the start bit is re-checked at its centre (glitch filter), then
    // the eight data bits and the stop bit are sampled at their centres.
    // -----------------------------------------------------------------
    reg          rx_meta, rx_sync, rx_prev;
    reg [1:0]    rx_state;
    reg [CW-1:0] rx_count;
    reg [2:0]    rx_bit;
    reg [7:0]    rx_shift;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    wire rx_fall  = rx_prev && !rx_sync;
    wire rx_store = (rx_state == S_STOP) && (rx_count == DIVIDER) && rx_sync;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_state <= S_IDLE;
            rx_count <= {CW{1'b0}};
            rx_bit   <= 3'd0;
            rx_shift <= 8'h00;
        end else begin
            case (rx_state)
                S_IDLE: begin
                    if (rx_enable && rx_fall) begin
                        rx_count <= {CW{1'b0}};
                        rx_state <= S_START;
                    end
                end

                S_START: begin
                    if (rx_count == HALF) begin
                        rx_count <= {CW{1'b0}};
                        rx_bit   <= 3'd0;
                        rx_state <= rx_sync ? S_IDLE : S_DATA;   // glitch -> IDLE
                    end else
                        rx_count <= rx_count + 1'b1;
                end

                S_DATA: begin
                    if (rx_count == DIVIDER) begin
                        rx_count <= {CW{1'b0}};
                        rx_shift <= {rx_sync, rx_shift[7:1]};    // LSB first
                        if (rx_bit == 3'd7)
                            rx_state <= S_STOP;
                        else
                            rx_bit <= rx_bit + 3'd1;
                    end else
                        rx_count <= rx_count + 1'b1;
                end

                default: begin   // S_STOP: sample the stop bit at its centre
                    if (rx_count == DIVIDER) begin
                        rx_count <= {CW{1'b0}};
                        rx_state <= S_IDLE;
                    end else
                        rx_count <= rx_count + 1'b1;
                end
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_enable     <= 1'b0;
            rx_irq_enable <= 1'b0;
            rx_data       <= 8'h00;
            rx_valid      <= 1'b0;
            rx_overrun    <= 1'b0;
        end else begin
            if (ctrl_write) begin
                rx_enable     <= PWDATA[0];
                rx_irq_enable <= PWDATA[1];
            end

            if (data_read) begin
                rx_valid   <= 1'b0;
                rx_overrun <= 1'b0;
            end

            // A byte arriving in the same cycle as a DATA read is kept.
            if (rx_store) begin
                rx_data  <= rx_shift;
                rx_valid <= 1'b1;
                if (rx_valid && !data_read)
                    rx_overrun <= 1'b1;
            end
        end
    end

    always @(*) begin
        case (PADDR[7:2])
            REG_DATA:   PRDATA = {24'b0, rx_data};
            REG_STATUS: PRDATA = {29'b0, rx_overrun, rx_valid, tx_busy};
            REG_CTRL:   PRDATA = {30'b0, rx_irq_enable, rx_enable};
            default:    PRDATA = 32'b0;
        endcase
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;
    assign irq     = rx_valid && rx_irq_enable;

endmodule
