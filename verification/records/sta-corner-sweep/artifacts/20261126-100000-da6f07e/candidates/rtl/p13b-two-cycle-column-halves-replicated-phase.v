// P13b kernel: P13 (DR-0017 two pipelined column halves, cut H = N/2) with the
// phase control replicated. P13's worst path was not the datapath: it was the
// single phase flop decoded through nor2 (fanout 38) and buf_4 (fanout 45) into
// every enable. Here eight phase flops ph[0..7] each toggle from their OWN
// output (so they are structurally distinct and cannot be merged by Yosys) and
// each drives one slice of the enables:
//   ph[0] S low, ph[1] C low + cb, ph[2] S high, ph[3] C high,
//   ph[4] a[7:0], ph[5] bi_r[7:0] + qr, ph[6] bi_r[WIDTH-1:8], ph[7] a[WIDTH-1:8]
// All eight are 0 after reset or load. Datapath, cut and schedule are identical
// to P13 (see that file for the clock-by-clock description).
// Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output wire [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam H = N / 2;            // low group = columns 0..H-1
  localparam WL = (WIDTH > 8) ? 8 : WIDTH / 2;   // slice boundary for a / bi_r
  reg [WIDTH-1:0] a, b, m, bi_r;
  reg [N-1:0] S, C;
  reg cb, qr;
  reg [7:0] ph;
  assign s_out = S;
  assign c_out = C;
  wire [N-1:0] bi  = {2'b00, bi_r};
  wire [N-1:0] qmx = {2'b00, {WIDTH{qr}} & m};
  wire [N-1:0] s1  = S ^ C ^ bi;
  wire [N-1:0] c1  = (S & C) | (S & bi) | (C & bi);
  wire [N-1:0] c1s_lo = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2_lo  = s1 ^ c1s_lo ^ qmx;
  wire [N-1:0] c2_lo  = (s1 & c1s_lo) | (s1 & qmx) | (c1s_lo & qmx);
  wire [H-1:0] S_lo_n = s2_lo[H:1];
  wire [H-1:0] C_lo_n = c2_lo[H-1:0];
  wire [N-H-1:0] c1s_hi = {c1[N-2:H], cb};
  wire [N-H-1:0] s1_hi  = s1[N-1:H];
  wire [N-H-1:0] qm_hi  = qmx[N-1:H];
  wire [N-H-1:0] s2_hi  = s1_hi ^ c1s_hi ^ qm_hi;
  wire [N-H-1:0] c2_hi  = (s1_hi & c1s_hi) | (s1_hi & qm_hi) | (c1s_hi & qm_hi);
  wire [N-H-1:0] S_hi_n = {1'b0, s2_hi[N-H-1:1]};
  wire [N-H-1:0] C_hi_n = {1'b0, c2_hi[N-H-2:0]};
  wire q_next = S[0] ^ C[0] ^ (a[0] & b[0]);
  wire q_load = a_in[0] & b_in[0];
  wire [WIDTH-1:0] a_n  = a >> 1;
  wire [WIDTH-1:0] bi_n = a[0] ? b : {WIDTH{1'b0}};
  integer k;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0;
      cb <= 0; qr <= 0; ph <= 8'h00;
    end else if (load) begin
      a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0; cb <= 0;
      bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      qr <= q_load; ph <= 8'h00;
    end else begin
      for (k = 0; k < 8; k = k + 1) ph[k] <= ~ph[k];
      if (!ph[0]) S[H-1:0] <= S_lo_n;
      if (!ph[1]) begin C[H-1:0] <= C_lo_n; cb <= c1[H-1]; end
      if (ph[2]) S[N-1:H] <= S_hi_n;
      if (ph[3]) C[N-1:H] <= C_hi_n;
      if (ph[4]) a[WL-1:0] <= a_n[WL-1:0];
      if (ph[7]) a[WIDTH-1:WL] <= a_n[WIDTH-1:WL];
      if (ph[5]) begin bi_r[WL-1:0] <= bi_n[WL-1:0]; qr <= q_next; end
      if (ph[6]) bi_r[WIDTH-1:WL] <= bi_n[WIDTH-1:WL];
    end
  end
endmodule
