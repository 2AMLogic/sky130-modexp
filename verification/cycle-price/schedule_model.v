// THROWAWAY schedule-only model of a Montgomery modexp control sequence. It
// has NO datapath: no operands, no arithmetic, no carry-save state. It exists
// only so a testbench can count clock edges from `start` to `done` for a
// stated schedule (DR-0017/0018). It is evidence for a cycle price, not RTL, and
// nothing in rtl/ instantiates it.
//
// K = clock cycles per Montgomery iteration:
//   K = 1  one-cycle-per-iteration carry-save kernel (the P4..P11c kernels)
//   K = 2  two pipelined column halves, serialized (low half, then high half)
//
// Schedule per Montgomery product (MP):
//   LOAD   1                  operand load
//   ITER   K * (WIDTH + 2)    WIDTH+2 iterations (R = 2^(WIDTH+2) > 4m, so
//                             in/out stay < 2m with no final subtraction)
//   CONV   ceil((WIDTH+2)/2)  carry-save -> binary, 2 bits per cycle
//   AFTER  1                  commit / dispatch
// Per modexp (left-to-right, same outer loop as rtl/modexp.v):
//   PRE_X   MP(base, R^2 mod m)   into the Montgomery domain
//   PRE_ACC MP(1,    R^2 mod m)   accumulator = R mod m
//   per exponent bit (WIDTH of them): SQ, then MUL iff the bit is set, + STEP 1
//   POST    MP(acc, 1)            out of the Montgomery domain
// R2_SOURCE selects the prefix before PRE_X. "caller" has R^2 at start.
// "double" splits each modular doubling across two edges. "kernel" uses
// the same split to seed 2R, then scans the public bits of WIDTH+2 with
// the ordinary MP states before one split reduction to a canonical residue.
module schedule_model #(
    parameter WIDTH = 16,
    parameter K     = 2,
    parameter R2_SOURCE = "caller"   // "caller", "double", or "kernel"
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [WIDTH-1:0] exp_in,
    output reg              done
);
  localparam N_IT = WIDTH + 2;
  localparam ITER = K * N_IT;
  localparam CONV = (WIDTH + 2 + 1) / 2;

  localparam [3:0] S_IDLE = 0, S_LOAD = 1, S_ITER = 2, S_CONV = 3,
                   S_AFTER = 4, S_STEP = 5, S_FINISH = 6,
                   S_REDUCE_LO = 7, S_REDUCE_HI = 8;
  localparam [2:0] P_PRE_X = 0, P_PRE_ACC = 1, P_SQ = 2, P_MUL = 3,
                   P_POST = 4, P_SEED_SQ = 5, P_SEED_MUL = 6;

  reg [3:0]       state;
  reg [2:0]       ph;
  reg [WIDTH-1:0] exp_r;
  integer         outer, cnt, seed_bit;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; ph <= P_PRE_X; exp_r <= 0; outer <= 0; cnt <= 0;
      seed_bit <= 0; done <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: if (start) begin
          exp_r <= exp_in; outer <= WIDTH; ph <= P_PRE_X;
          case (R2_SOURCE)
            "caller": state <= S_LOAD;
            "double": begin cnt <= 2*N_IT; state <= S_REDUCE_LO; end
            "kernel": begin
              cnt <= N_IT+1; state <= S_REDUCE_LO; ph <= P_SEED_SQ;
              seed_bit <= $clog2(N_IT+1) - 2;  // skip leading one of N_IT
            end
            default: $fatal(1, "Unknown R2_SOURCE %s", R2_SOURCE);
          endcase
        end
        S_REDUCE_LO: state <= S_REDUCE_HI;  // register low difference and borrow
        S_REDUCE_HI: begin                  // high difference and conditional select
          cnt <= cnt - 1;
          if (cnt == 1) state <= S_LOAD;
          else state <= S_REDUCE_LO;
        end
        S_LOAD: begin cnt <= ITER; state <= S_ITER; end
        S_ITER: begin
          cnt <= cnt - 1;
          if (cnt == 1) begin cnt <= CONV; state <= S_CONV; end
        end
        S_CONV: begin
          cnt <= cnt - 1;
          if (cnt == 1) state <= S_AFTER;
        end
        S_AFTER: case (ph)
          P_SEED_SQ, P_SEED_MUL: begin
            if (ph == P_SEED_SQ && N_IT[seed_bit]) begin
              ph <= P_SEED_MUL; state <= S_LOAD;
            end else if (seed_bit == 0) begin
              cnt <= 1; state <= S_REDUCE_LO; ph <= P_PRE_X;  // normalize [0,2m)
            end else begin
              seed_bit <= seed_bit - 1; ph <= P_SEED_SQ; state <= S_LOAD;
            end
          end
          P_PRE_X:   begin ph <= P_PRE_ACC; state <= S_LOAD; end
          P_PRE_ACC: begin ph <= P_SQ;      state <= S_LOAD; end
          P_SQ: if (exp_r[WIDTH-1]) begin ph <= P_MUL; state <= S_LOAD; end
                else state <= S_STEP;
          P_MUL:     state <= S_STEP;
          default:   state <= S_FINISH;      // P_POST
        endcase
        S_STEP: begin
          exp_r <= exp_r << 1;
          if (outer == 1) begin ph <= P_POST; state <= S_LOAD; end
          else begin outer <= outer - 1; ph <= P_SQ; state <= S_LOAD; end
        end
        S_FINISH: begin done <= 1'b1; state <= S_IDLE; end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
