// Candidate 3 kernel: radix-2 Montgomery, carry-save, 4:2 split into two
// pipeline stages (one 3:2 layer per cycle). Single lane => 2 cycles/step;
// timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  reg [WIDTH-1:0] a, b, m;
  reg [N-1:0] S, C;       // architectural carry-save state
  reg [N-1:0] s1r, c1r;   // stage-1 result (first 3:2 layer)
  reg [N-1:0] qmr;        // registered q*m
  reg         ph;
  wire ai = a[0];
  wire q  = S[0] ^ C[0] ^ (ai & b[0]);
  wire [N-1:0] bi = ai ? {2'b00, b} : {N{1'b0}};
  // stage 0: first 3:2 layer over (S, C, a0*b)
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = (S & C) | (S & bi) | (C & bi);
  // stage 1: second 3:2 layer over (s1, c1<<1, q*m), then shift right 1
  wire [N-1:0] c1s = {c1r[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1r ^ c1s ^ qmr;
  wire [N-1:0] c2 = (s1r & c1s) | (s1r & qmr) | (c1s & qmr);
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; S <= 0; C <= 0; s1r <= 0; c1r <= 0; qmr <= 0;
      ph <= 0; s_out <= 0; c_out <= 0;
    end else if (load) begin
      a <= a_in; b <= b_in; m <= m_in; S <= 0; C <= 0; ph <= 0;
    end else if (!ph) begin
      s1r <= s1; c1r <= c1;
      qmr <= q ? {2'b00, m} : {N{1'b0}};
      ph  <= 1'b1;
    end else begin
      S <= {1'b0, s2[N-1:1]};
      C <= {1'b0, c2s[N-1:1]};
      a <= a >> 1;
      ph <= 1'b0;
      s_out <= {1'b0, s2[N-1:1]}; c_out <= {1'b0, c2s[N-1:1]};
    end
  end
endmodule
