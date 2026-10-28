// P11c kernel: P11b with the quotient held in FOUR non-mergeable flops
// (polarity x {async-reset-0, no reset}); the async-set copies of P7-P11b are
// dfstp_2 cells with a 4.97 ns clk-to-Q at ss_n40C_1v28 (vs ~2.2 ns for the
// reset flop) and were the worst-path startpoint in P11b. Fan-out per copy is
// ~WIDTH/4.
// P11b kernel: P11a (addend set {0,b,m,b+m} recoded so the per-cycle datapath
// has ONE 3:2 level: add = q ? v : u, u = a_i?b:0, v = a_i?b+m:m, both
// pre-registered) with the b+m carry-propagate add taken OFF the single-cycle
// path. P11a's one-cycle 16-bit adder put 22 ns of ripple on a flop-to-flop
// path (WNS -13.84 ns), which measures the adder, not the kernel.
// Here b+m is computed CH bits per cycle over WIDTH/CH prep cycles: b and m
// rotate right by CH each step (a full rotation restores them), a carry flop
// links the steps, and the sum chunk shifts into bm from the top. One more
// start cycle loads u/v/q/x_r for iteration 0. Price (measured by the
// testbench, X = WIDTH/CH + 1): WIDTH/CH + 1 extra cycles per multiply, plus
// bm, cy and the one-hot step register as extra state.
// q recurrence: q = S0^C0^(a_i&b0); the carry out of bit 0 is S0|C0 (s0 = 0),
// so q' = S1^C1^add1^(S0|C0)^x_r, x_r = a_{i+1}&b0 pre-registered.
// q is held in non-mergeable flops as in P7/P8 (four here, see above).
// Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16, parameter CH = 2) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam K = 4;
  localparam PN = WIDTH / CH;
  reg [WIDTH-1:0] a, b, m;
  reg [WIDTH:0] u, v, bm;
  reg [N-1:0] S, C;
  reg [K-1:0] qc;                  // qc[0..1] = q, qc[2..3] = ~q
  reg x_r, cy, adding;
  reg [PN:0] pr;                   // one-hot: pr[0..PN-1] add steps, pr[PN] start
  wire start  = pr[PN];
  wire [K-1:0] qv = {~qc[3:2], qc[1:0]};   // all four decoded to q polarity
  wire [WIDTH:0] add_lo;
  genvar i;
  generate for (i = 0; i <= WIDTH; i = i + 1) begin : addmux
    assign add_lo[i] = qv[(i * K) / N] ? v[i] : u[i];
  end endgenerate
  wire [N-1:0] add = {1'b0, add_lo};
  wire [N-1:0] s2 = S ^ C ^ add;
  wire [N-1:0] c2 = (S & C) | (S & add) | (C & add);
  wire q_n = (S[1] ^ C[1]) ^ add[1] ^ (S[0] | C[0]) ^ x_r;
  wire q_l = a[0] & b[0];
  wire q_d = start ? q_l : q_n;
  wire [CH:0] chunk = {1'b0, b[CH-1:0]} + {1'b0, m[CH-1:0]} + {{CH{1'b0}}, cy};
  wire [WIDTH:0] u_n = a[0] ? {1'b0, b} : {(WIDTH+1){1'b0}};
  wire [WIDTH:0] v_n = a[0] ? bm : {1'b0, m};
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_r <= 0; cy <= 0; adding <= 0; pr <= 0; a <= 0; b <= 0; m <= 0; u <= 0; v <= 0;
      bm <= 0; S <= 0; C <= 0; s_out <= 0; c_out <= 0;
      qc[0] <= 1'b0; qc[2] <= 1'b0;
    end else begin
      qc[0] <= q_d; qc[2] <= ~q_d;
      if (load) begin
        a <= a_in; b <= b_in; m <= m_in; S <= 0; C <= 0; cy <= 0; pr <= 1; adding <= 1'b1;
        u <= 0; v <= 0;
      end else begin
        pr <= pr << 1;
        adding <= |pr[PN-2:0];     // registered: the next cycle is an add step
        x_r <= a[1] & b[0];
        // u = v = 0 during the add steps, so S/C stay 0 without an enable
        u <= adding ? {(WIDTH+1){1'b0}} : u_n;
        v <= adding ? {(WIDTH+1){1'b0}} : v_n;
        S <= {1'b0, s2[N-1:1]};
        C <= {1'b0, c2[N-2:0]};
        s_out <= S; c_out <= C;
        if (adding) begin
          b <= {b[CH-1:0], b[WIDTH-1:CH]};
          m <= {m[CH-1:0], m[WIDTH-1:CH]};
          cy <= chunk[CH];
          bm <= {chunk[CH], chunk[CH-1:0], bm[WIDTH-1:CH]};
        end else begin
          a <= a >> 1;
        end
      end
    end
  end
  always @(posedge clk) begin
    qc[1] <= q_d; qc[3] <= ~q_d;
  end
endmodule
