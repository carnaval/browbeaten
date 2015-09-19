`timescale 10ns / 1ns

module ro_literal_ram_model
  #(width=16, logic [width-1:0] data [])
   (ram_bus.slave bus);
   
   always @(posedge bus.clock) begin
      bus.read <= data[bus.addr];
   end
endmodule

module test;

   logic clock;
   localparam [15:0] code_data []
     = {{8'h0a, 8'h00}, // li 5
        {8'h0b, 8'h00}, // li 4
        {8'h0c, 8'h00}, // li 3
        {8'h0d, 8'h00}, // li 2
        {8'h0e, 8'h00}, // li 1
        {8'h0f, 8'h00}, // li 0
        {5'h4, 5'h3, 5'h3, 1'b1}, // alu 3 $2 $1
//        {5'h1, 5'h2, 5'h3, 1'b1}, // alu 3 $2 $1
        {14'h0, 2'b10}}; // hlt
   display disp();
   ram_bus code_ram();
   core_control ctrl();
   core c0(.clock, .ctrl, .code_ram, .disp);
   ro_literal_ram_model
     #(.data(code_data)) ram_model
       (code_ram.slave);
   
   always begin
      #1 clock = ~clock;
      $display("====================");
      #1 clock = ~clock;
      $display("====================");
   end
   
   
   initial begin
      $display("RAM %p", code_data);
      clock = '0;
      ctrl.running = 0;
      @(posedge clock);
      @(posedge clock);
      ctrl.running = '1;
      #25;
      $finish;
   end
endmodule
