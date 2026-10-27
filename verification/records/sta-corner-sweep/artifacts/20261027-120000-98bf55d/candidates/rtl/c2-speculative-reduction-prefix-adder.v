// RSA-style modular-exponentiation accelerator -- computes
//
//     result = base ** exp (mod modulus)
//
// via left-to-right square-and-multiply, where each modular multiply is an
// MSB-first interleaved (bit-serial "Blakley") modular multiplication that
// keeps the running partial product reduced with at most two conditional
// subtractions per bit. This is the textbook RSA modexp datapath -- a real
// modular multiplier reused across exponent bits -- and is the "GCD/RSA
// modular-exponentiation accelerator" class of design the Qwen3.8-Max post
// (2026-08-02) benchmarked, not the minimal subtract-based GCD in `gcd.v`.
//
// Precondition (standard RSA message constraint): `base_in < mod_in` and
// `mod_in > 1`. The randomized cocotb testbench (`test_modexp.py`) only ever
// drives operands in that range, and the design is bit-exact against Python's
// `pow(base, exp, mod)` there across WIDTH = 4/6/8/16.
//
// Handshake: assert `start` with base/exp/modulus valid for one cycle; `done`
// pulses high for one cycle when `result` is valid.
module modexp #(
    parameter WIDTH = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [WIDTH-1:0] base_in,
    input  wire [WIDTH-1:0] exp_in,
    input  wire [WIDTH-1:0] mod_in,
    output reg              done,
    output reg  [WIDTH-1:0] result
);

  // Counter width sufficient to hold WIDTH..1 (WIDTH up to 16 -> 5 bits, but
  // keep it general for larger WIDTH configs).
  localparam CW = (WIDTH <= 2)   ? 2 :
                  (WIDTH <= 4)   ? 3 :
                  (WIDTH <= 8)   ? 4 :
                  (WIDTH <= 16)  ? 5 :
                  (WIDTH <= 32)  ? 6 :
                  (WIDTH <= 64)  ? 7 : 8;

  localparam [2:0] S_IDLE    = 3'd0,
                   S_MM_LOAD = 3'd1,
                   S_MM_RUN  = 3'd2,
                   S_AFTER   = 3'd3,
                   S_STEP    = 3'd4,
                   S_FINISH  = 3'd5;

  localparam MM_SQUARE = 1'b0,
             MM_MUL     = 1'b1;

  reg [2:0]        state;
  reg              mm_phase;      // which modular multiply is running

  // Operand / accumulator registers.
  reg [WIDTH-1:0]  base_r;        // constant base for the whole exponentiation
  reg [WIDTH-1:0]  exp_r;         // exponent, shifted left one bit per step
  reg [WIDTH-1:0]  mod_r;         // modulus
  reg [CW-1:0]     outer;         // exponent bits still to process (WIDTH..1)

  // Interleaved modular-multiply working registers.
  reg [WIDTH-1:0]  mm_a;          // multiplier operand, MSB-first scanned
  reg [WIDTH-1:0]  mm_b;          // multiplicand operand (added when a-bit set)
  reg [WIDTH-1:0]  mm_p;          // running partial product, always < mod_r
  reg [CW-1:0]     j;             // inner bit counter (WIDTH..1)

  // One interleaved step: p <- 2*p + (a_msb ? b : 0), then reduce mod m with
  // up to two conditional subtractions. Widened to WIDTH+2 bits: 2*p < 2m and
  // +b < m gives a pre-reduction sum < 3m < 3*2^WIDTH.
  wire [WIDTH+1:0] mm_p2  = {mm_p, 1'b0};
  wire [WIDTH+1:0] mm_add = mm_a[WIDTH-1] ? {2'b00, mm_b} : {(WIDTH+2){1'b0}};
  // Candidate 1: speculative parallel reduction. sum, sum-m and sum-2m are
  // each formed directly from (2p, addend, -m / -2m) through one 3:2 layer
  // and one carry-propagate adder, all in parallel; the two sign bits then
  // pick the result. No adder output feeds a comparator or another adder.
  localparam SW = WIDTH + 3;  // signed working width
  // Kogge-Stone parallel-prefix adder: sum = a + b + cin over SW bits.
  function [SW-1:0] ks_add(input [SW-1:0] a, input [SW-1:0] b, input cin);
    reg [SW-1:0] g, p, gg, pp, gn, pn;
    integer lvl, i, d;
    begin
      g = a & b; p = a ^ b;
      gg = g; pp = p;
      gg[0] = g[0] | (p[0] & cin);
      d = 1;
      for (lvl = 0; lvl < 6; lvl = lvl + 1) begin
        if (d < SW) begin
          gn = gg; pn = pp;
          for (i = 0; i < SW; i = i + 1) begin
            if (i >= d) begin
              gn[i] = gg[i] | (pp[i] & gg[i-d]);
              pn[i] = pp[i] & pp[i-d];
            end
          end
          gg = gn; pp = pn;
        end
        d = d * 2;
      end
      ks_add = p ^ {gg[SW-2:0], cin};
    end
  endfunction

  wire [SW-1:0] x  = {1'b0, mm_p, 1'b0};
  wire [SW-1:0] y  = mm_a[WIDTH-1] ? {3'b000, mm_b} : {SW{1'b0}};
  wire [SW-1:0] nm1 = ~{3'b000, mod_r};
  wire [SW-1:0] nm2 = ~{2'b00, mod_r, 1'b0};
  wire [SW-1:0] xy_s = x ^ y;
  wire [SW-1:0] xy_c = x & y;
  // s0 = x + y
  wire [SW-1:0] s0 = ks_add(x, y, 1'b0);
  // s1 = x + y - m  = x + y + ~m + 1  (3:2 compress, then add with carry-in)
  wire [SW-1:0] c1s = xy_s ^ nm1;
  wire [SW-1:0] c1c = (xy_s & nm1) | xy_c;
  wire [SW-1:0] s1  = ks_add(c1s, {c1c[SW-2:0], 1'b0}, 1'b1);
  wire [SW-1:0] c2s = xy_s ^ nm2;
  wire [SW-1:0] c2c = (xy_s & nm2) | xy_c;
  wire [SW-1:0] s2  = ks_add(c2s, {c2c[SW-2:0], 1'b0}, 1'b1);
  wire [WIDTH+1:0] mm_red = !s2[SW-1] ? s2[WIDTH+1:0]
                          : !s1[SW-1] ? s1[WIDTH+1:0]
                          :             s0[WIDTH+1:0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= S_IDLE;
      done     <= 1'b0;
      result   <= {WIDTH{1'b0}};
      mm_phase <= MM_SQUARE;
      base_r   <= {WIDTH{1'b0}};
      exp_r    <= {WIDTH{1'b0}};
      mod_r    <= {WIDTH{1'b0}};
      outer    <= {CW{1'b0}};
      mm_a     <= {WIDTH{1'b0}};
      mm_b     <= {WIDTH{1'b0}};
      mm_p     <= {WIDTH{1'b0}};
      j        <= {CW{1'b0}};
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          if (start) begin
            base_r   <= base_in;
            exp_r    <= exp_in;
            mod_r    <= mod_in;
            // result starts at 1 (== 1 mod m for m > 1); base**0 == 1.
            result   <= {{(WIDTH-1){1'b0}}, 1'b1};
            outer    <= WIDTH[CW-1:0];
            mm_phase <= MM_SQUARE;
            state    <= S_MM_LOAD;
          end
        end

        // Load the interleaved multiplier with the operands for this phase.
        // SQUARE: result*result. MUL: result*base. `result` already holds the
        // squared value by the time a MUL is loaded (see S_AFTER).
        S_MM_LOAD: begin
          mm_p <= {WIDTH{1'b0}};
          mm_a <= result;
          mm_b <= (mm_phase == MM_SQUARE) ? result : base_r;
          j    <= WIDTH[CW-1:0];
          state <= S_MM_RUN;
        end

        S_MM_RUN: begin
          mm_p <= mm_red[WIDTH-1:0];
          mm_a <= mm_a << 1;
          if (j == {{(CW-1){1'b0}}, 1'b1}) begin
            state <= S_AFTER;
          end else begin
            j <= j - 1'b1;
          end
        end

        // The modular multiply just finished; commit it to `result`.
        S_AFTER: begin
          result <= mm_p;
          if (mm_phase == MM_SQUARE) begin
            if (exp_r[WIDTH-1]) begin
              // exponent bit set: follow the square with a multiply by base.
              mm_phase <= MM_MUL;
              state    <= S_MM_LOAD;
            end else begin
              state <= S_STEP;
            end
          end else begin
            state <= S_STEP;
          end
        end

        // Advance to the next (lower) exponent bit.
        S_STEP: begin
          exp_r <= exp_r << 1;
          if (outer == {{(CW-1){1'b0}}, 1'b1}) begin
            state <= S_FINISH;
          end else begin
            outer    <= outer - 1'b1;
            mm_phase <= MM_SQUARE;
            state    <= S_MM_LOAD;
          end
        end

        S_FINISH: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
