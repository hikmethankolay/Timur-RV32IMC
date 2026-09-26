`timescale 1ns/1ps
//
// cpu_ahb_master_tb: address phase from the MEM stage, acceptance on HGRANT
// and HREADY, HWDATA loaded on acceptance and held through wait states,
// data phase tracking, bus_wait for both phases (Phase 9).
// Vector: see vectors/cpu_ahb_master_vectors.txt (x = don't care).
//
module cpu_ahb_master_tb;

    reg         clk, rst_n;
    reg  [31:0] addr, store_data, HRDATA;
    reg  [2:0]  funct3;
    reg         mem_read, mem_write, mem_valid, HGRANT, HREADY;
    wire [31:0] HADDR, HWDATA, load_data;
    wire [1:0]  HTRANS;
    wire        HWRITE, HMASTLOCK, HBUSREQ, bus_wait;
    wire [2:0]  HSIZE, HBURST;
    wire [3:0]  HPROT;

    cpu_ahb_master dut (
        .HCLK       (clk),
        .HRESETn    (rst_n),
        .addr       (addr),
        .store_data (store_data),
        .funct3     (funct3),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_valid  (mem_valid),
        .HGRANT     (HGRANT),
        .HREADY     (HREADY),
        .HRDATA     (HRDATA),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HPROT      (HPROT),
        .HMASTLOCK  (HMASTLOCK),
        .HWDATA     (HWDATA),
        .HBUSREQ    (HBUSREQ),
        .load_data  (load_data),
        .bus_wait   (bus_wait)
    );

    always #5 clk = ~clk;

    function match;
        input [31:0] got;
        input [31:0] exp;
        integer i;
        begin
            match = 1'b1;
            for (i = 0; i < 32; i = i + 1)
                if (exp[i] !== 1'bx && got[i] !== exp[i])
                    match = 1'b0;
        end
    endfunction

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      e_haddr, e_hwdata, e_load;
    reg [1:0]       e_htrans;
    reg [2:0]       e_hsize;
    reg             e_hwrite, e_hbusreq, e_bus_wait, wait_type;
    reg             ok;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        {addr, store_data, HRDATA} = 96'b0;
        funct3 = 3'b010;
        {mem_read, mem_write, mem_valid} = 3'b0;
        HGRANT = 1'b1;
        HREADY = 1'b1;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/cpu_ahb_master_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/cpu_ahb_master_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %h %b %b %b %b %b %b %h %h %b %b %b %h %b %h %b %b",
                            rst_n, addr, store_data, funct3, mem_read, mem_write, mem_valid,
                            HGRANT, HREADY, HRDATA,
                            e_haddr, e_htrans, e_hwrite, e_hsize, e_hwdata, e_hbusreq, e_load,
                            e_bus_wait, wait_type) == 19) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = match(HADDR, e_haddr) && match({30'b0, HTRANS}, {30'b0, e_htrans}) &&
                         match({31'b0, HWRITE}, {31'b0, e_hwrite}) && match({29'b0, HSIZE}, {29'b0, e_hsize}) &&
                         match(HWDATA, e_hwdata) && match({31'b0, HBUSREQ}, {31'b0, e_hbusreq}) &&
                         match(load_data, e_load) && match({31'b0, bus_wait}, {31'b0, e_bus_wait}) &&
                         (HBURST === 3'b000) && (HPROT === 4'b0011) && (HMASTLOCK === 1'b0);
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL rd=%b wr=%b v=%b grant=%b ready=%b addr=%h | got %h %b %b %b %h %b %h wait=%b | expected %h %b %b %b %h %b %h wait=%b",
                                 mem_read, mem_write, mem_valid, HGRANT, HREADY, addr,
                                 HADDR, HTRANS, HWRITE, HSIZE, HWDATA, HBUSREQ, load_data, bus_wait,
                                 e_haddr, e_htrans, e_hwrite, e_hsize, e_hwdata, e_hbusreq, e_load, e_bus_wait);
                    end else
                        $display("PASS rd=%b wr=%b v=%b grant=%b ready=%b addr=%h wait_type=%b | htrans=%b hwdata=%h bus_wait=%b",
                                 mem_read, mem_write, mem_valid, HGRANT, HREADY, addr, wait_type,
                                 HTRANS, HWDATA, bus_wait);
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
