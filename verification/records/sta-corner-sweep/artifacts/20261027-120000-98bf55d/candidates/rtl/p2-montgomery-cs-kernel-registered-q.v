// Candidate 2 kernel: radix-2 Montgomery multiply in carry-save form.
// One step per cycle: (S,C) <- (S + C + a0*b + q*m) / 2, q = parity of the
// low column. Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  reg [WIDTH-1:0] a, b, m;
  reg [WIDTH+1:0] S, C;
  reg q_r;
  localparam N = WIDTH + 2;
  wire ai = a[0];
  wire q  = q_r;
  wire [N-1:0] bi = ai ? {2'b00, b} : {N{1'b0}};
  wire [N-1:0] qm = q  ? {2'b00, m} : {N{1'b0}};
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = ((S & C) | (S & bi) | (C & bi));
  wire [N-1:0] c1s = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1 ^ c1s ^ qm;
  wire [N-1:0] c2 = ((s1 & c1s) | (s1 & qm) | (c1s & qm));
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_r <= 0; a <= 0; b <= 0; m <= 0; S <= 0; C <= 0; s_out <= 0; c_out <= 0;
    end else if (load) begin
      a <= a_in; b <= b_in; m <= m_in; S <= 0; C <= 0; q_r <= a_in[0] & b_in[0];
    end else begin
      a <= a >> 1;
      q_r <= s2[1] ^ c2s[1] ^ (a[1] & b[0]);
      S <= {1'b0, s2[N-1:1]};
      C <= {1'b0, c2s[N-1:1]};
      s_out <= S; c_out <= C;
    end
  end
endmodule
