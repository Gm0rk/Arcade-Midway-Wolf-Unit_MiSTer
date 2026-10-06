//============================================================================
//  altsyncram - behavioural model for Verilator and lint (simulation only)
//
//  Covers the one configuration the core uses for its CMOS: BIDIR_DUAL_PORT,
//  both ports on clock0, inputs registered, outputs unregistered, new data
//  on a same-port read during write. Quartus supplies the real megafunction;
//  this file is not part of the core's file list.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module altsyncram #(
	parameter operation_mode                     = "BIDIR_DUAL_PORT",
	parameter intended_device_family             = "Cyclone V",
	parameter lpm_type                           = "altsyncram",
	parameter ram_block_type                     = "M10K",
	parameter width_a                            = 16,
	parameter widthad_a                          = 14,
	parameter numwords_a                         = 16384,
	parameter width_b                            = 16,
	parameter widthad_b                          = 14,
	parameter numwords_b                         = 16384,
	parameter width_byteena_a                    = 1,
	parameter width_byteena_b                    = 1,
	parameter address_reg_b                      = "CLOCK0",
	parameter indata_reg_b                       = "CLOCK0",
	parameter wrcontrol_wraddress_reg_b          = "CLOCK0",
	parameter outdata_reg_a                      = "UNREGISTERED",
	parameter outdata_reg_b                      = "UNREGISTERED",
	parameter outdata_aclr_a                     = "NONE",
	parameter outdata_aclr_b                     = "NONE",
	parameter clock_enable_input_a               = "BYPASS",
	parameter clock_enable_input_b               = "BYPASS",
	parameter clock_enable_output_a              = "BYPASS",
	parameter clock_enable_output_b              = "BYPASS",
	parameter read_during_write_mode_port_a      = "NEW_DATA_NO_NBE_READ",
	parameter read_during_write_mode_port_b      = "NEW_DATA_NO_NBE_READ",
	parameter read_during_write_mode_mixed_ports = "DONT_CARE",
	parameter power_up_uninitialized             = "FALSE"
)
(
	input                      clock0,
	input      [widthad_a-1:0] address_a,
	input        [width_a-1:0] data_a,
	input                      wren_a,
	output reg   [width_a-1:0] q_a,
	input                      clock1,
	input      [widthad_b-1:0] address_b,
	input        [width_b-1:0] data_b,
	input                      wren_b,
	output reg   [width_b-1:0] q_b,
	input                      aclr0, aclr1, addressstall_a, addressstall_b,
	input                      byteena_a, byteena_b,
	input                      clocken0, clocken1, clocken2, clocken3,
	input                      rden_a, rden_b,
	output                     eccstatus
);

reg [width_a-1:0] mem [0:numwords_a-1];

integer i;
initial for (i = 0; i < numwords_a; i = i + 1) mem[i] = '0;

always @(posedge clock0) begin
	if (wren_a && address_a < numwords_a) mem[address_a] <= data_a;
	if (wren_b && address_b < numwords_b) mem[address_b] <= data_b;
	q_a <= wren_a ? data_a : (address_a < numwords_a) ? mem[address_a] : '0;
	q_b <= wren_b ? data_b : (address_b < numwords_b) ? mem[address_b] : '0;
end

assign eccstatus = 1'b0;

endmodule
