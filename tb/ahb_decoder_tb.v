`timescale 1ns/1ps
//
// ahb_decoder_tb: exactly one HSEL per mapped region, none for unmapped
// addresses; HRDATA/HREADY multiplexed with the registered data-phase select,
// which only moves when HREADY = 1; default slave answers unmapped transfers
// (Phase 9).
// Vector: HRESETn HADDR HRDATA_ROM HRDATA_RAM HRDATA_APB HREADYOUT_ROM/RAM/APB
//         exp_HSEL exp_HRDATA exp_HREADY wait_type   (x = don't care)
//
module ahb_decoder_tb;

    reg         clk, rst_n;
    reg  [31:0] HADDR, HRDATA_ROM, HRDATA_RAM, HRDATA_APB;
    reg         HREADYOUT_ROM, HREADYOUT_RAM, HREADYOUT_APB;
    wire        HSEL_ROM, HSEL_RAM, HSEL_APB;
    wire [31:0] HRDATA;
    wire        HREADY;

    ahb_decoder dut (
        .HCLK          (clk),
        .HRESETn       (rst_n),
        .HADDR         (HADDR),
        .HSEL_ROM      (HSEL_ROM),
        .HSEL_RAM      (HSEL_RAM),
        .HSEL_APB      (HSEL_APB),
        .HRDATA_ROM    (HRDATA_ROM),
        .HRDATA_RAM    (HRDATA_RAM),
        .HRDATA_APB    (HRDATA_APB),
        .HREADYOUT_ROM (HREADYOUT_ROM),
        .HREADYOUT_RAM (HREADYOUT_RAM),
        .HREADYOUT_APB (HREADYOUT_APB),
        .HRDATA        (HRDATA),
        .HREADY        (HREADY)
    );

    always #5 clk = ~clk;

    // compare, treating x bits in the expected value as don't care
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
    reg [2:0]       e_hsel;
    reg [31:0]      e_hrdata;
    reg             e_hready, wait_type;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        HADDR = 32'b0;
        {HRDATA_ROM, HRDATA_RAM, HRDATA_APB} = 96'b0;
        {HREADYOUT_ROM, HREADYOUT_RAM, HREADYOUT_APB} = 3'b111;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/ahb_decoder_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ahb_decoder_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %h %h %h %b %b %b %b %h %b %b", rst_n, HADDR,
                            HRDATA_ROM, HRDATA_RAM, HRDATA_APB,
                            HREADYOUT_ROM, HREADYOUT_RAM, HREADYOUT_APB,
                            e_hsel, e_hrdata, e_hready, wait_type) == 12) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (!match({29'b0, HSEL_APB, HSEL_RAM, HSEL_ROM}, {29'b0, e_hsel}) ||
                        !match(HRDATA, e_hrdata) || !match({31'b0, HREADY}, {31'b0, e_hready})) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b haddr=%h ready_out=%b%b%b | got hsel=%b%b%b hrdata=%h hready=%b | expected %b %h %b",
                                 rst_n, HADDR, HREADYOUT_APB, HREADYOUT_RAM, HREADYOUT_ROM,
                                 HSEL_APB, HSEL_RAM, HSEL_ROM, HRDATA, HREADY, e_hsel, e_hrdata, e_hready);
                    end else
                        $display("PASS rst_n=%b haddr=%h wait=%b | hsel=%b%b%b hrdata=%h hready=%b",
                                 rst_n, HADDR, wait_type, HSEL_APB, HSEL_RAM, HSEL_ROM, HRDATA, HREADY);
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
