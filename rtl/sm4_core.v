// SM4 iterative core
// - 32-round Feistel-like, one round reused
// - Key expansion first (32 cycles), then 32 data rounds
// - decrypt = encrypt with reversed round keys
// - ~65+ cycles / block (keyexp 32 + round 32 + 1)

module sm4_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt,
    input  wire [127:0] key,
    input  wire [127:0] din,
    output reg  [127:0] dout,
    output reg          busy,
    output reg          done
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_KEXP  = 2'd1,
                     S_ROUND = 2'd2,
                     S_DONE  = 2'd3;

    localparam [31:0] FK0 = 32'hA3B1BAC6;
    localparam [31:0] FK1 = 32'h56AA3350;
    localparam [31:0] FK2 = 32'h677D9197;
    localparam [31:0] FK3 = 32'hB27022DC;

    reg [1:0]  state;
    reg [5:0]  cnt;
    reg        dec_r;

    reg [31:0] k0, k1, k2, k3;
    reg [31:0] rk [0:31];

    reg [31:0] x0, x1, x2, x3;
    reg [31:0] x4;

    // ---- CK table ----
    function [31:0] ck;
        input [4:0] i;
        begin
            case (i)
                5'd0:  ck = 32'h00070e15; 5'd1:  ck = 32'h1c232a31;
                5'd2:  ck = 32'h383f464d; 5'd3:  ck = 32'h545b6269;
                5'd4:  ck = 32'h70777e85; 5'd5:  ck = 32'h8c939aa1;
                5'd6:  ck = 32'ha8afb6bd; 5'd7:  ck = 32'hc4cbd2d9;
                5'd8:  ck = 32'he0e7eef5; 5'd9:  ck = 32'hfc030a11;
                5'd10: ck = 32'h181f262d; 5'd11: ck = 32'h343b4249;
                5'd12: ck = 32'h50575e65; 5'd13: ck = 32'h6c737a81;
                5'd14: ck = 32'h888f969d; 5'd15: ck = 32'ha4abb2b9;
                5'd16: ck = 32'hc0c7ced5; 5'd17: ck = 32'hdce3eaf1;
                5'd18: ck = 32'hf8ff060d; 5'd19: ck = 32'h141b2229;
                5'd20: ck = 32'h30373e45; 5'd21: ck = 32'h4c535a61;
                5'd22: ck = 32'h686f767d; 5'd23: ck = 32'h848b9299;
                5'd24: ck = 32'ha0a7aeb5; 5'd25: ck = 32'hbcc3cad1;
                5'd26: ck = 32'hd8dfe6ed; 5'd27: ck = 32'hf4fb0209;
                5'd28: ck = 32'h10171e25; 5'd29: ck = 32'h2c333a41;
                5'd30: ck = 32'h484f565d; 5'd31: ck = 32'h646b7279;
                default: ck = 32'h0;
            endcase
        end
    endfunction

    function [31:0] rotl;
        input [31:0] x;
        input [4:0]  n;
        begin
            rotl = (x << n) | (x >> (32 - n));
        end
    endfunction

    // S-box (4 parallel instances via function using module — use function copy)
    function [7:0] sbox_f;
        input [7:0] a;
        begin
            case (a)
                8'h00: sbox_f=8'hd6; 8'h01: sbox_f=8'h90; 8'h02: sbox_f=8'he9; 8'h03: sbox_f=8'hfe;
                8'h04: sbox_f=8'hcc; 8'h05: sbox_f=8'he1; 8'h06: sbox_f=8'h3d; 8'h07: sbox_f=8'hb7;
                8'h08: sbox_f=8'h16; 8'h09: sbox_f=8'hb6; 8'h0a: sbox_f=8'h14; 8'h0b: sbox_f=8'hc2;
                8'h0c: sbox_f=8'h28; 8'h0d: sbox_f=8'hfb; 8'h0e: sbox_f=8'h2c; 8'h0f: sbox_f=8'h05;
                8'h10: sbox_f=8'h2b; 8'h11: sbox_f=8'h67; 8'h12: sbox_f=8'h9a; 8'h13: sbox_f=8'h76;
                8'h14: sbox_f=8'h2a; 8'h15: sbox_f=8'hbe; 8'h16: sbox_f=8'h04; 8'h17: sbox_f=8'hc3;
                8'h18: sbox_f=8'haa; 8'h19: sbox_f=8'h44; 8'h1a: sbox_f=8'h13; 8'h1b: sbox_f=8'h26;
                8'h1c: sbox_f=8'h49; 8'h1d: sbox_f=8'h86; 8'h1e: sbox_f=8'h06; 8'h1f: sbox_f=8'h99;
                8'h20: sbox_f=8'h9c; 8'h21: sbox_f=8'h42; 8'h22: sbox_f=8'h50; 8'h23: sbox_f=8'hf4;
                8'h24: sbox_f=8'h91; 8'h25: sbox_f=8'hef; 8'h26: sbox_f=8'h98; 8'h27: sbox_f=8'h7a;
                8'h28: sbox_f=8'h33; 8'h29: sbox_f=8'h54; 8'h2a: sbox_f=8'h0b; 8'h2b: sbox_f=8'h43;
                8'h2c: sbox_f=8'hed; 8'h2d: sbox_f=8'hcf; 8'h2e: sbox_f=8'hac; 8'h2f: sbox_f=8'h62;
                8'h30: sbox_f=8'he4; 8'h31: sbox_f=8'hb3; 8'h32: sbox_f=8'h1c; 8'h33: sbox_f=8'ha9;
                8'h34: sbox_f=8'hc9; 8'h35: sbox_f=8'h08; 8'h36: sbox_f=8'he8; 8'h37: sbox_f=8'h95;
                8'h38: sbox_f=8'h80; 8'h39: sbox_f=8'hdf; 8'h3a: sbox_f=8'h94; 8'h3b: sbox_f=8'hfa;
                8'h3c: sbox_f=8'h75; 8'h3d: sbox_f=8'h8f; 8'h3e: sbox_f=8'h3f; 8'h3f: sbox_f=8'ha6;
                8'h40: sbox_f=8'h47; 8'h41: sbox_f=8'h07; 8'h42: sbox_f=8'ha7; 8'h43: sbox_f=8'hfc;
                8'h44: sbox_f=8'hf3; 8'h45: sbox_f=8'h73; 8'h46: sbox_f=8'h17; 8'h47: sbox_f=8'hba;
                8'h48: sbox_f=8'h83; 8'h49: sbox_f=8'h59; 8'h4a: sbox_f=8'h3c; 8'h4b: sbox_f=8'h19;
                8'h4c: sbox_f=8'he6; 8'h4d: sbox_f=8'h85; 8'h4e: sbox_f=8'h4f; 8'h4f: sbox_f=8'ha8;
                8'h50: sbox_f=8'h68; 8'h51: sbox_f=8'h6b; 8'h52: sbox_f=8'h81; 8'h53: sbox_f=8'hb2;
                8'h54: sbox_f=8'h71; 8'h55: sbox_f=8'h64; 8'h56: sbox_f=8'hda; 8'h57: sbox_f=8'h8b;
                8'h58: sbox_f=8'hf8; 8'h59: sbox_f=8'heb; 8'h5a: sbox_f=8'h0f; 8'h5b: sbox_f=8'h4b;
                8'h5c: sbox_f=8'h70; 8'h5d: sbox_f=8'h56; 8'h5e: sbox_f=8'h9d; 8'h5f: sbox_f=8'h35;
                8'h60: sbox_f=8'h1e; 8'h61: sbox_f=8'h24; 8'h62: sbox_f=8'h0e; 8'h63: sbox_f=8'h5e;
                8'h64: sbox_f=8'h63; 8'h65: sbox_f=8'h58; 8'h66: sbox_f=8'hd1; 8'h67: sbox_f=8'ha2;
                8'h68: sbox_f=8'h25; 8'h69: sbox_f=8'h22; 8'h6a: sbox_f=8'h7c; 8'h6b: sbox_f=8'h3b;
                8'h6c: sbox_f=8'h01; 8'h6d: sbox_f=8'h21; 8'h6e: sbox_f=8'h78; 8'h6f: sbox_f=8'h87;
                8'h70: sbox_f=8'hd4; 8'h71: sbox_f=8'h00; 8'h72: sbox_f=8'h46; 8'h73: sbox_f=8'h57;
                8'h74: sbox_f=8'h9f; 8'h75: sbox_f=8'hd3; 8'h76: sbox_f=8'h27; 8'h77: sbox_f=8'h52;
                8'h78: sbox_f=8'h4c; 8'h79: sbox_f=8'h36; 8'h7a: sbox_f=8'h02; 8'h7b: sbox_f=8'he7;
                8'h7c: sbox_f=8'ha0; 8'h7d: sbox_f=8'hc4; 8'h7e: sbox_f=8'hc8; 8'h7f: sbox_f=8'h9e;
                8'h80: sbox_f=8'hea; 8'h81: sbox_f=8'hbf; 8'h82: sbox_f=8'h8a; 8'h83: sbox_f=8'hd2;
                8'h84: sbox_f=8'h40; 8'h85: sbox_f=8'hc7; 8'h86: sbox_f=8'h38; 8'h87: sbox_f=8'hb5;
                8'h88: sbox_f=8'ha3; 8'h89: sbox_f=8'hf7; 8'h8a: sbox_f=8'hf2; 8'h8b: sbox_f=8'hce;
                8'h8c: sbox_f=8'hf9; 8'h8d: sbox_f=8'h61; 8'h8e: sbox_f=8'h15; 8'h8f: sbox_f=8'ha1;
                8'h90: sbox_f=8'he0; 8'h91: sbox_f=8'hae; 8'h92: sbox_f=8'h5d; 8'h93: sbox_f=8'ha4;
                8'h94: sbox_f=8'h9b; 8'h95: sbox_f=8'h34; 8'h96: sbox_f=8'h1a; 8'h97: sbox_f=8'h55;
                8'h98: sbox_f=8'had; 8'h99: sbox_f=8'h93; 8'h9a: sbox_f=8'h32; 8'h9b: sbox_f=8'h30;
                8'h9c: sbox_f=8'hf5; 8'h9d: sbox_f=8'h8c; 8'h9e: sbox_f=8'hb1; 8'h9f: sbox_f=8'he3;
                8'ha0: sbox_f=8'h1d; 8'ha1: sbox_f=8'hf6; 8'ha2: sbox_f=8'he2; 8'ha3: sbox_f=8'h2e;
                8'ha4: sbox_f=8'h82; 8'ha5: sbox_f=8'h66; 8'ha6: sbox_f=8'hca; 8'ha7: sbox_f=8'h60;
                8'ha8: sbox_f=8'hc0; 8'ha9: sbox_f=8'h29; 8'haa: sbox_f=8'h23; 8'hab: sbox_f=8'hab;
                8'hac: sbox_f=8'h0d; 8'had: sbox_f=8'h53; 8'hae: sbox_f=8'h4e; 8'haf: sbox_f=8'h6f;
                8'hb0: sbox_f=8'hd5; 8'hb1: sbox_f=8'hdb; 8'hb2: sbox_f=8'h37; 8'hb3: sbox_f=8'h45;
                8'hb4: sbox_f=8'hde; 8'hb5: sbox_f=8'hfd; 8'hb6: sbox_f=8'h8e; 8'hb7: sbox_f=8'h2f;
                8'hb8: sbox_f=8'h03; 8'hb9: sbox_f=8'hff; 8'hba: sbox_f=8'h6a; 8'hbb: sbox_f=8'h72;
                8'hbc: sbox_f=8'h6d; 8'hbd: sbox_f=8'h6c; 8'hbe: sbox_f=8'h5b; 8'hbf: sbox_f=8'h51;
                8'hc0: sbox_f=8'h8d; 8'hc1: sbox_f=8'h1b; 8'hc2: sbox_f=8'haf; 8'hc3: sbox_f=8'h92;
                8'hc4: sbox_f=8'hbb; 8'hc5: sbox_f=8'hdd; 8'hc6: sbox_f=8'hbc; 8'hc7: sbox_f=8'h7f;
                8'hc8: sbox_f=8'h11; 8'hc9: sbox_f=8'hd9; 8'hca: sbox_f=8'h5c; 8'hcb: sbox_f=8'h41;
                8'hcc: sbox_f=8'h1f; 8'hcd: sbox_f=8'h10; 8'hce: sbox_f=8'h5a; 8'hcf: sbox_f=8'hd8;
                8'hd0: sbox_f=8'h0a; 8'hd1: sbox_f=8'hc1; 8'hd2: sbox_f=8'h31; 8'hd3: sbox_f=8'h88;
                8'hd4: sbox_f=8'ha5; 8'hd5: sbox_f=8'hcd; 8'hd6: sbox_f=8'h7b; 8'hd7: sbox_f=8'hbd;
                8'hd8: sbox_f=8'h2d; 8'hd9: sbox_f=8'h74; 8'hda: sbox_f=8'hd0; 8'hdb: sbox_f=8'h12;
                8'hdc: sbox_f=8'hb8; 8'hdd: sbox_f=8'he5; 8'hde: sbox_f=8'hb4; 8'hdf: sbox_f=8'hb0;
                8'he0: sbox_f=8'h89; 8'he1: sbox_f=8'h69; 8'he2: sbox_f=8'h97; 8'he3: sbox_f=8'h4a;
                8'he4: sbox_f=8'h0c; 8'he5: sbox_f=8'h96; 8'he6: sbox_f=8'h77; 8'he7: sbox_f=8'h7e;
                8'he8: sbox_f=8'h65; 8'he9: sbox_f=8'hb9; 8'hea: sbox_f=8'hf1; 8'heb: sbox_f=8'h09;
                8'hec: sbox_f=8'hc5; 8'hed: sbox_f=8'h6e; 8'hee: sbox_f=8'hc6; 8'hef: sbox_f=8'h84;
                8'hf0: sbox_f=8'h18; 8'hf1: sbox_f=8'hf0; 8'hf2: sbox_f=8'h7d; 8'hf3: sbox_f=8'hec;
                8'hf4: sbox_f=8'h3a; 8'hf5: sbox_f=8'hdc; 8'hf6: sbox_f=8'h4d; 8'hf7: sbox_f=8'h20;
                8'hf8: sbox_f=8'h79; 8'hf9: sbox_f=8'hee; 8'hfa: sbox_f=8'h5f; 8'hfb: sbox_f=8'h3e;
                8'hfc: sbox_f=8'hd7; 8'hfd: sbox_f=8'hcb; 8'hfe: sbox_f=8'h39; 8'hff: sbox_f=8'h48;
                default: sbox_f = 8'h00;
            endcase
        end
    endfunction

    function [31:0] tau;
        input [31:0] b;
        begin
            tau = {sbox_f(b[31:24]), sbox_f(b[23:16]), sbox_f(b[15:8]), sbox_f(b[7:0])};
        end
    endfunction

    function [31:0] l_enc;
        input [31:0] b;
        begin
            l_enc = b ^ rotl(b, 5'd2) ^ rotl(b, 5'd10) ^ rotl(b, 5'd18) ^ rotl(b, 5'd24);
        end
    endfunction

    function [31:0] l_key;
        input [31:0] b;
        begin
            l_key = b ^ rotl(b, 5'd13) ^ rotl(b, 5'd23);
        end
    endfunction

    function [31:0] t_enc;
        input [31:0] b;
        begin
            t_enc = l_enc(tau(b));
        end
    endfunction

    function [31:0] t_key;
        input [31:0] b;
        begin
            t_key = l_key(tau(b));
        end
    endfunction

    wire [31:0] k_new  = k0 ^ t_key(k1 ^ k2 ^ k3 ^ ck(cnt[4:0]));
    wire [31:0] rk_sel = dec_r ? rk[6'd31 - cnt] : rk[cnt];
    wire [31:0] x_nxt  = x0 ^ t_enc(x1 ^ x2 ^ x3 ^ rk_sel);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            cnt     <= 6'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
            dec_r   <= 1'b0;
            dout    <= 128'd0;
            k0 <= 32'd0; k1 <= 32'd0; k2 <= 32'd0; k3 <= 32'd0;
            x0 <= 32'd0; x1 <= 32'd0; x2 <= 32'd0; x3 <= 32'd0;
            x4 <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        dec_r <= decrypt;
                        k0 <= key[127:96] ^ FK0;
                        k1 <= key[95:64]  ^ FK1;
                        k2 <= key[63:32]  ^ FK2;
                        k3 <= key[31:0]   ^ FK3;
                        cnt   <= 6'd0;
                        state <= S_KEXP;
                    end
                end

                S_KEXP: begin
                    // one round-key per cycle
                    rk[cnt[4:0]] <= k_new;
                    k0 <= k1;
                    k1 <= k2;
                    k2 <= k3;
                    k3 <= k_new;
                    if (cnt == 6'd31) begin
                        cnt   <= 6'd0;
                        x0 <= din[127:96];
                        x1 <= din[95:64];
                        x2 <= din[63:32];
                        x3 <= din[31:0];
                        state <= S_ROUND;
                    end else begin
                        cnt <= cnt + 6'd1;
                    end
                end

                S_ROUND: begin
                    // X[i+4] = X[i] ^ T(...)
                    x0 <= x1;
                    x1 <= x2;
                    x2 <= x3;
                    x3 <= x_nxt;
                    if (cnt == 6'd31) begin
                        // after last round, x_nxt is X[35] which goes to x3 next cycle —
                        // capture reversed output: (X35,X34,X33,X32) = (x_nxt, x3, x2, x1)
                        // After this cycle assignment: x0<=x1(=X32? wait)
                        // Before last round: x0=X[i], x1=X[i+1], x2=X[i+2], x3=X[i+3], x_nxt=X[i+4]
                        // Output is (X[i+4], X[i+3], X[i+2], X[i+1]) after i==31
                        dout  <= {x_nxt, x3, x2, x1};
                        state <= S_DONE;
                    end
                    cnt <= cnt + 6'd1;
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
