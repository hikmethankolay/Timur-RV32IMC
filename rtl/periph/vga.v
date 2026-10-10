// VGA controller: 640x480 at 60 Hz from a 320x240, 4-bit-per-pixel framebuffer.
//
// Framebuffer (AHB-Lite slave, 0x3000_0000, 38,400 bytes):
//   row y (0..239) starts at byte 160*y; byte 160*y + b holds pixel 2b in its
//   low nibble and pixel 2b+1 in its high nibble. Four byte lanes of 9600 x 8,
//   so byte and halfword stores work as in ram_ahb. Offsets at or above 38,400
//   read 0 and ignore writes.
// Registers (APB slave, 0x4000_0300), decoded on PADDR[7:2]:
//   0x00 CTRL     R/W  bit 0 ENABLE (resets to 1): 0 = black screen
//   0x04 STATUS   R    bit 0 VBLANK: the beam is in the vertical blanking interval
//   0x08 SCROLL   R/W  framebuffer row shown at the top of the screen, 0..239;
//                      writes of 240 or more are ignored
//   0x0C FRAME    R    frames started, counted when VBLANK begins
//   0x40-0x7C PALETTE[0..15]  R/W  12-bit colour {R[3:0], G[3:0], B[3:0]};
//                      reset to the 16 standard VGA text-mode colours
//
// Video: one pixel every second clock (25 MHz at 50 MHz; 25.175 MHz nominal,
// well inside what monitors accept). 800 x 525 pixels per frame: active 640,
// front porch 16, sync 96, back porch 48; active 480, front porch 10, sync 2,
// back porch 33; both syncs active low. Each framebuffer pixel covers 2 x 2
// screen pixels.
//
// The framebuffer is a simple dual-port memory per lane: one write port (the
// AHB data phase) and one read port shared by the video fetch and AHB reads.
// The video fetch reads one 32-bit word (8 framebuffer pixels = 32 clocks of
// video) per word period, in a fixed slot one word ahead; an AHB read whose
// address phase falls on that slot is issued one cycle later, with one wait
// state (HREADYOUT = 0). Writes never wait.
module vga (
    input             HCLK,
    input             HRESETn,

    // AHB-Lite slave: framebuffer
    input             HSEL,
    input      [31:0] HADDR,
    input      [1:0]  HTRANS,
    input             HWRITE,
    input      [2:0]  HSIZE,
    input      [31:0] HWDATA,
    input             HREADY,
    output     [31:0] HRDATA,
    output            HREADYOUT,
    output            HRESP,

    // APB slave: registers
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PADDR,
    input      [31:0] PWDATA,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,

    // VGA connector (4-bit resistor DAC per colour on the DE10-Lite)
    output reg [3:0]  vga_r,
    output reg [3:0]  vga_g,
    output reg [3:0]  vga_b,
    output reg        vga_hs,
    output reg        vga_vs
);

    localparam [13:0] FB_WORDS = 14'd9600;     // 320 x 240 x 4 bit / 32 bit

    localparam [9:0] H_ACTIVE     = 10'd640,
                     H_SYNC_START = 10'd656,   // + front porch 16
                     H_SYNC_END   = 10'd752,   // + sync 96
                     H_LAST       = 10'd799;   // + back porch 48, minus 1
    localparam [9:0] V_ACTIVE     = 10'd480,
                     V_SYNC_START = 10'd490,   // + front porch 10
                     V_SYNC_END   = 10'd492,   // + sync 2
                     V_LAST       = 10'd524;   // + back porch 33, minus 1
    localparam [7:0] ROWS = 8'd240;

    localparam [5:0] REG_CTRL   = 6'h00,       // 0x00
                     REG_STATUS = 6'h01,       // 0x04
                     REG_SCROLL = 6'h02,       // 0x08
                     REG_FRAME  = 6'h03;       // 0x0C

    // =====================================================================
    // Beam position: h and v advance on every second clock (phase = 1)
    // =====================================================================
    reg       phase;
    reg [9:0] h;
    reg [9:0] v;

    wire h_wrap = (h == H_LAST);
    wire v_wrap = (v == V_LAST);
    wire vblank = (v >= V_ACTIVE);

    reg [31:0] frame_count;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            phase       <= 1'b0;
            h           <= 10'd0;
            v           <= 10'd0;
            frame_count <= 32'd0;
        end else begin
            phase <= ~phase;
            if (phase) begin
                h <= h_wrap ? 10'd0 : h + 10'd1;
                if (h_wrap) begin
                    v <= v_wrap ? 10'd0 : v + 10'd1;
                    if (v == V_ACTIVE - 10'd1)
                        frame_count <= frame_count + 32'd1;
                end
            end
        end
    end

    // =====================================================================
    // Registers
    // =====================================================================
    reg        enable;
    reg [7:0]  scroll;
    reg [11:0] palette [0:15];

    wire       apb_write = PSEL && PENABLE && PWRITE;
    wire       pal_sel   = PADDR[6];           // 0x40-0x7C
    wire [3:0] pal_index = PADDR[5:2];

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            enable      <= 1'b1;
            scroll      <= 8'd0;
            palette[0]  <= 12'h000;  palette[1]  <= 12'h00A;   // black, blue
            palette[2]  <= 12'h0A0;  palette[3]  <= 12'h0AA;   // green, cyan
            palette[4]  <= 12'hA00;  palette[5]  <= 12'hA0A;   // red, magenta
            palette[6]  <= 12'hA50;  palette[7]  <= 12'hAAA;   // brown, light grey
            palette[8]  <= 12'h555;  palette[9]  <= 12'h55F;   // dark grey, light blue
            palette[10] <= 12'h5F5;  palette[11] <= 12'h5FF;   // light green, light cyan
            palette[12] <= 12'hF55;  palette[13] <= 12'hF5F;   // light red, light magenta
            palette[14] <= 12'hFF5;  palette[15] <= 12'hFFF;   // yellow, white
        end else if (apb_write) begin
            if (pal_sel)
                palette[pal_index] <= PWDATA[11:0];
            else case (PADDR[7:2])
                REG_CTRL:   enable <= PWDATA[0];
                REG_SCROLL: if (PWDATA < {24'd0, ROWS}) scroll <= PWDATA[7:0];
                default: ;
            endcase
        end
    end

    always @(*) begin
        if (pal_sel)
            PRDATA = {20'b0, palette[pal_index]};
        else case (PADDR[7:2])
            REG_CTRL:   PRDATA = {31'b0, enable};
            REG_STATUS: PRDATA = {31'b0, vblank};
            REG_SCROLL: PRDATA = {24'b0, scroll};
            REG_FRAME:  PRDATA = frame_count;
            default:    PRDATA = 32'b0;
        endcase
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // =====================================================================
    // Framebuffer
    // =====================================================================
    // TIMUR_PORTABLE: no Intel attributes (see rom_ahb).
`ifdef TIMUR_PORTABLE
    reg [7:0] lane0 [0:9599];
    reg [7:0] lane1 [0:9599];
    reg [7:0] lane2 [0:9599];
    reg [7:0] lane3 [0:9599];
`else
    (* ramstyle = "M9K" *) reg [7:0] lane0 [0:9599];
    (* ramstyle = "M9K" *) reg [7:0] lane1 [0:9599];
    (* ramstyle = "M9K" *) reg [7:0] lane2 [0:9599];
    (* ramstyle = "M9K" *) reg [7:0] lane3 [0:9599];
`endif

    wire        accept   = HSEL & HTRANS[1] & HREADY;
    wire [13:0] index    = HADDR[15:2];
    wire        in_range = (index < FB_WORDS);

    // Byte enables from HSIZE and HADDR[1:0].
    reg [3:0] byte_en;
    always @(*) begin
        case (HSIZE)
            3'b000:  byte_en = 4'b0001 << HADDR[1:0];           // byte
            3'b001:  byte_en = HADDR[1] ? 4'b1100 : 4'b0011;    // halfword
            3'b010:  byte_en = 4'b1111;                         // word
            default: byte_en = 4'b0000;
        endcase
    end

    // ---- writes: address phase registered, data written in the data phase
    reg        wr_pending;
    reg [13:0] wr_index;
    reg [3:0]  wr_be;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            wr_pending <= 1'b0;
            wr_index   <= 14'b0;
            wr_be      <= 4'b0;
        end else if (HREADY) begin
            wr_pending <= accept & HWRITE & in_range;
            wr_index   <= index;
            wr_be      <= byte_en;
        end
    end

    always @(posedge HCLK) begin
        if (wr_pending) begin
            if (wr_be[0]) lane0[wr_index] <= HWDATA[7:0];
            if (wr_be[1]) lane1[wr_index] <= HWDATA[15:8];
            if (wr_be[2]) lane2[wr_index] <= HWDATA[23:16];
            if (wr_be[3]) lane3[wr_index] <= HWDATA[31:24];
        end
    end

    // ---- video fetch address, computed a cycle ahead of its slot
    // The slot is the first clock of h[3:0] = 1 in each 16-pixel word period;
    // it fetches the word of the next period (from the last period of a line,
    // the first word of the next line). vid_addr is registered from the
    // current period's h and v, so it is valid from the period's second clock.
    wire       vid_slot  = (h[3:0] == 4'd1) && !phase;
    wire [5:0] next_col  = h[9:4] + 6'd1;
    wire       next_line = (next_col == 6'd50);
    wire [5:0] fetch_col = next_line ? 6'd0 : next_col;
    wire [9:0] fetch_v   = !next_line ? v : (v_wrap ? 10'd0 : v + 10'd1);
    wire [8:0] row_sum   = {1'b0, fetch_v[8:1]} + {1'b0, scroll};
    wire [7:0] fetch_row = (row_sum >= {1'b0, ROWS}) ? row_sum[7:0] - ROWS : row_sum[7:0];

    reg [13:0] vid_addr;
    always @(posedge HCLK)
        vid_addr <= ({6'b0, fetch_row} << 5) + ({6'b0, fetch_row} << 3) + {8'b0, fetch_col};

    // ---- the shared read port
    wire rd_req = accept & ~HWRITE;

    reg        rd_defer;          // an AHB read lost its slot: issued now, one wait state
    reg [13:0] rd_defer_index;
    reg        rd_range;          // the read being answered is in range
    reg        vid_issued;        // the read port served the video fetch last cycle

    wire [13:0] rd_addr = vid_slot ? vid_addr :
                          rd_defer ? rd_defer_index : index;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            rd_defer   <= 1'b0;
            rd_range   <= 1'b0;
            vid_issued <= 1'b0;
        end else begin
            rd_defer   <= rd_req & vid_slot;
            vid_issued <= vid_slot;
            if (rd_req)
                rd_range <= in_range;
        end
    end

    always @(posedge HCLK)
        if (rd_req)
            rd_defer_index <= index;

    // Synchronous read every clock (M9K registers the read address).
    reg [7:0] q0, q1, q2, q3;
    always @(posedge HCLK) begin
        q0 <= lane0[rd_addr];
        q1 <= lane1[rd_addr];
        q2 <= lane2[rd_addr];
        q3 <= lane3[rd_addr];
    end

    // Read-after-write bypass, as in ram_ahb: a read whose address phase is
    // the data phase of a write to the same word gets the written lanes. A
    // deferred read is issued after that write and needs none; the bypass
    // then merges the same bytes the memory returns.
    reg        byp_hit;
    reg [3:0]  byp_be;
    reg [31:0] byp_data;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            byp_hit <= 1'b0;
        else if (rd_req)
            byp_hit <= wr_pending && (wr_index == index);
    end

    always @(posedge HCLK) begin
        if (rd_req) begin
            byp_be   <= wr_be;
            byp_data <= HWDATA;
        end
    end

    wire [31:0] rd_word = {(byp_hit && byp_be[3]) ? byp_data[31:24] : q3,
                           (byp_hit && byp_be[2]) ? byp_data[23:16] : q2,
                           (byp_hit && byp_be[1]) ? byp_data[15:8]  : q1,
                           (byp_hit && byp_be[0]) ? byp_data[7:0]   : q0};

    assign HRDATA    = rd_range ? rd_word : 32'b0;
    assign HREADYOUT = ~rd_defer;
    assign HRESP     = 1'b0;

    // =====================================================================
    // Pixel pipeline
    // =====================================================================
    reg [31:0] next_word;         // fetched word of the next period
    reg [31:0] cur_word;          // word of the current period: 8 pixels

    always @(posedge HCLK) begin
        if (vid_issued)
            next_word <= {q3, q2, q1, q0};
        if (phase && h[3:0] == 4'd15)
            cur_word <= next_word;
    end

    wire        active = (h < H_ACTIVE) && (v < V_ACTIVE);
    wire [3:0]  pixel  = cur_word[{h[3:1], 2'b00} +: 4];
    wire [11:0] colour = palette[pixel];
    wire        show   = active && enable;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            vga_r  <= 4'd0;
            vga_g  <= 4'd0;
            vga_b  <= 4'd0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            vga_r  <= show ? colour[11:8] : 4'd0;
            vga_g  <= show ? colour[7:4]  : 4'd0;
            vga_b  <= show ? colour[3:0]  : 4'd0;
            vga_hs <= !((h >= H_SYNC_START) && (h < H_SYNC_END));
            vga_vs <= !((v >= V_SYNC_START) && (v < V_SYNC_END));
        end
    end

endmodule
