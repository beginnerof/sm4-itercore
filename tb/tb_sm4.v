// Self-checking TB: GM/T 0002 standard vector + decrypt round-trip via MMIO

`timescale 1ns/1ps

module tb_sm4;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg         wr = 0;
    reg  [5:0]  waddr = 0;
    reg  [31:0] wdata = 0;
    reg         rd = 0;
    reg  [5:0]  raddr = 0;
    wire [31:0] rdata;

    integer errors = 0;
    integer checks = 0;

    sm4_top dut (
        .clk(clk), .rst_n(rst_n),
        .wr(wr), .waddr(waddr), .wdata(wdata),
        .rd(rd), .raddr(raddr), .rdata(rdata),
        .irq_unused()
    );

    task check;
        input cond;
        input [511:0] name;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("[FAIL] %0s (t=%0t)", name, $time);
            end else begin
                $display("[ OK ] %0s", name);
            end
        end
    endtask

    task bus_write;
        input [5:0]  a;
        input [31:0] d;
        begin
            @(posedge clk);
            wr <= 1'b1; waddr <= a; wdata <= d;
            @(posedge clk);
            wr <= 1'b0;
        end
    endtask

    task bus_read;
        input  [5:0]  a;
        output [31:0] d;
        begin
            @(posedge clk);
            rd <= 1'b1; raddr <= a;
            @(posedge clk);
            d = rdata;
            rd <= 1'b0;
        end
    endtask

    task wait_done;
        reg [31:0] st;
        integer guard;
        begin
            guard = 0;
            st = 32'h0;
            while (st[1] !== 1'b1 && guard < 200) begin
                bus_read(6'h04, st);
                guard = guard + 1;
            end
            check(st[1] == 1'b1, "done asserted");
        end
    endtask

    task load_key;
        input [127:0] k;
        begin
            bus_write(6'h08, k[127:96]);
            bus_write(6'h0C, k[95:64]);
            bus_write(6'h10, k[63:32]);
            bus_write(6'h14, k[31:0]);
        end
    endtask

    task load_din;
        input [127:0] d;
        begin
            bus_write(6'h18, d[127:96]);
            bus_write(6'h1C, d[95:64]);
            bus_write(6'h20, d[63:32]);
            bus_write(6'h24, d[31:0]);
        end
    endtask

    task read_dout;
        output [127:0] d;
        reg [31:0] w0, w1, w2, w3;
        begin
            bus_read(6'h28, w0);
            bus_read(6'h2C, w1);
            bus_read(6'h30, w2);
            bus_read(6'h34, w3);
            d = {w0, w1, w2, w3};
        end
    endtask

    // GM/T 0002 sample
    localparam [127:0] KEY1 = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] PT1  = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] CT1  = 128'h681edf34d206965e86b3e94f536e4246;

    // second vector (same key, different PT) — CT from scripts/sm4_ref.py
    localparam [127:0] KEY2 = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] PT2  = 128'hfedcba98765432100123456789abcdef;
    localparam [127:0] CT2  = 128'hf0a2b07e64dd2c2590f93e4edd90fbb4;

    reg [127:0] dout;
    reg [31:0]  ver, st;

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_sm4.vcd");
            $dumpvars(0, tb_sm4);
        end

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        bus_read(6'h38, ver);
        check(ver == 32'h0002_0000, "VERSION == 0x00020000");

        // ---- Encrypt vector 1 ----
        $display("\n=== ENCRYPT vector 1 ===");
        load_key(KEY1);
        load_din(PT1);
        bus_write(6'h00, 32'h1); // start, encrypt
        wait_done;
        read_dout(dout);
        $display("CT = %032h", dout);
        check(dout === CT1, "ENCRYPT vector1");
        bus_write(6'h04, 32'h2); // clear done

        // ---- Decrypt vector 1 ----
        $display("\n=== DECRYPT vector 1 ===");
        load_key(KEY1);
        load_din(CT1);
        bus_write(6'h00, 32'h3); // start + decrypt
        wait_done;
        read_dout(dout);
        $display("PT = %032h", dout);
        check(dout === PT1, "DECRYPT vector1");
        bus_write(6'h04, 32'h2);

        // ---- Encrypt vector 2 ----
        $display("\n=== ENCRYPT vector 2 ===");
        load_key(KEY2);
        load_din(PT2);
        bus_write(6'h00, 32'h1);
        wait_done;
        read_dout(dout);
        $display("CT = %032h", dout);
        check(dout === CT2, "ENCRYPT vector2");
        bus_write(6'h04, 32'h2);

        // ---- Decrypt vector 2 ----
        $display("\n=== DECRYPT vector 2 ===");
        load_key(KEY2);
        load_din(CT2);
        bus_write(6'h00, 32'h3);
        wait_done;
        read_dout(dout);
        check(dout === PT2, "DECRYPT vector2");

        $display("----------------------------------------");
        if (errors == 0)
            $display("PASS  (%0d checks)", checks);
        else
            $display("FAIL  (%0d errors / %0d checks)", errors, checks);
        $display("----------------------------------------");
        $finish;
    end

    initial begin
        #200000;
        $display("[FAIL] timeout");
        $display("FAIL");
        $finish;
    end

endmodule
