// SM4 IP top: core + MMIO

module sm4_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr,
    input  wire [5:0]  waddr,
    input  wire [31:0] wdata,
    input  wire        rd,
    input  wire [5:0]  raddr,
    output wire [31:0] rdata,
    output wire        irq_unused
);
    assign irq_unused = 1'b0;

    sm4_mmio u_mmio (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr     (wr),
        .waddr  (waddr),
        .wdata  (wdata),
        .rd     (rd),
        .raddr  (raddr),
        .rdata  (rdata)
    );
endmodule
