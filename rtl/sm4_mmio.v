// SM4 MMIO wrapper (word-oriented, 32-bit host)
// Compatible offset map with aes_mmio:
//  0x00 CTRL   [0] start (self-clear) [1] decrypt
//  0x04 STATUS [0] busy [1] done (W1C)
//  0x08 KEY0   ... KEY3 @ 0x14   (KEY0 = bits [127:96])
//  0x18 DIN0   ... DIN3 @ 0x24
//  0x28 DOUT0  ... DOUT3 @ 0x34
//  0x38 VERSION = 0x00020000

module sm4_mmio (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr,
    input  wire [5:0]  waddr,
    input  wire [31:0] wdata,
    input  wire        rd,
    input  wire [5:0]  raddr,
    output reg  [31:0] rdata
);
    reg [127:0] key_r, din_r;
    wire [127:0] dout_w;
    wire busy, done_pulse;
    reg  start_r, dec_r, done_sticky;

    sm4_core u_sm4 (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start_r),
        .decrypt (dec_r),
        .key     (key_r),
        .din     (din_r),
        .dout    (dout_w),
        .busy    (busy),
        .done    (done_pulse)
    );

    wire [3:0] woff = waddr[5:2];
    wire [3:0] roff = raddr[5:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_r  <= 128'h0;
            din_r  <= 128'h0;
            start_r<= 1'b0;
            dec_r  <= 1'b0;
            done_sticky <= 1'b0;
        end else begin
            start_r <= 1'b0;
            if (done_pulse)
                done_sticky <= 1'b1;
            if (wr) begin
                case (woff)
                    4'h0: begin
                        dec_r <= wdata[1];
                        if (wdata[0] && !busy)
                            start_r <= 1'b1;
                    end
                    4'h1: if (wdata[1]) done_sticky <= 1'b0;
                    4'h2: key_r[127:96] <= wdata;
                    4'h3: key_r[95:64]  <= wdata;
                    4'h4: key_r[63:32]  <= wdata;
                    4'h5: key_r[31:0]   <= wdata;
                    4'h6: din_r[127:96] <= wdata;
                    4'h7: din_r[95:64]  <= wdata;
                    4'h8: din_r[63:32]  <= wdata;
                    4'h9: din_r[31:0]   <= wdata;
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (roff)
            4'h0:    rdata = {30'd0, dec_r, 1'b0};
            4'h1:    rdata = {30'd0, done_sticky, busy};
            4'h2:    rdata = key_r[127:96];
            4'h3:    rdata = key_r[95:64];
            4'h4:    rdata = key_r[63:32];
            4'h5:    rdata = key_r[31:0];
            4'h6:    rdata = din_r[127:96];
            4'h7:    rdata = din_r[95:64];
            4'h8:    rdata = din_r[63:32];
            4'h9:    rdata = din_r[31:0];
            4'hA:    rdata = dout_w[127:96];
            4'hB:    rdata = dout_w[95:64];
            4'hC:    rdata = dout_w[63:32];
            4'hD:    rdata = dout_w[31:0];
            4'hE:    rdata = 32'h0002_0000; // VERSION
            default: rdata = 32'h0;
        endcase
    end

endmodule
