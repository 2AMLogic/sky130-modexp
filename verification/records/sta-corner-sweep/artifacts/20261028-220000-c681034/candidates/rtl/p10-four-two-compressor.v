// P10 kernel: P8 with the two chained 3:2 levels replaced by a 4:2 compressor
// per column (xor2 tree + horizontal cout/cin), same q recurrence and q copies.
// P8 kernel: P7 with the next-quotient recurrence rewritten as a shallow XOR
// of flop outputs (odd modulus: next carry bit 0 equals the current q), and
// the operand-bit terms pre-registered one cycle ahead (x_r).
// P7 kernel: P6 (registered, re-timed quotient) with the registered quotient
// held in six flops that the flow cannot merge, because they differ in what
// opt_merge compares: polarity (q vs ~q) x flop kind (async-reset-0,
// async-set-1, no reset). Each copy drives a contiguous column group, so the
// fan-out per flop is ~WIDTH/6 instead of WIDTH. Reset values of the copies
// are irrelevant: load always initialises all six before use.
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
  // 4:2 compressor per column (inputs S, C, bi, qm + horizontal cin):
  //   cout = maj(S, C, bi)           (independent of cin)
  //   t    = (S ^ C) ^ (bi ^ qm)     (xor2 tree, no xor3)
  //   sum  = t ^ cin;  carry = t ? cin : qm
  // sum has weight j, carry weight j+1; cout feeds column j+1 as cin.
  wire [N-1:0] cout = (S & C) | (S & bi) | (C & bi);
  wire [N-1:0] cin  = {cout[N-2:0], 1'b0};
  wire [N-1:0] ta = S ^ C;
  wire [N-1:0] tb = bi ^ qmx;
  wire [N-1:0] t  = ta ^ tb;
  wire [N-1:0] s2 = t ^ cin;
  wire [N-1:0] c2 = (t & cin) | (~t & qmx);
  // q' = s2[1]^c2[0]^bi'[0]; with m[0]=1, c2[0]=q, so
  // q' = (S1^C1) ^ maj(S0,C0,bi0) ^ (q & ~m1) ^ x_r, x_r = bi[1]^bi'[0].
  reg x_r;
  wire t2 = (S[0] & C[0]) | (S[0] & bi_r[0]) | (C[0] & bi_r[0]);
  wire q_n = (S[1] ^ C[1]) ^ (t2 ^ (qv[0] & ~m[1])) ^ x_r;
  wire x_l = (a_in[0] & b_in[1]) ^ (a_in[1] & b_in[0]);
  wire x_n = (a[0] & b[1]) ^ (a[1] & b[0]);
  wire q_l = a_in[0] & b_in[0];
  wire q_d = load ? q_l : q_n;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_r <= 0; a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0;
      s_out <= 0; c_out <= 0;
      qc[0] <= 1'b0; qc[1] <= 1'b1; qc[3] <= 1'b1; qc[4] <= 1'b0;
    end else begin
      qc[0] <= q_d; qc[1] <= q_d; qc[3] <= ~q_d; qc[4] <= ~q_d;
      if (load) begin
        x_r <= x_l; a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0;
        bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      end else begin
        x_r <= x_n; a <= a >> 1;
        bi_r <= a[0] ? b : {WIDTH{1'b0}};
        S <= {1'b0, s2[N-1:1]};
        C <= {1'b0, c2[N-2:0]};
        s_out <= S; c_out <= C;
      end
    end
  end
  always @(posedge clk) begin
    qc[2] <= q_d; qc[5] <= ~q_d;
  end
endmodule
