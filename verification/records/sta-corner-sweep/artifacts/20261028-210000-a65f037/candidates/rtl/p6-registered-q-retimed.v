// P6 kernel: P4 with the quotient bit q registered (q_r) and its next value
// computed during the current step from the same carry-save recurrence, so
// the q fan-out starts at a flop instead of after the S0^C0^bi0 reduction.
// Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  reg [WIDTH-1:0] a, b, m, bi_r;
  reg [N-1:0] S, C;
  reg q_r;
  wire [N-1:0] bi = {2'b00, bi_r};
  wire [N-1:0] qm = {2'b00, {WIDTH{q_r}} & m};
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = ((S & C) | (S & bi) | (C & bi));
  wire [N-1:0] c1s = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1 ^ c1s ^ qm;
  wire [N-1:0] c2 = ((s1 & c1s) | (s1 & qm) | (c1s & qm));
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  // next-step operand bit and next-step quotient
  wire bi_n0 = a[0] & b[0];
  wire q_n = s2[1] ^ c2s[1] ^ bi_n0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0; q_r <= 0;
      s_out <= 0; c_out <= 0;
    end else if (load) begin
      a <= a_in >> 1; b <= b_in; m <= m_in; S <= 0; C <= 0;
      bi_r <= a_in[0] ? b_in : {WIDTH{1'b0}};
      q_r <= a_in[0] & b_in[0];
    end else begin
      a <= a >> 1;
      bi_r <= a[0] ? b : {WIDTH{1'b0}};
      q_r <= q_n;
      S <= {1'b0, s2[N-1:1]};
      C <= {1'b0, c2s[N-1:1]};
      s_out <= S; c_out <= C;
    end
  end
endmodule
