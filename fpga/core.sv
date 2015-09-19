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
	  //disp.led[3:0] = ir_in;
      
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

typedef logic [15:0] op_t;
typedef logic [31:0] data_t;
typedef logic [4:0] slot_t;
typedef logic [4:0] alu_cmd_t;

interface op_pipe_ctrl;
   logic flush;
   
endinterface

interface decoded_op;
   logic ready;
   logic is_alu;
   logic is_imm;
   logic is_hlt;
   logic fetch_slot_1, fetch_slot_2;
   
   logic [7:0] imm;
   alu_cmd_t alu_cmd;
   slot_t slot_1, slot_2;
endinterface

module decoder
  (input op_t op_in,
   input slot_t offset,
   decoded_op op_out);

   always_comb begin
      if (op_in[0]) begin
         op_out.is_alu = '1;
         op_out.fetch_slot_1 = '1;
         op_out.fetch_slot_2 = '1;
         op_out.is_imm = '0;
      end
      else begin
         op_out.is_alu = '0;
         op_out.fetch_slot_1 = '0;
         op_out.fetch_slot_2 = '0;
         op_out.is_imm = '1;
      end
      
      op_out.is_hlt = op_in[1:0] == 2'b10;

      op_out.imm = op_in[15:8];
      op_out.alu_cmd = op_in[5:1];
      if (op_out.fetch_slot_1)
        op_out.slot_1 = op_in[10:6] + offset;
      else
        op_out.slot_1 = 'X;
      if (op_out.fetch_slot_2)
        op_out.slot_2 = op_in[15:11] + offset;
      else
        op_out.slot_2 = 'X;
   end
   
endmodule // decoder

interface ring_bus;
   logic clock;
   logic we;
   slot_t slot_1, slot_2;
   data_t read_1, read_2;
   data_t write;
   modport read_master(output clock, slot_1, slot_2, input read_1, read_2);
   modport write_master(output we, write);
   modport slave(input clock, we, slot_1, slot_2, write, output read_1, read_2);
endinterface

module sp_async_ram
  (input data_t write,
   input logic clock,
   input slot_t read_addr,
   input slot_t write_addr,
   input logic we,
   output data_t read
   );
   	altdpram	ram
       (.data(write),
		.inclock (clock),
		.outclock (clock),
		.rdaddress (read_addr),
		.wraddress (write_addr),
		.wren (we),
		.q (read),
		.aclr (1'b0),
		.byteena (1'b1),
		.inclocken (1'b1),
		.outclocken (1'b1),
		.rdaddressstall (1'b0),
		.rden (1'b1),
		.wraddressstall (1'b0));
   defparam
	 ram.indata_aclr = "OFF",
	 ram.indata_reg = "INCLOCK",
	 ram.intended_device_family = "Cyclone V",
	 ram.lpm_type = "altdpram",
	 ram.outdata_aclr = "OFF",
	 ram.outdata_reg = "UNREGISTERED",
	 ram.ram_block_type = "MLAB",
	 ram.rdaddress_aclr = "OFF",
	 ram.rdaddress_reg = "UNREGISTERED",
	 ram.rdcontrol_aclr = "OFF",
	 ram.rdcontrol_reg = "UNREGISTERED",
	 ram.read_during_write_mode_mixed_ports = "NEW_DATA",//"CONSTRAINED_DONT_CARE",
	 ram.width = 32,
	 ram.widthad = 5,
	 ram.width_byteena = 1,
	 ram.wraddress_aclr = "OFF",
	 ram.wraddress_reg = "INCLOCK",
	 ram.wrcontrol_aclr = "OFF",
	 ram.wrcontrol_reg = "INCLOCK";
   
endmodule


module ring
  (ring_bus.slave bus,
   output data_t last_data,
   output slot_t write_addr);
   
   //data_t store [2**$bits(slot_t)];
   slot_t read_addr1, read_addr2;
//, write_addr = '0;
   
   sp_async_ram store1
     (.clock(bus.clock),
      .write(bus.write),
      .read_addr(read_addr1),
      .write_addr,
      .we(bus.we),
      .read(bus.read_1));
   sp_async_ram store2
     (.clock(bus.clock),
      .write(bus.write),
      .read_addr(read_addr2),
      .write_addr,
      .we(bus.we),
      .read(bus.read_2));
   
   always_comb begin
      read_addr1 = write_addr - bus.slot_1;
      read_addr2 = write_addr - bus.slot_2;
      $display("ring: new read w:%h | %h %h => %h %h", write_addr, bus.slot_1, bus.slot_2, read_addr1, read_addr2);
      $display("ring: data %h %h", bus.read_1, bus.read_2);
      /*bus.read_1 = store[ptr - bus.slot_1 + 1];
      bus.read_2 = store[ptr - bus.slot_2 + 1];*/
   end
   always_ff @(posedge bus.clock) begin
      if (bus.we) begin
         $display("ring: writing %h", bus.write);
         write_addr <= write_addr + 1;
         last_data <= bus.write;
      end
   end
endmodule

module decode_stage
  (input logic clock,
   ram_bus.master code_ram,
   input logic stall,
   input logic running,
   decoded_op decoded,
   input slot_t offset);

   logic [31:0] ip;
   op_t op_coded;
   logic        op_ready;
   
   decoder dec(.offset,
               .op_in(op_coded),
               .op_out(decoded));
   always_comb begin
      code_ram.addr = ip;
      code_ram.clock = clock;
      code_ram.write = '0;
      code_ram.we = '0;
   end

   always_ff @(posedge clock) begin
      if (running) begin
         if (!stall) begin
            ip <= ip+1;
            op_ready <= '1;
            op_coded <= code_ram.read;
            if (op_ready)
              decoded.ready <= '1;
         end
         else begin
            decoded.ready <= '0;
            op_ready <= '1;
         end
      end
      else begin
         ip <= '0;
         decoded.ready <= '0;
         op_ready <= '1;
      end
   end
endmodule

interface fetched_op;
   logic ready;
   logic is_alu, is_imm;
   
   alu_cmd_t alu_cmd;
   data_t arg_1, arg_2;
endinterface

module fetch_stage
  (input logic clock,
   input logic stall,
   ring_bus.read_master ring,
   decoded_op decoded,
   fetched_op fetched);

   always_comb begin
      ring.clock = clock;
      ring.slot_1 = decoded.slot_1;
      ring.slot_2 = decoded.slot_2;
   end
   
   always_ff @(posedge clock) begin
      if (decoded.ready && !decoded.is_hlt) begin
         
         if (decoded.fetch_slot_1)
           fetched.arg_1 <= ring.read_1;
         else
           fetched.arg_1 <= {'0, decoded.imm};
         if (decoded.fetch_slot_2)
           fetched.arg_2 <= ring.read_2;
         else
           fetched.arg_2 <= 'X;
         
         fetched.is_alu <= decoded.is_alu;
         fetched.is_imm <= decoded.is_imm;
         fetched.alu_cmd <= decoded.alu_cmd;
         fetched.ready <= '1;
      end
      else fetched.ready <= '0;
   end
endmodule

module execute_stage
  (input logic clock,
   ring_bus.write_master ring,
   fetched_op fetched);

   data_t result;
   
   always_comb begin
      //ring.clock = clock;
      ring.write = result;
   end
   
   always_ff @(posedge clock) begin
      if (fetched.ready) begin
         ring.we <= '1;
         unique case ({fetched.is_imm, fetched.is_alu})
           2'b10: result <= fetched.arg_1;
           2'b01: result <= fetched.arg_1 + fetched.arg_2;
         endcase
      end
      else begin
         ring.we <= '0;
      end
   end
   
endmodule

module core
  (input logic clock,
   core_control.slave ctrl,
   ram_bus.master code_ram,
   display disp);

   data_t last_data;
   
   ring_bus ring_bus();
   slot_t w_a;
   
   ring ring(.bus(ring_bus.slave), .last_data, .write_addr(w_a));
   
   decoded_op decoded();
   decode_stage decode
     (.clock, .code_ram, .stall('0), .decoded, .running(ctrl.running),
      .offset(w_a));
   
   fetched_op fetched();
   fetch_stage fetch
     (.clock, .decoded, .stall('0), .ring(ring_bus.read_master), .fetched);

   execute_stage exec
     (.clock, .ring(ring_bus.write_master), .fetched);

   always_comb begin
      disp.led[9:4] = last_data;
      disp.led[3] = ctrl.running;
      disp.led[2] = decoded.ready;
      disp.led[1] = fetched.ready;
      if (last_data == '1)
        disp.led[0] = '1;
      else
        disp.led[0] = '0;
   end
   always_ff @(negedge clock) begin
      if (ctrl.running) begin
         if (decoded.ready)
           $display("- decoded: %p", decoded);
         else
           $display("- decode: off");
         if (fetched.ready)
           $display("- fetched: %p", fetched);
         else
           $display("- fetch: off");
         if (ring_bus.we)
           $display("- wrote back: %h", ring_bus.write);
         $display("- led %b", disp.led);
      end
      else begin // reset
         $display("core: off");
      end
   end
   always_ff @(posedge clock) begin
   end
endmodule
