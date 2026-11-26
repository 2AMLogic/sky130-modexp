`timescale 1ns/1ps
// Self-check for the two-clock-per-iteration kernel: R = 2^(W+2); for each
// product run W+2 complete low/high pairs, sample the settled S/C, require
// (T*R) mod m == (a*b) mod m and 0 <= T < 2m. Counts q=1/q=0 iterations and
// iterations where the boundary carry cb is set (carries across the cut).
module tb;
  parameter W=16, NC=2000, SEED=3;
  localparam N = W+2;
  reg clk=0,rst_n=0,load=0; reg [W-1:0] a,b,m; wire [W+1:0] so,co;
  modexp #(.WIDTH(W)) d(.clk(clk),.rst_n(rst_n),.load(load),.a_in(a),.b_in(b),.m_in(m),.s_out(so),.c_out(co));
  always #5 clk=~clk;
  integer i,k,errs=0,seed=SEED,q1=0,q0=0,cbhi=0,cb0=0; reg [63:0] tot,lhs,rhs; reg [31:0] rr;
  initial begin
    repeat(2)@(negedge clk); rst_n=1;
    for(i=0;i<NC;i=i+1) begin
      rr=$random(seed); m=(rr%((1<<(W-1))-1))*2+3; // odd, >=3
      rr=$random(seed); a=rr%m; rr=$random(seed); b=rr%m;
      @(negedge clk); load=1; @(negedge clk); load=0;
      for(k=0;k<N;k=k+1) begin
        if(d.qr) q1=q1+1; else q0=q0+1;
        @(negedge clk);                       // low clock done
        if(d.cb) cbhi=cbhi+1; else cb0=cb0+1;
        @(negedge clk);                       // high clock done
      end
      tot=so+co;
      lhs=(tot*(64'd1<<N))%m; rhs=(a*b)%m;
      if(lhs!==rhs) begin errs=errs+1; if(errs<4) $display("BAD a=%0d b=%0d m=%0d tot=%0d",a,b,m,tot); end
      if(tot>=2*m) begin errs=errs+1; if(errs<4) $display("RANGE tot=%0d m=%0d",tot,m); end
    end
    $display("P13 DONE W=%0d seed=%0d cases=%0d errs=%0d q1=%0d q0=%0d cb_set=%0d cb_clear=%0d",W,SEED,NC,errs,q1,q0,cbhi,cb0); $finish;
  end
endmodule
