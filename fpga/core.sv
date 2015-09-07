interface ram_bus #(width=16, depth=9);
   
   logic clock;
   logic [depth-1:0] addr;
   logic [width-1:0] write;
   logic             we;
   logic [width-1:0] read;
   
   modport master(output clock, addr, write, we, input read);
   modport slave(input clock, addr, write, we, output read);
endinterface

interface core_control;
   logic             running;

   modport master(output running);
   modport slave(input running);
endinterface

interface display
  (output logic [9:0] led);
endinterface

module main
  (input logic clk50,
   output logic [9:0] led);
   
   display disp(.led);
   ram_bus jtag_ram_bus();
   ram_bus core_ram_bus();
   core_control c0_ctrl();
   
   dp_ram #(.n_word(512)) code_ram
     (.bus_a(jtag_ram_bus.slave),
      .bus_b(core_ram_bus.slave));

   jtag j
     (.disp,
      .ram(jtag_ram_bus.master),
      .core_ctrl(c0_ctrl.master));

   core c0(.clock(clk50),
           .code_ram(core_ram_bus.master),
           .disp,
           .ctrl(c0_ctrl.slave));
   
endmodule

module jtag
  (display disp,
   ram_bus.master ram,
   core_control.master core_ctrl);
   
   logic                       tck, tdo, tdi,
                               sdr, udr, uir, cdr;
   logic [3:0]                 ir_in;
   
   sld_virtual_jtag
     #(.sld_auto_instance_index("NO"),
	   .sld_instance_index(12),
	   .sld_ir_width(4)) virtual_jtag
     (.tdi(tdi),
	  .tdo(tdo),
	  .ir_in(ir_in),
	  .virtual_state_sdr(sdr),
      .virtual_state_cdr(cdr),
	  .virtual_state_udr(udr),
      .virtual_state_uir(uir),
	  .tck(tck));

   logic [15:0]                dr_data;
   
   always_comb begin
	  disp.led[3:0] = ir_in;
      
      ram.write = dr_data;
      ram.clock = tck;
   end
   
   always_ff @(posedge tck) begin
      unique case (ir_in)
        4'b1101: begin // set address
           if (sdr)
		     ram.addr <= { tdi, ram.addr[8:1] };
        end
        4'b1001: begin // read
           if (uir)
             dr_data <= ram.read;
           if (cdr || sdr) begin
              tdo <= dr_data[0];
              dr_data <= { 1'bX, dr_data[8:1] };
           end
        end
        4'b1000: begin // write
           if (sdr)
             dr_data <= { tdi, dr_data[15:1] };
           if (udr)
             ram.we <= 1'b1;
        end
        4'b1100: begin // core ctrl
           if (sdr)
             core_ctrl.running <= tdi;
        end
        default: begin
        end
      endcase
      if (ram.we) ram.we <= 1'b0;
   end
	
endmodule

module dp_ram #(n_word)
   (ram_bus.slave bus_a,
    ram_bus.slave bus_b);
      
   altsyncram ram
       (.address_a (bus_a.addr),
	    .address_b (bus_b.addr),
	    .clock0 (bus_a.clock),
	    .clock1 (bus_b.clock),
	    .data_a (bus_a.write),
	    .data_b (bus_b.write),
	    .wren_a (bus_a.we),
	    .wren_b (bus_b.we),
	    .q_a (bus_a.read),
	    .q_b (bus_b.read),
	    .aclr0 (1'b0),
	    .aclr1 (1'b0),
	    .addressstall_a (1'b0),
	    .addressstall_b (1'b0),
	    .byteena_a (1'b1),
	    .byteena_b (1'b1),
	    .clocken0 (1'b1),
	    .clocken1 (1'b1),
	    .clocken2 (1'b1),
	    .clocken3 (1'b1),
	    .eccstatus (),
	    .rden_a (1'b1),
	    .rden_b (1'b1));
   defparam
	 ram.address_reg_b = "CLOCK1",
	 ram.clock_enable_input_a = "BYPASS",
	 ram.clock_enable_input_b = "BYPASS",
	 ram.clock_enable_output_a = "BYPASS",
	 ram.clock_enable_output_b = "BYPASS",
	 ram.indata_reg_b = "CLOCK1",
	 ram.intended_device_family = "Cyclone V",
	 ram.lpm_type = "altsyncram",
	 ram.numwords_a = n_word,
	 ram.numwords_b = n_word,
	 ram.operation_mode = "BIDIR_DUAL_PORT",
	 ram.outdata_aclr_a = "NONE",
	 ram.outdata_aclr_b = "NONE",
	 ram.outdata_reg_a = "UNREGISTERED",
	 ram.outdata_reg_b = "UNREGISTERED",
	 ram.power_up_uninitialized = "TRUE",
	 ram.ram_block_type = "M10K",
	 ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	 ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	 ram.widthad_a = $bits(bus_a.addr),
	 ram.widthad_b = $bits(bus_b.addr),
	 ram.width_a = $bits(bus_a.read),
	 ram.width_b = $bits(bus_b.read),
	 ram.width_byteena_a = 1,
	 ram.width_byteena_b = 1,
	 ram.wrcontrol_wraddress_reg_b = "CLOCK1";
endmodule

module core #(op_width = 16)
   (input logic clock,
    core_control.slave ctrl,
    ram_bus.master code_ram,
    display disp);

   logic [31:0] ip, sum;


   always_comb begin
      code_ram.addr = ip;
      code_ram.we = 1'b0;
      code_ram.clock = clock;
      disp.led[9:6] = sum;
   end
   
   always_ff @(posedge clock) begin
      static logic [op_width-1:0] op = 'X;
      if (ctrl.running) begin
         $display("core ON");
         op = code_ram.read;
         $display("- op : 0x%h", op);
         sum <= sum + code_ram.read;
         
         $display("- fetch 0x%h", ip);
         ip <= ip+1;
      end
      else begin // reset
         $display("core OFF");
         ip <= '0;
         sum <= '0;
      end
      $display("==============");
   end
endmodule
