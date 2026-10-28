// P11 kernel: the radix-2 Montgomery step adds one of {0, b, m, b+m}, chosen by
// (a_i, q). Recode the addend set so the per-cycle datapath has ONE 3:2 level:
// b+m is computed by a carry-propagate add in a prep cycle (off the per-cycle
// path), and the addend is a 2:1 mux on q between two pre-registered vectors,
//   u = a_i ? b   : 0      (q = 0)
//   v = a_i ? b+m : m      (q = 1)
// both registered one cycle ahead like P8's operand ANDs. Price: one prep cycle
// per multiply (testbench X=1) and 2W+1 extra flops (u/v/bm vs bi_r).
// q recurrence: q = S0^C0^(a_i&b0); the carry out of bit 0 is S0|C0 (s0 = 0),
// so q' = S1^C1^add1^(S0|C0)^x_r, x_r = a_{i+1}&b0 pre-registered.
// q is held in six non-mergeable flops as in P7/P8.
// Timing-probe interface (not the modexp handshake): s_out/c_out valid W+1
// cycles after the prep cycle.
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam K = 6;
  reg [WIDTH-1:0] a, b, m;
  reg [WIDTH:0] u, v, bm;
  reg [N-1:0] S, C;
  reg [K-1:0] qc;                  // qc[0..2] = q, qc[3..5] = ~q
  reg x_r, prep;
  wire [K-1:0] qv = {~qc[5:3], qc[2:0]};   // all six decoded to q polarity
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
  wire q_d = prep ? q_l : q_n;
  wire [WIDTH:0] bm_w = {1'b0, b} + {1'b0, m};
  wire [WIDTH:0] u_n = a[0] ? {1'b0, b} : {(WIDTH+1){1'b0}};
  wire [WIDTH:0] v_n = a[0] ? (prep ? bm_w : bm) : {1'b0, m};
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_r <= 0; prep <= 0; a <= 0; b <= 0; m <= 0; u <= 0; v <= 0; bm <= 0;
      S <= 0; C <= 0; s_out <= 0; c_out <= 0;
      qc[0] <= 1'b0; qc[1] <= 1'b1; qc[3] <= 1'b1; qc[4] <= 1'b0;
    end else begin
      qc[0] <= q_d; qc[1] <= q_d; qc[3] <= ~q_d; qc[4] <= ~q_d;
      if (load) begin
        a <= a_in; b <= b_in; m <= m_in; S <= 0; C <= 0; prep <= 1'b1;
      end else begin
        prep <= 1'b0;
        x_r <= a[1] & b[0];
        a <= a >> 1;
        u <= u_n; v <= v_n;
        if (prep) bm <= bm_w;
        else begin
          S <= {1'b0, s2[N-1:1]};
          C <= {1'b0, c2[N-2:0]};
          s_out <= S; c_out <= C;
        end
      end
    end
  end
  always @(posedge clk) begin
    qc[2] <= q_d; qc[5] <= ~q_d;
  end
endmodule
