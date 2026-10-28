// P4 kernel: P1 with (a) the operand AND a0*b pre-registered (bi_r holds the
// next cycle's a0*b) and (b) the quotient bit q replicated per column group,
// each copy kept so synthesis cannot merge them (fan-out limited).
// Timing-probe interface (not the modexp handshake).
module modexp #(parameter WIDTH = 16) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] a_in, b_in, m_in,
    output reg  [WIDTH+1:0] s_out, c_out
);
  localparam N = WIDTH + 2;
  localparam G = 4;                       // columns per q copy
  localparam NQ = (N + G - 1) / G;
  reg [WIDTH-1:0] a, b, m, bi_r;
  reg [N-1:0] S, C;
  (* keep *) wire [NQ-1:0] q;
  genvar g;
  generate for (g = 0; g < NQ; g = g + 1) begin : qcopy
    (* keep *) wire qq = S[0] ^ C[0] ^ bi_r[0];
    assign q[g] = qq;
  end endgenerate
  wire [N-1:0] bi = {2'b00, bi_r};
  wire [N-1:0] qm;
  genvar i;
  generate for (i = 0; i < N; i = i + 1) begin : qmask
    assign qm[i] = (i < WIDTH) ? (q[i / G] & m[i]) : 1'b0;
  end endgenerate
  wire [N-1:0] s1 = S ^ C ^ bi;
  wire [N-1:0] c1 = ((S & C) | (S & bi) | (C & bi));
  wire [N-1:0] c1s = {c1[N-2:0], 1'b0};
  wire [N-1:0] s2 = s1 ^ c1s ^ qm;
  wire [N-1:0] c2 = ((s1 & c1s) | (s1 & qm) | (c1s & qm));
  wire [N-1:0] c2s = {c2[N-2:0], 1'b0};
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a <= 0; b <= 0; m <= 0; bi_r <= 0; S <= 0; C <= 0; s_out <= 0; c_out <= 0;
    end else if (load) begin
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
endmodule
