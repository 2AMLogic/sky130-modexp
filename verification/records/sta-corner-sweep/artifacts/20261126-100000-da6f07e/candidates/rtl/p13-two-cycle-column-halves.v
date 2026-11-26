// P13 kernel: DR-0017 two pipelined column halves (DR-0014 candidate 2).
// Radix-2 carry-save Montgomery, N = WIDTH+2 columns, WIDTH+2 iterations,
// R = 2^N. Each iteration takes two clocks, never overlapped:
//   ph=0 (low clock):  columns 0..H-1 advance. The only high-group signal read
//        is column H's s1 (S[H]^C[H]^bi[H], old values, high not yet updated).
//        The carry c1[H-1] leaving the low group is captured in cb.
//   ph=1 (high clock): columns H..N-1 advance using cb (the boundary carry) and
//        qr (the quotient bit). At the end of this clock bi/a shift, and the
//        NEXT iteration's quotient bit is formed from the new column 0 (low
//        group, already updated) and next bi[0] = a[0]&b[0], and stored in qr.
// So the low-clock path starts from the qr flop (q is not recomputed from
// column 0 on that clock) and the one-bit right-shift feedback high -> low is
// the S[H],C[H] read in the low clock after the high group's update.
// Timing-probe interface (not the modexp handshake): load for one clock,
// then 2*(WIDTH+2) clocks, then s_out/c_out hold S/C (T = S + C).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output wire [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam H = N / 2;            // low group = columns 0..H-1
  reg [WIDTH-1:0] a, b, m, bi_r;
  reg [N-1:0] S, C;
  reg cb, qr, ph;
  assign s_out = S;
  assign c_out = C;
  wire [N-1:0] bi  = {2'b00, bi_r};
  wire [N-1:0] qmx = {2'b00, {WIDTH{qr}} & m};
  wire [N-1:0] s1  = S ^ C ^ bi;
  wire [N-1:0] c1  = (S & C) | (S & bi) | (C & bi);
  // low clock: carry into column j is c1[j-1] (live)
  wire [N-1:0] c1s_lo = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2_lo  = s1 ^ c1s_lo ^ qmx;
  wire [N-1:0] c2_lo  = (s1 & c1s_lo) | (s1 & qmx) | (c1s_lo & qmx);
  wire [H-1:0] S_lo_n = s2_lo[H:1];
  wire [H-1:0] C_lo_n = c2_lo[H-1:0];
  // high clock: carry into column H is the registered cb
  wire [N-H-1:0] c1s_hi = {c1[N-2:H], cb};
  wire [N-H-1:0] s1_hi  = s1[N-1:H];
  wire [N-H-1:0] qm_hi  = qmx[N-1:H];
  wire [N-H-1:0] s2_hi  = s1_hi ^ c1s_hi ^ qm_hi;
  wire [N-H-1:0] c2_hi  = (s1_hi & c1s_hi) | (s1_hi & qm_hi) | (c1s_hi & qm_hi);
  wire [N-H-1:0] S_hi_n = {1'b0, s2_hi[N-H-1:1]};
  wire [N-H-1:0] C_hi_n = {1'b0, c2_hi[N-H-2:0]};
  wire q_next = S[0] ^ C[0] ^ (a[0] & b[0]);
  wire q_load = a_in[0] & b_in[0];
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0;
      cb <= 0; qr <= 0; ph <= 0;
    end else if (load) begin
      a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0; cb <= 0;
      bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      qr <= q_load; ph <= 1'b0;
    end else begin
      ph <= ~ph;
      if (!ph) begin
        S[H-1:0] <= S_lo_n; C[H-1:0] <= C_lo_n; cb <= c1[H-1];
      end else begin
        S[N-1:H] <= S_hi_n; C[N-1:H] <= C_hi_n;
        a <= a >> 1; bi_r <= a[0] ? b : {WIDTH{1'b0}};
        qr <= q_next;
      end
    end
  end
endmodule
