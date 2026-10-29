// P12 kernel: P8 (six non-mergeable q copies, shallow q recurrence, two
// chained 3:2 levels) with the q loop restructured per DR-0015 option 2.
// P8 computed q' = A ^ (q & ~m1), A = S1^C1^maj(S0,C0,bi0)^x_r, and then put
// the load mux behind it: q_d = load ? q_l : q_n. Here A does not depend on q,
// so both outcomes are formed first,
//   q=1: A ^ ~m1 (= ~(A ^ m1)),  q=0: A,
// each already merged with the load operand q_l, and q selects between the two
// with one mux2, the only gate on the q -> q loop. The inverted copies
// (qc[3..5]) get their own mux on inverted data, selected by an inverted copy,
// so the six flops are not all driven by one net.
// Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam K = 6;
  reg [WIDTH-1:0] a, b, m, bi_r;
  reg [N-1:0] S, C;
  reg [K-1:0] qc;                  // qc[0..2] = q, qc[3..5] = ~q
  wire [K-1:0] qv = {~qc[5:3], qc[2:0]};   // all six decoded to q polarity
  wire [N-1:0] bi = {2'b00, bi_r};
  wire [WIDTH-1:0] qm;
  genvar i;
  generate for (i = 0; i < WIDTH; i = i + 1) begin : qmask
    assign qm[i] = qv[(i * K) / WIDTH] & m[i];
  end endgenerate
  wire [N-1:0] qmx = {2'b00, qm};
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = ((S & C) | (S & bi) | (C & bi));
  wire [N-1:0] c1s = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1 ^ c1s ^ qmx;
  wire [N-1:0] c2 = ((s1 & c1s) | (s1 & qmx) | (c1s & qmx));
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  reg x_r;
  wire t2 = (S[0] & C[0]) | (S[0] & bi_r[0]) | (C[0] & bi_r[0]);
  wire x_l = (a_in[0] & b_in[1]) ^ (a_in[1] & b_in[0]);
  wire x_n = (a[0] & b[1]) ^ (a[1] & b[0]);
  wire q_l = a_in[0] & b_in[0];
  // q-independent part of the next quotient, and both q outcomes with the
  // load operand folded in
  wire qa    = (S[1] ^ C[1]) ^ t2 ^ x_r;
  wire d_q1  = load ? q_l : (qa ^ ~m[1]);
  wire d_q0  = load ? q_l : qa;
  wire q_d   = qv[0] ? d_q1 : d_q0;       // the only gate on the q loop
  wire qn_d  = qv[3] ? ~d_q1 : ~d_q0;     // same function, driven by ~q copy 3
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_r <= 0; a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0;
      s_out <= 0; c_out <= 0;
      qc[0] <= 1'b0; qc[1] <= 1'b1; qc[3] <= 1'b1; qc[4] <= 1'b0;
    end else begin
      qc[0] <= q_d; qc[1] <= q_d; qc[3] <= qn_d; qc[4] <= qn_d;
      if (load) begin
        x_r <= x_l; a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0;
        bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      end else begin
        x_r <= x_n; a <= a >> 1;
        bi_r <= a[0] ? b : {WIDTH{1'b0}};
        S <= {1'b0, s2[N-1:1]};
        C <= {1'b0, c2s[N-1:1]};
        s_out <= S; c_out <= C;
      end
    end
  end
  always @(posedge clk) begin
    qc[2] <= q_d; qc[5] <= qn_d;
  end
endmodule
