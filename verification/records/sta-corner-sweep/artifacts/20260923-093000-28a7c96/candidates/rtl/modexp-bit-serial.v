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
//
// ---------------------------------------------------------------------------
// Inner-datapath structure (issue #132 / DR-0004): bit-serial Blakley step.
// ---------------------------------------------------------------------------
// The pre-#132 core computed each Blakley step combinationally in one cycle:
//   mm_sum = 2*mm_p + (a_msb ? mm_b : 0)          -- (WIDTH+2)-bit add
//   mm_p   = (mm_sum >= 2m) ? mm_sum - 2m
//          : (mm_sum >= m)   ? mm_sum - m : mm_sum -- two serial compares
// That single-cycle chain (18-bit add + two conditional subtracts) is the
// 42.17 ns critical path at ss_n40C_1v28 (arrival vs 8.31 ns required) that
// capped the all-corner Fmax at 22.80 MHz; splitting it any fixed number of
// ways leaves >= 1 full adder depth per cycle, which cannot fit the ~4.8 ns
// combinational budget 100 MHz allows at 1.28 V / -40 C in sky130_fd_sc_hd.
//
// This version keeps the algorithm and the interface bit-identical but
// serializes each Blakley step LSB-first across 2*WIDTH+6 cycles of
// one-gate-deep slices, so every cycle carries at most one full-adder /
// full-subtractor slice of logic:
//
//   S_STEP_INIT (1 cycle)   parallel-load the step's operand slices:
//                           ab_sr = a_msb ? b : 0 (the masked addend),
//                           m1_sr = m, m2_sr = m<<1, carry/borrows cleared.
//   S_P1      (WIDTH+2)     serial full adder: s = 2*p + ab, one bit per
//                           cycle, carry registered; ~s is shifted LSB-first
//                           into s_buf.
//   S_P2      (WIDTH+2)     two independent serial subtractions in parallel:
//                           d2 = s - 2m and d1 = s - m, borrows registered,
//                           difference bits shifted into d2_buf / d1_buf and
//                           ~s passed through into s2_buf.
//   S_SEL     (1 cycle)     the final borrow flags decide the reduction:
//                           p <= (s >= 2m) ? d2 : (s >= m) ? d1 : s.
//
// The arithmetic is unchanged -- red(s) = s - k*m with k = floor(s/m) in
// {0,1,2}, exactly the original mm_red -- so the core stays bit-exact against
// pow(base, exp, mod); only the cycle count per Blakley step changes (see
// DR-0004 for the re-derived latency formula and its measured cross-check).
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

  // Counter width sufficient to hold WIDTH..1 and WIDTH+2 (WIDTH up to 16
  // needs to count to 18 -> 5 bits; keep it general for larger WIDTH).
  localparam CW = (WIDTH <= 2)   ? 2 :
                  (WIDTH <= 4)   ? 3 :
                  (WIDTH <= 8)   ? 4 :
                  (WIDTH <= 16)  ? 5 :
                  (WIDTH <= 32)  ? 6 :
                  (WIDTH <= 64)  ? 7 : 8;

  localparam [3:0] S_IDLE      = 4'd0,
                   S_MM_LOAD   = 4'd1,
                   S_STEP_INIT = 4'd2,
                   S_P1        = 4'd3,
                   S_P2        = 4'd4,
                   S_SEL       = 4'd5,
                   S_AFTER     = 4'd6,
                   S_STEP      = 4'd7,
                   S_FINISH    = 4'd8;

  localparam MM_SQUARE = 1'b0,
              MM_MUL    = 1'b1;

  // Serial-pass length, as a CW-wide constant (the same sizing idiom the
  // original core used for WIDTH itself).
  localparam integer FULL = WIDTH + 2;
  localparam [CW-1:0] FULL_COUNT = FULL[CW-1:0];

  reg [3:0]        state;
  reg              mm_phase;      // which modular multiply is running

  // Operand / accumulator registers.
  reg [WIDTH-1:0]  base_r;        // constant base for the whole exponentiation
  reg [WIDTH-1:0]  exp_r;         // exponent, shifted left one bit per step
  reg [WIDTH-1:0]  mod_r;         // modulus
  reg [CW-1:0]     outer;         // exponent bits still to process (WIDTH..1)

  // Interleaved modular-multiply working registers.
  reg [WIDTH-1:0]  mm_a;          // multiplier operand, MSB-first scanned
  reg [WIDTH-1:0]  mm_b;          // multiplicand operand (added when a-bit set)
  reg [CW-1:0]     j;             // inner step counter (WIDTH..1)
  reg [CW-1:0]     i;             // serial bit counter ((WIDTH+2)..1)

  // Bit-slice shift registers (LSB-first streams; destructively consumed
  // where the value is dead after the pass, parallel-loaded elsewhere).
  reg [WIDTH-1:0]  p_sr;          // running partial product, always < mod_r
  reg [WIDTH-1:0]  ab_sr;         // this step's masked addend (a_msb ? b : 0)
  reg [WIDTH+1:0]  m1_sr;         // mod_r,        zero-extended to WIDTH+2
  reg [WIDTH+1:0]  m2_sr;         // mod_r << 1,   zero-extended to WIDTH+2
  reg [WIDTH+1:0]  s_buf;         // ~s,   shifted in during S_P1
  reg [WIDTH+1:0]  s2_buf;        // ~s,   passed through during S_P2
  reg [WIDTH+1:0]  d1_buf;        // s - m,   shifted in during S_P2
  reg [WIDTH+1:0]  d2_buf;        // s - 2*m, shifted in during S_P2
  reg               c;            // serial-adder carry
  reg               p_d;          // one-slice delay flop: serializes 2*p as
                                 // a leading zero followed by p's bits
  reg               b1, b2;       // serial-subtractor borrows (s-m, s-2m)

  // S_P1 slice: one full-adder bit of s = 2*p + ab.
  wire fa_x    = p_d;
  wire fa_y    = ab_sr[0];
  wire sum_t   = fa_x ^ fa_y ^ c;                     // s bit (true form)
  wire carry_n = (fa_x & fa_y) | (fa_x & c) | (fa_y & c);

  // S_P2 slice: one bit each of d2 = s - 2m and d1 = s - m. s_buf[0] carries
  // ~s, so the borrow maj3 reads it directly and each xor yields the true
  // difference bit (~s ^ m ^ b == s ^ m ^ b).
  wire nsb  = s_buf[0];
  wire m1b  = m1_sr[0];
  wire m2b  = m2_sr[0];
  // Note: ~s ^ m ^ b == ~(s ^ m ^ b), so each xor-of-~s needs its own
  // inversion to yield the true difference bit.
  wire d1_t = ~(nsb ^ m1b ^ b1);
  wire d2_t = ~(nsb ^ m2b ^ b2);
  wire nb1  = (nsb & m1b) | (nsb & b1) | (m1b & b1);  // borrow, s - m
  wire nb2  = (nsb & m2b) | (nsb & b2) | (m2b & b2);  // borrow, s - 2m

  // S_SEL reduction: no final borrow <=> subtrahend fit, exactly the original
  // (mm_sum >= mm_m2) ? ... : (mm_sum >= mm_m1) ? ... : mm_sum. The reduced
  // value is always < mod_r < 2**WIDTH, so the low WIDTH bits suffice.
  wire [WIDTH-1:0] p_next = (~b2) ? d2_buf[WIDTH-1:0]
                        : (~b1) ? d1_buf[WIDTH-1:0]
                        :         ~s2_buf[WIDTH-1:0];

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
      j        <= {CW{1'b0}};
      i        <= {CW{1'b0}};
      p_sr     <= {WIDTH{1'b0}};
      ab_sr    <= {WIDTH{1'b0}};
      m1_sr    <= {(WIDTH+2){1'b0}};
      m2_sr    <= {(WIDTH+2){1'b0}};
      s_buf    <= {(WIDTH+2){1'b0}};
      s2_buf   <= {(WIDTH+2){1'b0}};
      d1_buf   <= {(WIDTH+2){1'b0}};
      d2_buf   <= {(WIDTH+2){1'b0}};
      c        <= 1'b0;
      p_d      <= 1'b0;
      b1       <= 1'b0;
      b2       <= 1'b0;
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
          p_sr    <= {WIDTH{1'b0}};
          mm_a    <= result;
          mm_b    <= (mm_phase == MM_SQUARE) ? result : base_r;
          j       <= WIDTH[CW-1:0];
          state   <= S_STEP_INIT;
        end

        // Parallel-load this step's operand slices. mm_a's MSB selects the
        // addend for the whole step (it is constant across the step's
        // slices), so the a-bit AND is folded into the load, not the slice.
        // p_d is cleared so the p stream enters the adder one slice late
        // (a leading zero then p's bits LSB-first) -- the serial form of
        // the original core's mm_p2 = {mm_p, 1'b0}: s = 2*p + ab.
        S_STEP_INIT: begin
          ab_sr <= mm_a[WIDTH-1] ? mm_b : {WIDTH{1'b0}};
          m1_sr <= {2'b00, mod_r};
          m2_sr <= {1'b0, mod_r, 1'b0};
          p_d   <= 1'b0;
          c     <= 1'b0;
          b1    <= 1'b0;
          b2    <= 1'b0;
          i     <= FULL_COUNT;
          state <= S_P1;
        end

        // Serial add: s = 2*p + ab, LSB-first, one full-adder slice per
        // cycle. p_sr and ab_sr are consumed destructively (they shift in
        // zeroes, which is exactly the zero extension of 2*p + ab above the
        // WIDTH boundary); ~s accumulates LSB-first into s_buf.
        S_P1: begin
          s_buf <= {~sum_t, s_buf[WIDTH+1:1]};
          p_d   <= p_sr[0];
          p_sr  <= {1'b0, p_sr[WIDTH-1:1]};
          ab_sr <= {1'b0, ab_sr[WIDTH-1:1]};
          c     <= carry_n;
          if (i == {{(CW-1){1'b0}}, 1'b1}) begin
            i     <= FULL_COUNT;
            state <= S_P2;
          end else begin
            i <= i - 1'b1;
          end
        end

        // Serial dual subtract: d2 = s - 2m and d1 = s - m, LSB-first,
        // one full-subtractor slice each per cycle. The final borrow flags
        // (available when the MSB slice completes) decide the reduction.
        S_P2: begin
          d2_buf <= {d2_t, d2_buf[WIDTH+1:1]};
          d1_buf <= {d1_t, d1_buf[WIDTH+1:1]};
          s2_buf <= {nsb,  s2_buf[WIDTH+1:1]};
          s_buf  <= {1'b0, s_buf[WIDTH+1:1]};
          m1_sr  <= {1'b0, m1_sr[WIDTH+1:1]};
          m2_sr  <= {1'b0, m2_sr[WIDTH+1:1]};
          b1     <= nb1;
          b2     <= nb2;
          if (i == {{(CW-1){1'b0}}, 1'b1}) begin
            state <= S_SEL;
          end else begin
            i <= i - 1'b1;
          end
        end

        // Commit the reduced partial product and advance the step counter.
        S_SEL: begin
          p_sr  <= p_next;
          mm_a  <= mm_a << 1;
          if (j == {{(CW-1){1'b0}}, 1'b1}) begin
            state <= S_AFTER;
          end else begin
            j     <= j - 1'b1;
            state <= S_STEP_INIT;
          end
        end

        // The modular multiply just finished; commit it to `result`.
        S_AFTER: begin
          result <= p_sr;
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
