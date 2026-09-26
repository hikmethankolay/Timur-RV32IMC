`timescale 1ns/1ps
//
// ahb_bus_mux_tb: address/control follow HMASTER, HWDATA follows
// HMASTER_DATA (Phase 9). Combinational: apply, wait 10 ns, compare.
// Vector: HMASTER HMASTER_DATA, CPU and DMAC signals, expected bus signals.
//
module ahb_bus_mux_tb;

    reg         HMASTER, HMASTER_DATA;
    reg  [31:0] HADDR_CPU, HWDATA_CPU, HADDR_DMAC, HWDATA_DMAC;
    reg  [1:0]  HTRANS_CPU, HTRANS_DMAC;
    reg         HWRITE_CPU, HWRITE_DMAC;
    reg  [2:0]  HSIZE_CPU, HSIZE_DMAC;
    wire [31:0] HADDR, HWDATA;
    wire [1:0]  HTRANS;
    wire        HWRITE;
    wire [2:0]  HSIZE;

    ahb_bus_mux dut (
        .HMASTER      (HMASTER),
        .HMASTER_DATA (HMASTER_DATA),
        .HADDR_CPU    (HADDR_CPU),
        .HTRANS_CPU   (HTRANS_CPU),
        .HWRITE_CPU   (HWRITE_CPU),
        .HSIZE_CPU    (HSIZE_CPU),
        .HWDATA_CPU   (HWDATA_CPU),
        .HADDR_DMAC   (HADDR_DMAC),
        .HTRANS_DMAC  (HTRANS_DMAC),
        .HWRITE_DMAC  (HWRITE_DMAC),
        .HSIZE_DMAC   (HSIZE_DMAC),
        .HWDATA_DMAC  (HWDATA_DMAC),
        .HADDR        (HADDR),
        .HTRANS       (HTRANS),
        .HWRITE       (HWRITE),
        .HSIZE        (HSIZE),
        .HWDATA       (HWDATA)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      e_haddr, e_hwdata;
    reg [1:0]       e_htrans;
    reg             e_hwrite;
    reg [2:0]       e_hsize;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        {HMASTER, HMASTER_DATA} = 2'b0;
        {HADDR_CPU, HTRANS_CPU, HWRITE_CPU, HSIZE_CPU, HWDATA_CPU} = 70'b0;
        {HADDR_DMAC, HTRANS_DMAC, HWRITE_DMAC, HSIZE_DMAC, HWDATA_DMAC} = 70'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/ahb_bus_mux_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ahb_bus_mux_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %h %b %b %b %h %h %b %b %b %h %h %b %b %b %h",
                            HMASTER, HMASTER_DATA,
                            HADDR_CPU, HTRANS_CPU, HWRITE_CPU, HSIZE_CPU, HWDATA_CPU,
                            HADDR_DMAC, HTRANS_DMAC, HWRITE_DMAC, HSIZE_DMAC, HWDATA_DMAC,
                            e_haddr, e_htrans, e_hwrite, e_hsize, e_hwdata) == 17) begin
                    #10;
                    total = total + 1;
                    if (HADDR !== e_haddr || HTRANS !== e_htrans || HWRITE !== e_hwrite ||
                        HSIZE !== e_hsize || HWDATA !== e_hwdata) begin
                        failed = failed + 1;
                        $display("FAIL master=%b data=%b | got %h %b %b %b %h | expected %h %b %b %b %h",
                                 HMASTER, HMASTER_DATA, HADDR, HTRANS, HWRITE, HSIZE, HWDATA,
                                 e_haddr, e_htrans, e_hwrite, e_hsize, e_hwdata);
                    end else
                        $display("PASS master=%b data=%b | %h %b %b %b %h",
                                 HMASTER, HMASTER_DATA, HADDR, HTRANS, HWRITE, HSIZE, HWDATA);
                end
            end
            $fclose(fd);
        end

        if (total == 0)
            $display("FAIL no test vectors were applied");
        if (failed == 0 && total > 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $stop;
    end

endmodule
