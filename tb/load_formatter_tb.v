`timescale 1ns/1ps
//
// load_formatter_tb: byte/halfword selection and sign/zero extension for
// every funct3 and offset, including 0x80 and 0x8000 (Phase 3).
// Vector: hrdata(hex) addr(bin) funct3(bin) load_data(hex).
//
module load_formatter_tb;

    reg  [31:0] hrdata;
    reg  [1:0]  addr;
    reg  [2:0]  funct3;
    wire [31:0] load_data;

    load_formatter dut (
        .hrdata    (hrdata),
        .addr      (addr),
        .funct3    (funct3),
        .load_data (load_data)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_data;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        hrdata = 32'b0;
        addr = 2'b0;
        funct3 = 3'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/load_formatter_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/load_formatter_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %b %b %h", hrdata, addr, funct3, exp_data) == 4) begin
                    #10;
                    total = total + 1;
                    if (load_data !== exp_data) begin
                        failed = failed + 1;
                        $display("FAIL hrdata=%h addr=%b funct3=%b | got=%h expected=%h",
                                 hrdata, addr, funct3, load_data, exp_data);
                    end else
                        $display("PASS hrdata=%h addr=%b funct3=%b | load_data=%h",
                                 hrdata, addr, funct3, load_data);
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
