`timescale 1ns/1ps
module tb;
  parameter W=16, X=0;
  reg clk=0,rst_n=0,load=0; reg [W-1:0] a,b,m; wire [W+1:0] so,co;
  modexp #(.WIDTH(W)) d(.clk(clk),.rst_n(rst_n),.load(load),.a_in(a),.b_in(b),.m_in(m),.s_out(so),.c_out(co));
  always #5 clk=~clk;
  integer i,k,errs=0,seed=3,maxv=0; reg [63:0] tot,lhs,rhs; reg [31:0] rr;
  initial begin
    repeat(2)@(negedge clk); rst_n=1;
    for(i=0;i<2000;i=i+1) begin
      rr=$random(seed); m=(rr%((1<<(W-1))-1))*2+3; // odd, >=3
      rr=$random(seed); a=rr%m; rr=$random(seed); b=rr%m;
      @(negedge clk); load=1; @(negedge clk); load=0;
      repeat(W+X) @(negedge clk);
      @(negedge clk); // s_out/c_out lag one cycle
      tot=so+co; if(tot>maxv) maxv=tot;
      lhs=(tot*(64'd1<<W))%m; rhs=(a*b)%m;
      if(lhs!==rhs) begin errs=errs+1; if(errs<4) $display("BAD a=%0d b=%0d m=%0d tot=%0d",a,b,m,tot); end
      if(tot>=3*m) begin errs=errs+1; $display("RANGE tot=%0d m=%0d",tot,m); end
    end
    $display("K2 DONE W=%0d errs=%0d",W,errs); $finish;
  end
endmodule
