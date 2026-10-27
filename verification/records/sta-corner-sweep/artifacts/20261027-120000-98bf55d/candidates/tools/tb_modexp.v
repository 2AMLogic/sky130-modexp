`timescale 1ns/1ps
module tb;
  parameter WIDTH = 16;
  parameter N = 300;
  reg clk=0, rst_n=0, start=0;
  reg [WIDTH-1:0] b,e,m; wire done; wire [WIDTH-1:0] r;
  modexp #(.WIDTH(WIDTH)) dut(.clk(clk),.rst_n(rst_n),.start(start),.base_in(b),.exp_in(e),.mod_in(m),.done(done),.result(r));
  always #5 clk=~clk;
  integer i, errs=0, cyc, seed=7;
  reg [WIDTH-1:0] want, acc, bb, ee; integer k;
  reg [2*WIDTH+3:0] t;
  function [WIDTH-1:0] pw(input [WIDTH-1:0] bs, input [WIDTH-1:0] ex, input [WIDTH-1:0] md);
    reg [2*WIDTH+3:0] a, x; integer q;
    begin a=1; x=bs; for(q=0;q<WIDTH;q=q+1) begin if(ex[q]) a=(a*x)%md; x=(x*x)%md; end pw=a%md; end
  endfunction
  task run(input [WIDTH-1:0] bs, input [WIDTH-1:0] ex, input [WIDTH-1:0] md);
    begin
      @(negedge clk); b=bs;e=ex;m=md;start=1; @(negedge clk); start=0; cyc=1;
      while(!done && cyc<200000) begin @(negedge clk); cyc=cyc+1; end
      want=pw(bs,ex,md);
      if(r!==want) begin errs=errs+1; if(errs<5) $display("MISMATCH b=%0d e=%0d m=%0d got=%0d want=%0d",bs,ex,md,r,want); end
      if(ex=={WIDTH{1'b1}}) $display("CYC allones m=%0d cyc=%0d", md, cyc);
      if(ex==0) $display("CYC zero cyc=%0d", cyc);
    end
  endtask
  reg [31:0] rr;
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    run(0,0,7); run(5,0,7); run(0,5,7); run(7,13,11); run(2,10,1000>= (1<<WIDTH) ? 3 : 1000);
    run(1,{WIDTH{1'b1}},{WIDTH{1'b1}}); run(2,{WIDTH{1'b1}},{1'b0,{(WIDTH-1){1'b1}}}|1);
    run(3,{WIDTH{1'b1}},{WIDTH{1'b1}}-1);
    run({WIDTH{1'b1}}-1,{WIDTH{1'b1}},{WIDTH{1'b1}}); run(1,5,2); run(1,{WIDTH{1'b1}},2); run(2,{WIDTH{1'b1}},3);
    for(i=0;i<N;i=i+1) begin
      rr=$random(seed); m=(rr % ((1<<WIDTH)-2))+2;
      rr=$random(seed); b=rr % m; rr=$random(seed); e=rr;
      run(b,e,m);
    end
    $display("DONE WIDTH=%0d errs=%0d", WIDTH, errs);
    $finish;
  end
endmodule
