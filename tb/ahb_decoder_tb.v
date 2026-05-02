`timescale 1ns/1ps
module ahb_decoder_tb;

    reg         HCLK;
    reg         HRESETn;
    reg  [31:0] HADDR;
    reg  [31:0] HRDATA_rom, HRDATA_ram, HRDATA_apb;
    reg         HREADY_rom, HREADY_ram, HREADY_apb;

    wire        HSEL_rom, HSEL_ram, HSEL_apb;
    wire [31:0] HRDATA;
    wire        HREADY;

    ahb_decoder dut (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR),
        .HRDATA_rom (HRDATA_rom),
        .HREADY_rom (HREADY_rom),
        .HRDATA_ram (HRDATA_ram),
        .HREADY_ram (HREADY_ram),
        .HRDATA_apb (HRDATA_apb),
        .HREADY_apb (HREADY_apb),
        .HSEL_rom   (HSEL_rom),
        .HSEL_ram   (HSEL_ram),
        .HSEL_apb   (HSEL_apb),
        .HRDATA     (HRDATA),
        .HREADY     (HREADY)
    );

    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    task tick;
        begin
            @(posedge HCLK);
            #1;
        end
    endtask

    task check_selects;
        input [255:0] label;
        input         exp_sel_rom;
        input         exp_sel_ram;
        input         exp_sel_apb;
        begin
            #1;
            test_num = test_num + 1;
            total    = total + 1;
            if (HSEL_rom !== exp_sel_rom || HSEL_ram !== exp_sel_ram || HSEL_apb !== exp_sel_apb) begin
                $display("FAIL T%0d %0s: SEL(r/m/a)=%b%b%b | exp %b%b%b",
                          test_num, label,
                          HSEL_rom, HSEL_ram, HSEL_apb,
                          exp_sel_rom, exp_sel_ram, exp_sel_apb);
                failed = failed + 1;
            end else begin
                $display("PASS T%0d %0s: SEL(r/m/a)=%b%b%b",
                          test_num, label,
                          HSEL_rom, HSEL_ram, HSEL_apb);
            end
        end
    endtask

    task check_data;
        input [255:0] label;
        input [31:0] exp_hrdata;
        input         exp_hready;
        begin
            tick;
            test_num = test_num + 1;
            total    = total + 1;
            if (HRDATA !== exp_hrdata || HREADY !== exp_hready) begin
                $display("FAIL T%0d %0s: HRDATA=%h HREADY=%b | exp %h %b",
                          test_num, label, HRDATA, HREADY, exp_hrdata, exp_hready);
                failed = failed + 1;
            end else begin
                $display("PASS T%0d %0s: HRDATA=%h HREADY=%b",
                          test_num, label, HRDATA, HREADY);
            end
        end
    endtask

    task check_hold_data;
        input [255:0] label;
        input [31:0] exp_hrdata;
        input         exp_hready;
        begin
            #1;
            test_num = test_num + 1;
            total    = total + 1;
            if (HRDATA !== exp_hrdata || HREADY !== exp_hready) begin
                $display("FAIL T%0d %0s: HRDATA=%h HREADY=%b | exp %h %b",
                          test_num, label, HRDATA, HREADY, exp_hrdata, exp_hready);
                failed = failed + 1;
            end else begin
                $display("PASS T%0d %0s: HRDATA=%h HREADY=%b",
                          test_num, label, HRDATA, HREADY);
            end
        end
    endtask

    initial begin
        HADDR      = 32'h0000_0000;
        HRDATA_rom = 32'hAABBCCDD;
        HRDATA_ram = 32'h11223344;
        HRDATA_apb = 32'h55667788;
        HREADY_rom = 1'b1;
        HREADY_ram = 1'b1;
        HREADY_apb = 1'b1;
        HRESETn    = 1'b0;

        repeat (2) tick;
        HRESETn = 1'b1;
        #1;

        // ROM region
        HADDR = 32'h0000_0000;
        check_selects("ROM base select", 1'b1, 1'b0, 1'b0);
        check_data("ROM base data", 32'hAABBCCDD, 1'b1);

        HADDR = 32'h0000_FFFF;
        check_selects("ROM top select", 1'b1, 1'b0, 1'b0);
        check_data("ROM top data", 32'hAABBCCDD, 1'b1);

        HADDR = 32'h0001_0000;
        check_selects("above ROM select", 1'b0, 1'b0, 1'b0);
        check_data("above ROM data", 32'h0000_0000, 1'b1);

        // RAM region
        HADDR = 32'h2000_0000;
        check_selects("RAM base select", 1'b0, 1'b1, 1'b0);
        check_data("RAM base data", 32'h11223344, 1'b1);

        HADDR = 32'h2000_8000;
        check_selects("RAM mid select", 1'b0, 1'b1, 1'b0);
        check_data("RAM mid data", 32'h11223344, 1'b1);

        HADDR = 32'h2000_FFFF;
        check_selects("RAM top select", 1'b0, 1'b1, 1'b0);
        check_data("RAM top data", 32'h11223344, 1'b1);

        HADDR = 32'h1FFF_FFFF;
        check_selects("below RAM select", 1'b0, 1'b0, 1'b0);
        check_data("below RAM data", 32'h0000_0000, 1'b1);

        HADDR = 32'h2001_0000;
        check_selects("above RAM select", 1'b0, 1'b0, 1'b0);
        check_data("above RAM data", 32'h0000_0000, 1'b1);

        // APB region
        HADDR = 32'h4000_0000;
        check_selects("APB base select", 1'b0, 1'b0, 1'b1);
        check_data("APB base data", 32'h55667788, 1'b1);

        HADDR = 32'h4000_0100;
        check_selects("APB GPIO off select", 1'b0, 1'b0, 1'b1);
        check_data("APB GPIO off data", 32'h55667788, 1'b1);

        HADDR = 32'h4000_0200;
        check_selects("APB DMAC off select", 1'b0, 1'b0, 1'b1);
        check_data("APB DMAC off data", 32'h55667788, 1'b1);

        // Unmapped address
        HADDR = 32'h8000_0000;
        check_selects("unmapped hi select", 1'b0, 1'b0, 1'b0);
        check_data("unmapped hi data", 32'h0000_0000, 1'b1);

        HADDR = 32'hFFFF_FFFF;
        check_selects("unmapped top select", 1'b0, 1'b0, 1'b0);
        check_data("unmapped top data", 32'h0000_0000, 1'b1);

        // HREADY mux: slave wait states
        HREADY_ram = 1'b0;
        HADDR = 32'h2000_0004;
        check_selects("RAM wait select", 1'b0, 1'b1, 1'b0);
        check_data("RAM wait HREADY", 32'h11223344, 1'b0);
        HREADY_ram = 1'b1;

        HREADY_apb = 1'b0;
        HADDR = 32'h4000_0000;
        check_selects("APB wait select", 1'b0, 1'b0, 1'b1);
        check_data("APB wait HREADY", 32'h55667788, 1'b0);
        HREADY_apb = 1'b1;

        HREADY_rom = 1'b0;
        HADDR = 32'h0000_0010;
        check_selects("ROM wait select", 1'b1, 1'b0, 1'b0);
        check_data("ROM wait HREADY", 32'hAABBCCDD, 1'b0);
        HREADY_rom = 1'b1;

        HREADY_ram = 1'b0;
        HREADY_apb = 1'b0;
        HADDR = 32'hC000_0000;
        check_selects("unmapped HREADY select", 1'b0, 1'b0, 1'b0);
        check_data("unmapped HREADY default", 32'h0000_0000, 1'b1);
        HREADY_ram = 1'b1;
        HREADY_apb = 1'b1;

        // HRDATA mux: live data from each slave
        HRDATA_rom = 32'hDEAD_BEEF;
        HADDR = 32'h0000_0000;
        check_selects("ROM data update select", 1'b1, 1'b0, 1'b0);
        check_data("ROM data update", 32'hDEADBEEF, 1'b1);

        HRDATA_ram = 32'hCAFE_BABE;
        HADDR = 32'h2000_0000;
        check_selects("RAM data update select", 1'b0, 1'b1, 1'b0);
        check_data("RAM data update", 32'hCAFEBABE, 1'b1);

        // Registered data-phase behavior: address changes immediately, data holds
        HADDR = 32'h2000_0000;
        check_selects("pipeline select RAM", 1'b0, 1'b1, 1'b0);
        check_data("pipeline RAM data", 32'hCAFEBABE, 1'b1);

        HADDR = 32'h0000_0000;
        check_selects("pipeline select ROM", 1'b1, 1'b0, 1'b0);
        check_hold_data("pipeline hold RAM", 32'hCAFEBABE, 1'b1);
        check_data("pipeline update ROM", 32'hDEADBEEF, 1'b1);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
