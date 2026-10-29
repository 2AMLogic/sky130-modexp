// Cycle-counting testbench for issue #280. For each WIDTH and a set of exp_in
// values it counts clock edges from the edge at which `start` is sampled to
// the edge at which `done` pulses (the counting convention of record 0001
// Decision 3) on three DUTs started on the same edge:
//   ship  rtl/modexp.v, the shipped design   -> checked against the RATIFIED
//         record-0001 formula, which calibrates this counting method
//   m1    schedule_model K=1
//   h2    schedule_model K=2
// Expected values come from closed-form formulas written independently of the
// FSMs. Prints one `ROW` line per case; ends with `RESULT: PASS|FAIL`.
`timescale 1ns/1ps
module cycle_price_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  integer fails = 0;

  // One instance of the harness per WIDTH.
  genvar gi;
  generate for (gi = 0; gi < 4; gi = gi + 1) begin : g
    localparam W = (gi == 0) ? 4 : (gi == 1) ? 6 : (gi == 2) ? 8 : 16;
    reg              start = 0;
    reg  [W-1:0]     exp_v = 0;
    wire             d_ship, d_m1, d_h2;
    wire [W-1:0]     res;
    modexp #(.WIDTH(W)) ship (.clk(clk), .rst_n(rst_n), .start(start),
        .base_in({{(W-2){1'b0}}, 2'b10}), .exp_in(exp_v),
        .mod_in({W{1'b1}}), .done(d_ship), .result(res));
    schedule_model #(.WIDTH(W), .K(1)) m1 (.clk(clk), .rst_n(rst_n),
        .start(start), .exp_in(exp_v), .done(d_m1));
    schedule_model #(.WIDTH(W), .K(2)) h2 (.clk(clk), .rst_n(rst_n),
        .start(start), .exp_in(exp_v), .done(d_h2));

    reg finished = 0;
    integer idx = 0;                       // posedge counter
    integer e0, c_ship, c_m1, c_h2;
    always @(posedge clk) begin
      idx <= idx + 1;
      // `done` read here is the value registered at the previous edge, so
      // the edge at which done pulsed is idx-1 and the start edge is e0.
      // The offset is calibrated on `ship`: the ratified record-0001 formula
      // must be reproduced exactly by the shipped RTL for the count to be
      // trusted; the models then use the identical convention.
      if (d_ship && c_ship < 0) c_ship = idx - e0;
      if (d_m1   && c_m1   < 0) c_m1   = idx - e0;
      if (d_h2   && c_h2   < 0) c_h2   = idx - e0;
    end

    function integer pop;
      input [W-1:0] v;
      integer i;
      begin pop = 0; for (i = 0; i < W; i = i + 1) pop = pop + v[i]; end
    endfunction
    function integer f_ship;               // record 0001, Decision 3
      input integer p;
      begin f_ship = W*(W+3) + p*(W+2) + 2; end
    endfunction
    function integer f_mont;               // schedule in schedule_model.v
      input integer p;
      input integer k;
      integer mp;
      begin
        mp = 2 + k*(W+2) + (W+2+1)/2;
        f_mont = 2 + 3*mp + W*(mp+1) + p*mp;
      end
    endfunction

    task one;
      input [W-1:0] e;
      integer p;
      begin
        p = pop(e);
        // return to idle on all three before the next case
        @(negedge clk);
        exp_v = e; start = 1;
        c_ship = -1; c_m1 = -1; c_h2 = -1;
        e0 = idx;                           // start is sampled at the next posedge
        @(negedge clk); start = 0;
        wait (c_ship >= 0 && c_m1 >= 0 && c_h2 >= 0);
        repeat (3) @(negedge clk);
        $display("ROW W=%0d exp=%0d popcount=%0d ship=%0d (0001 formula %0d) K1=%0d (formula %0d) K2=%0d (formula %0d)",
                 W, e, p, c_ship, f_ship(p), c_m1, f_mont(p,1), c_h2, f_mont(p,2));
        if (c_ship != f_ship(p) || c_m1 != f_mont(p,1) || c_h2 != f_mont(p,2))
          fails = fails + 1;
      end
    endtask

    initial begin : seq
      reg [W-1:0] alt;
      integer i;
      alt = 0; for (i = 0; i < W; i = i + 2) alt[i] = 1'b1;
      wait (rst_n === 1'b1);
      repeat (2) @(negedge clk);
      one({W{1'b0}});                       // lower bound: popcount 0
      one({W{1'b1}});                       // upper bound: popcount W
      one(alt);
      one({{(W-1){1'b0}}, 1'b1});
      one({1'b1, {(W-1){1'b0}}});
      one({1'b0, {(W-1){1'b1}}});
      finished = 1;
    end
  end endgenerate

  initial begin
    #1 rst_n = 0;
    #50 rst_n = 1;
    wait (g[0].finished && g[1].finished && g[2].finished && g[3].finished);
    #100;
    $display("RESULT: %s (%0d mismatching rows)", fails == 0 ? "PASS" : "FAIL", fails);
    $finish;
  end
  initial begin #20000000; $display("RESULT: FAIL (timeout)"); $finish; end
endmodule
