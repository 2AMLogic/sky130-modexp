// P9 LOWER-BOUND PROBE (arithmetically WRONG on purpose): P7 with the next
// quotient replaced by a trivial function of flops, so only the carry-save
// datapath + registered-q fan-out remain on the critical path. It bounds what
// ANY quotient re-timing could achieve. Not a working kernel; no self-check.
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
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = ((S & C) | (S & bi) | (C & bi));
  wire [N-1:0] c1s = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1 ^ c1s ^ qmx;
  wire [N-1:0] c2 = ((s1 & c1s) | (s1 & qmx) | (c1s & qmx));
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  wire bi_n0 = a[0] & b[0];
  wire q_n = a[1] ^ b[1];
  wire q_l = a_in[0] & b_in[0];
  wire q_d = load ? q_l : q_n;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0;
      s_out <= 0; c_out <= 0;
      qc[0] <= 1'b0; qc[1] <= 1'b1; qc[3] <= 1'b1; qc[4] <= 1'b0;
    end else begin
      qc[0] <= q_d; qc[1] <= q_d; qc[3] <= ~q_d; qc[4] <= ~q_d;
      if (load) begin
        a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0;
        bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      end else begin
        a <= a >> 1;
        bi_r <= a[0] ? b : {WIDTH{1'b0}};
        S <= {1'b0, s2[N-1:1]};
        C <= {1'b0, c2s[N-1:1]};
        s_out <= S; c_out <= C;
      end
    end
  end
  always @(posedge clk) begin
    qc[2] <= q_d; qc[5] <= ~q_d;
  end
endmodule
