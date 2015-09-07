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
     = {'hff00, 'h0f0f};
   display disp();
   ram_bus code_ram();
   core_control ctrl();
   core c0(.clock, .ctrl, .code_ram, .disp);
   ro_literal_ram_model
     #(.data(code_data)) ram_model
       (code_ram.slave);
   
   always #1 clock = ~clock;
   
   
   initial begin
      clock = '0;
      ctrl.running = 0;
      @(posedge clock);
      @(posedge clock);
      ctrl.running = '1;
      #10;
      $display(c0.sum);
      $finish;
   end
endmodule
