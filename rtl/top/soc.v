module soc (
    input         HCLK,
    input         HRESETn,
    output [31:0] pc_dbg_o,

    input         uart_rx_i,
    output        uart_tx_o,

    input  [31:0] gpio_in_i,
    output [31:0] gpio_out_o,
    output [31:0] gpio_oe_o
);

    // ── I-fetch bus signals (CPU → ROM Port A) ────────────────────────────────
    wire [31:0] if_HADDR;
    wire [1:0]  if_HTRANS;
    wire        if_HSEL   = (if_HADDR[31:16] == 16'h0000) & if_HTRANS[1];
    wire [31:0] if_HRDATA;   // ROM Port A read data → back to CPU I-fetch

    // ── Shared data-bus signals ───────────────────────────────────────────────
    // Master 0: CPU D-access
    wire [31:0] cpu_HADDR;
    wire [1:0]  cpu_HTRANS;
    wire        cpu_HWRITE;
    wire [2:0]  cpu_HSIZE;
    wire [31:0] cpu_HWDATA;
    wire        cpu_HBUSREQ;

    // Master 1: DMAC
    wire [31:0] dmac_HADDR;
    wire [1:0]  dmac_HTRANS;
    wire        dmac_HWRITE;
    wire [2:0]  dmac_HSIZE;
    wire [31:0] dmac_HWDATA;
    wire        dmac_HBUSREQ;

    // Arbiter grants
    wire [1:0]  HGRANT;
    wire        HMASTER;    // 0 = CPU, 1 = DMAC
    wire        HMASTLOCK;

    // Shared bus mux outputs — declared here so they are in scope
    // for both the arbiter (HREADY feedback) and the decoder below.
    wire [31:0] HRDATA_s;
    wire        HREADY_s;

    ahb_arbiter u_arb (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HBUSREQ   ({dmac_HBUSREQ, cpu_HBUSREQ}),
        .HLOCK     (2'b00),
        .HREADY    (HREADY_s),
        .HGRANT    (HGRANT),
        .HMASTER   (HMASTER),
        .HMASTLOCK (HMASTLOCK)
    );

    // Shared bus mux: winning master drives
    wire [31:0] HADDR_s  = HMASTER ? dmac_HADDR  : cpu_HADDR;
    wire [1:0]  HTRANS_s = HMASTER ? dmac_HTRANS : cpu_HTRANS;
    wire        HWRITE_s = HMASTER ? dmac_HWRITE : cpu_HWRITE;
    wire [2:0]  HSIZE_s  = HMASTER ? dmac_HSIZE  : cpu_HSIZE;
    wire [31:0] HWDATA_s = HMASTER ? dmac_HWDATA : cpu_HWDATA;

    // ── Address decoder ───────────────────────────────────────────────────────
    wire        HSEL_rom, HSEL_ram, HSEL_apb;
    wire [31:0] HRDATA_rom_b, HRDATA_ram, HRDATA_apb;
    wire        HREADY_ram, HREADY_apb;

    ahb_decoder u_dec (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR_s),
        .HRDATA_rom (HRDATA_rom_b),
        .HREADY_rom (1'b1),          // ROM Port B is zero-wait-state
        .HRDATA_ram (HRDATA_ram),
        .HREADY_ram (HREADY_ram),
        .HRDATA_apb (HRDATA_apb),
        .HREADY_apb (HREADY_apb),
        .HSEL_rom   (HSEL_rom),
        .HSEL_ram   (HSEL_ram),
        .HSEL_apb   (HSEL_apb),
        .HRDATA     (HRDATA_s),
        .HREADY     (HREADY_s)
    );

    // ── ROM (dual-port M9K) ───────────────────────────────────────────────────
    // Port A: dedicated I-fetch bus (CPU always has access, no arbitration)
    // Port B: shared D-bus (CPU D-reads from ROM + DMAC reads for .data init)
    wire [31:0] HRDATA_rom_a;

    rom_ahb u_rom (
        .HCLK     (HCLK),
        .HRESETn  (HRESETn),
        // Port A — I-fetch (dedicated, simultaneous with Port B)
        .HSEL_a   (if_HSEL),
        .HADDR_a  (if_HADDR),
        .HTRANS_a (if_HTRANS),
        .HWRITE_a (1'b0),
        .HSIZE_a  (3'b010),
        .HWDATA_a (32'b0),
        .HRDATA_a (HRDATA_rom_a),
        .HREADY_a (),
        .HRESP_a  (),
        // Port B — shared D-bus (CPU .rodata reads + DMAC .data copy)
        .HSEL_b   (HSEL_rom),
        .HADDR_b  (HADDR_s),
        .HTRANS_b (HTRANS_s),
        .HWRITE_b (HWRITE_s),
        .HSIZE_b  (HSIZE_s),
        .HWDATA_b (HWDATA_s),
        .HRDATA_b (HRDATA_rom_b),
        .HREADY_b (),
        .HRESP_b  ()
    );

    // ── RAM ───────────────────────────────────────────────────────────────────
    ram_ahb u_ram (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),
        .HSEL    (HSEL_ram),
        .HADDR   (HADDR_s),
        .HTRANS  (HTRANS_s),
        .HWRITE  (HWRITE_s),
        .HSIZE   (HSIZE_s),
        .HWDATA  (HWDATA_s),
        .HRDATA  (HRDATA_ram),
        .HREADY  (HREADY_ram),
        .HRESP   ()
    );

    // ── AHB→APB bridge ────────────────────────────────────────────────────────
    wire        PSEL_uart, PSEL_gpio, PSEL_dmac;
    wire        PENABLE_apb, PWRITE_apb;
    wire [7:0]  PADDR_apb;
    wire [31:0] PWDATA_apb;
    wire [31:0] PRDATA_uart, PRDATA_gpio, PRDATA_dmac;
    wire        PREADY_uart, PREADY_gpio, PREADY_dmac;

    ahb2apb_bridge u_bridge (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .HSEL        (HSEL_apb),
        .HADDR       (HADDR_s),
        .HTRANS      (HTRANS_s),
        .HWRITE      (HWRITE_s),
        .HSIZE       (HSIZE_s),
        .HWDATA      (HWDATA_s),
        .HRDATA      (HRDATA_apb),
        .HREADY      (HREADY_apb),
        .HRESP       (),
        .PSEL_uart   (PSEL_uart),
        .PSEL_gpio   (PSEL_gpio),
        .PSEL_dmac   (PSEL_dmac),
        .PENABLE     (PENABLE_apb),
        .PWRITE      (PWRITE_apb),
        .PADDR       (PADDR_apb),
        .PWDATA      (PWDATA_apb),
        .PRDATA_uart (PRDATA_uart),
        .PREADY_uart (PREADY_uart),
        .PRDATA_gpio (PRDATA_gpio),
        .PREADY_gpio (PREADY_gpio),
        .PRDATA_dmac (PRDATA_dmac),
        .PREADY_dmac (PREADY_dmac)
    );

    // ── UART ──────────────────────────────────────────────────────────────────
    uart_apb u_uart (
        .PCLK    (HCLK),
        .PRESETn (HRESETn),
        .PSEL    (PSEL_uart),
        .PENABLE (PENABLE_apb),
        .PWRITE  (PWRITE_apb),
        .PADDR   (PADDR_apb),
        .PWDATA  (PWDATA_apb),
        .PRDATA  (PRDATA_uart),
        .PREADY  (PREADY_uart),
        .PSLVERR (),
        .uart_tx (uart_tx_o),
        .uart_rx (uart_rx_i)
    );

    // ── GPIO ──────────────────────────────────────────────────────────────────
    gpio_apb u_gpio (
        .PCLK    (HCLK),
        .PRESETn (HRESETn),
        .PSEL    (PSEL_gpio),
        .PENABLE (PENABLE_apb),
        .PWRITE  (PWRITE_apb),
        .PADDR   (PADDR_apb),
        .PWDATA  (PWDATA_apb),
        .PRDATA  (PRDATA_gpio),
        .PREADY  (PREADY_gpio),
        .PSLVERR (),
        .gpio_out (gpio_out_o),
        .gpio_dir (gpio_oe_o),
        .gpio_in  (gpio_in_i)
    );

    // ── DMAC APB control registers ────────────────────────────────────────────
    wire [31:0] dma_src, dma_dst, dma_len;
    wire        dma_start, dmac_busy, dmac_done;

    dmac_apb u_dmac_apb (
        .PCLK    (HCLK),
        .PRESETn (HRESETn),
        .PSEL    (PSEL_dmac),
        .PENABLE (PENABLE_apb),
        .PWRITE  (PWRITE_apb),
        .PADDR   (PADDR_apb),
        .PWDATA  (PWDATA_apb),
        .PRDATA  (PRDATA_dmac),
        .PREADY  (PREADY_dmac),
        .PSLVERR (),
        .dma_src  (dma_src),
        .dma_dst  (dma_dst),
        .dma_len  (dma_len),
        .dma_start(dma_start),
        .dma_busy (dmac_busy),
        .dma_done (dmac_done)
    );

    // ── DMAC AHB master (M1) ──────────────────────────────────────────────────
    dmac_ahb_master u_dmac (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .dmac_src    (dma_src),
        .dmac_dst    (dma_dst),
        .dmac_len    (dma_len),
        .dmac_enable (dma_start),
        .HRDATA      (HRDATA_s),
        .HREADY      (HREADY_s),
        .HGRANT      (HGRANT[1]),
        .HADDR       (dmac_HADDR),
        .HTRANS      (dmac_HTRANS),
        .HWRITE      (dmac_HWRITE),
        .HSIZE       (dmac_HSIZE),
        .HWDATA      (dmac_HWDATA),
        .HBUSREQ     (dmac_HBUSREQ),
        .dmac_busy   (dmac_busy),
        .dmac_done   (dmac_done)
    );

    // ── CPU (datapath + pipeline) ─────────────────────────────────────────────
    // D-bus HREADY is qualified by CPU grant: stall pipeline when DMAC owns the bus.
    wire cpu_d_hready = HGRANT[0] & HREADY_s;

    rv32imc_core u_cpu (
        .clk_i        (HCLK),
        .rst_n_i      (HRESETn),
        .pc_dbg_o     (pc_dbg_o),
        // I-fetch → ROM Port A (always ready, dedicated port)
        .HADDR_if_o   (if_HADDR),
        .HTRANS_if_o  (if_HTRANS),
        .HWRITE_if_o  (),
        .HSIZE_if_o   (),
        .HWDATA_if_o  (),
        .HRDATA_if_i  (HRDATA_rom_a),
        .HREADY_if_i  (1'b1),
        // D-access → shared data bus
        .HADDR_dm_o   (cpu_HADDR),
        .HTRANS_dm_o  (cpu_HTRANS),
        .HWRITE_dm_o  (cpu_HWRITE),
        .HSIZE_dm_o   (cpu_HSIZE),
        .HWDATA_dm_o  (cpu_HWDATA),
        .HRDATA_dm_i  (HRDATA_s),
        .HREADY_dm_i  (cpu_d_hready),
        .HBUSREQ_dm_o (cpu_HBUSREQ)
    );

endmodule
